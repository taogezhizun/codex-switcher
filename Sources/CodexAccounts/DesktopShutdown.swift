import Foundation
import AccountsCore
import Darwin

struct DesktopProcess: Equatable {
    struct Identity: Hashable {
        let pid: Int32
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
        let executable: String
        let uid: UInt32
    }
    let identity: Identity
    let parent: Int32
    let zombie: Bool
}

struct DesktopShutdownPrompt {
    let mainAppRunning: Bool
    let processCount: Int
    var title: String { mainAppRunning ? "Codex 尚未退出" : "Codex 后台仍在运行" }
}

/// Tracks one shutdown attempt across confirmation, including children that become orphans.
/// Unknown CLI instances and restarted roots are blockers, never force-termination targets.
@MainActor final class DesktopShutdown {
    let mainExecutable: String
    let cliExecutables: Set<String>
    private let readProcesses: () throws -> [DesktopProcess]
    private let requestQuit: () -> Void
    private let sendSignal: (DesktopProcess.Identity, Int32) throws -> Void
    private let wait: () async throws -> Void
    private let gracefulPolls: Int
    private let terminationPolls: Int
    private var known = Set<DesktopProcess.Identity>()
    private var roots = Set<DesktopProcess.Identity>()
    private var stopped = false

    init(mainExecutable: String, cliExecutables: Set<String>,
         readProcesses: @escaping () throws -> [DesktopProcess], requestQuit: @escaping () -> Void,
         sendSignal: @escaping (DesktopProcess.Identity, Int32) throws -> Void,
         wait: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 250_000_000) },
         gracefulPolls: Int = 60, terminationPolls: Int = 20) {
        self.mainExecutable = mainExecutable; self.cliExecutables = cliExecutables
        self.readProcesses = readProcesses; self.requestQuit = requestQuit; self.sendSignal = sendSignal
        self.wait = wait; self.gracefulPolls = gracefulPolls; self.terminationPolls = terminationPolls
    }

    func stop(terminationAlreadyApproved: Bool = false, confirm: (DesktopShutdownPrompt) async -> Bool, phase: (String) -> Void) async throws {
        try Task.checkCancellation()
        stopped = false
        let initial = try readProcesses()
        roots = Set(initial.filter { !$0.zombie && $0.identity.executable == mainExecutable }.map(\.identity))
        known = roots
        rememberChildren(initial)
        if !terminationAlreadyApproved {
            phase("正在退出 Codex；如有退出确认，请在 Codex 中完成…")
            requestQuit()
            for _ in 0..<gracefulPolls {
                try Task.checkCancellation()
                let rows = try readProcesses(); rememberChildren(rows)
                if activeWriters(rows).isEmpty { stopped = true; return }
                try await wait()
            }
            let rows = try readProcesses(); rememberChildren(rows)
            let remaining = activeWriters(rows)
            if remaining.isEmpty { stopped = true; return }
            try requireOwned(remaining)
            phase("等待确认如何处理尚未退出的 Codex。原认证未更改。")
            let prompt = DesktopShutdownPrompt(mainAppRunning: remaining.contains { roots.contains($0.identity) }, processCount: remaining.count)
            guard await confirm(prompt) else {
                throw AccountsError.message("已取消切换。Codex 未完全退出，原认证未更改。请完成退出后再试。")
            }
        }
        try Task.checkCancellation()
        // Freeze the approved set. A restart or newly discovered process needs a new attempt.
        phase("正在结束已确认的 Codex 进程…")
        for signal in [SIGTERM, SIGKILL] {
            let remaining = activeWriters(try readProcesses())
            try requireOwned(remaining)
            for process in remaining {
                // The system adapter rechecks identity immediately before each signal.
                try sendSignal(process.identity, signal)
            }
            for _ in 0..<terminationPolls {
                try Task.checkCancellation()
                let remaining = activeWriters(try readProcesses())
                try requireOwned(remaining)
                if remaining.isEmpty { stopped = true; return }
                try await wait()
            }
        }
        let final = activeWriters(try readProcesses())
        try requireOwned(final)
        if final.isEmpty { stopped = true; return }
        throw AccountsError.message("Codex 仍未完全退出，已停止切换，原认证未更改。请在活动监视器中检查后重试。")
    }

    func verifyStopped() throws {
        guard stopped, activeWriters(try readProcesses()).isEmpty else {
            throw AccountsError.message("Codex 或其后台进程已重新启动，已停止写入认证。请退出后重试；已有备份会保留。")
        }
    }

    private func activeWriters(_ rows: [DesktopProcess]) -> [DesktopProcess] {
        rows.filter { row in
            !row.zombie && (row.identity.executable == mainExecutable || cliExecutables.contains(row.identity.executable)
                || known.contains { $0.pid == row.identity.pid && $0.startedSeconds == row.identity.startedSeconds
                    && $0.startedMicroseconds == row.identity.startedMicroseconds && $0.uid == row.identity.uid })
        }
    }
    private func requireOwned(_ rows: [DesktopProcess]) throws {
        guard rows.allSatisfy({ known.contains($0.identity) }) else {
            throw AccountsError.message("检测到来源未确认的 Codex 后台进程或新启动的实例，已停止切换。请退出其他 Codex / CLI 后重试；不会自动结束这些进程。")
        }
    }
    private func rememberChildren(_ rows: [DesktopProcess]) {
        var descendants = Set(rows.filter { known.contains($0.identity) && !$0.zombie }.map { $0.identity.pid })
        var changed = true
        while changed {
            let before = descendants.count
            for row in rows where !row.zombie && descendants.contains(row.parent) { descendants.insert(row.identity.pid) }
            changed = descendants.count != before
        }
        for row in rows where !row.zombie && descendants.contains(row.identity.pid) && cliExecutables.contains(row.identity.executable) {
            known.insert(row.identity)
        }
    }
}

