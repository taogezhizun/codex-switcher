import AppKit
import AccountsCore
import Foundation
import Darwin

enum DesktopCompatibilityError: Error, LocalizedError {
    case unsupportedApplication
    case missingCLI

    var errorDescription: String? {
        switch self {
        case .unsupportedApplication:
            return "所选应用不是 Codex 桌面 App。请在设置中重新选择。"
        case .missingCLI:
            return "未找到 Codex 桌面 App 的内置程序，可能是桌面版更新后布局发生变化。请更新 Codex Switcher 或在设置中重新选择 Codex App；无需重新登录账号。"
        }
    }
}

@MainActor final class Desktop: SwitchEnvironment {
    static let bundleID = "com.openai.codex"
    let application: URL
    let home: URL
    let store: AccountStore
    var phase: (String) -> Void = { _ in }
    var homePath: String { home.path }
    var authURL: URL { home.appendingPathComponent("auth.json") }
    var executable: URL { get throws { try Self.resolveExecutable(in: application) } }

    /// Resolve on every operation because the desktop may update in place while we are running.
    static func resolveExecutable(in application: URL) throws -> URL {
        guard Bundle(url: application)?.bundleIdentifier == bundleID else {
            throw DesktopCompatibilityError.unsupportedApplication
        }
        // Use the official launcher for the packaged CLI; retain support for earlier desktop builds.
        let entries = ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"]
        for entry in entries {
            let url = application.appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        throw DesktopCompatibilityError.missingCLI
    }

    static func discover() -> URL? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL { return running }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
    init(application: URL, home: URL, store: AccountStore) {
        self.application = application; self.home = home; self.store = store
    }
    func preflight() throws {
        _ = try executable
        try PrivateFiles.rejectSymlinks(home)
        let text = try PrivateFiles.read(home.appendingPathComponent("config.toml"))
        if let text {
            guard let config = String(data: text, encoding: .utf8) else { throw AccountsError.message("无法读取认证配置。") }
            try StoragePolicy.validate(config: config)
        }
        let control = home.appendingPathComponent("app-server-control/app-server-control.sock")
        if FileManager.default.fileExists(atPath: control.path) {
            throw AccountsError.message("检测到 app-server 守护进程。第一版不会停止共享守护进程，请先通过 Codex 的正常方式关闭它。")
        }
        // A local policy may override user config. Do not silently weaken managed auth.
        let policies = ["/Library/Application Support/Codex/requirements.toml", "/etc/codex/requirements.toml"]
        if policies.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            throw AccountsError.message("检测到受管理配置，第一版不能确认认证存储方式，已停止切换。")
        }
    }
    func stopDesktop() async throws {
        phase("正在正常退出桌面 App…")
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        let children = try childCodexProcesses(of: apps.map(\.processIdentifier))
        for app in apps {
            if !app.terminate() { throw AccountsError.message("桌面 App 未接受退出请求，请手动退出后重试。") }
        }
        for _ in 0..<150 {
            if apps.allSatisfy(\.isTerminated) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard apps.allSatisfy(\.isTerminated) else {
            throw AccountsError.message("桌面 App 尚未退出。原认证未更改，请处理 App 中的退出提示后重试。")
        }
        for _ in 0..<80 {
            if children.allSatisfy({ kill($0, 0) != 0 }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard children.allSatisfy({ kill($0, 0) != 0 }) else {
            throw AccountsError.message("桌面 App 的后台进程仍在运行。原认证未更改，请等待进程正常退出。")
        }
        try preflight() // A daemon may have appeared while the desktop was closing.
    }
    func startDesktop() async throws {
        phase("正在重新打开桌面 App…")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: application, configuration: config)
    }
    func readLive() throws -> Data? { try PrivateFiles.read(authURL) }
    func writeLive(_ data: Data?) throws {
        phase("正在更新认证…")
        if let data { try PrivateFiles.write(data, to: authURL) } else { try PrivateFiles.remove(authURL) }
    }
    func saveBackup(_ backup: SwitchBackup) throws { try store.saveBackup(backup) }
    func archiveDeparting(_ data: Data) throws { _ = try store.upsert(data) }

    private func childCodexProcesses(of parents: [pid_t]) throws -> [pid_t] {
        let proc = Process(); let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "pid=,ppid=,comm="]
        proc.standardOutput = pipe; proc.standardError = FileHandle.nullDevice
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw AccountsError.message("无法检查桌面后台进程，已停止切换。") }
        let rows = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> (pid_t, pid_t, String)? in
            let fields = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 3, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { return nil }
            return (pid, parent, String(fields[2]))
        }
        var descendants = Set(parents)
        for _ in 0..<20 {
            let before = descendants.count
            for row in rows where descendants.contains(row.1) { descendants.insert(row.0) }
            if descendants.count == before { break }
        }
        return rows.filter { descendants.contains($0.0) && $0.2.hasPrefix(application.path + "/Contents/Resources/codex") }.map { $0.0 }
    }
}