/// Only process metadata is read: no argv, environment, credential files or task contents.
enum SystemDesktopProcesses {
    static func snapshot(matchingExecutableNames: Set<String> = []) throws -> [DesktopProcess] {
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard bytes > 0 else { throw inspectionError() }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 256)
        let capacity = Int32(pids.count * MemoryLayout<Int32>.size)
        let used = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_UID_ONLY), getuid(), $0.baseAddress, capacity) }
        guard used > 0, used < capacity else { throw inspectionError() }
        return try pids.prefix(Int(used) / MemoryLayout<Int32>.size).filter { $0 > 0 }.compactMap {
            try inspect($0, allowUnknownPath: true, matchingExecutableNames: matchingExecutableNames)
        }
    }
    static func inspect(_ pid: Int32, allowUnknownPath: Bool = false, matchingExecutableNames: Set<String> = []) throws -> DesktopProcess? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout.size(ofValue: info))
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected)
        if size == 0, errno == ESRCH { return nil }
        guard size == expected else { throw inspectionError() }
        let zombie = info.pbi_status == SZOMB
        var path = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        if length == 0, zombie { return nil } // No remaining code can write credentials.
        if length == 0, errno == ESRCH { return nil }
        // An unrelated process may outlive its deleted executable after an app update.
        // Keep its identity/ancestry but no executable claim. Matching Codex names and
        // direct signal targets must remain readable; uncertainty blocks their use.
        let name = withUnsafeBytes(of: info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard length > 0 || (allowUnknownPath && !matchingExecutableNames.contains(name)) else { throw inspectionError() }
        let executable = length > 0 ? URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path : ""
        let identity = DesktopProcess.Identity(pid: pid, startedSeconds: info.pbi_start_tvsec,
                                              startedMicroseconds: info.pbi_start_tvusec,
                                              executable: executable,
                                              uid: info.pbi_uid)
        return DesktopProcess(identity: identity, parent: Int32(info.pbi_ppid), zombie: zombie)
    }
    static func signal(_ identity: DesktopProcess.Identity, _ signal: Int32) throws {
        guard identity.pid > 1, identity.pid != getpid(), identity.uid == getuid() else { throw inspectionError() }
        guard let current = try inspect(identity.pid), !current.zombie else { return }
        guard current.identity == identity else { throw inspectionError() }
        // Darwin has no atomic pidfd signal API. Check birth time/path/uid immediately before kill.
        if kill(identity.pid, signal) != 0, errno != ESRCH {
            throw AccountsError.message("无法结束已确认的 Codex 进程，已停止切换。请检查系统权限或手动退出后重试。")
        }
    }
    private static func inspectionError() -> AccountsError {
        .message("无法可靠核对 Codex 进程身份，已停止切换。请完全退出 Codex 后重试。")
    }
}
