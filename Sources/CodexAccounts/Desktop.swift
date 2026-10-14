import AppKit
import AccountsCore
import Foundation

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
    var confirmTermination: (DesktopShutdownPrompt) async -> Bool = { _ in false }
    var terminationAlreadyApproved = false
    private var shutdown: DesktopShutdown?
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
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
        let selected = application.resolvingSymlinksInPath()
        guard apps.allSatisfy({ $0.bundleURL?.resolvingSymlinksInPath() == selected }),
              let main = Bundle(url: selected)?.executableURL?.resolvingSymlinksInPath().path else {
            throw AccountsError.message("正在运行的 Codex 与所选应用不一致。请退出其他副本或在设置中重新选择。")
        }
        let cliPaths = ["Contents/Resources/codex", "Contents/Resources/codex-cli/bin/codex",
                        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        let shutdown = DesktopShutdown(mainExecutable: main,
            cliExecutables: Set(cliPaths.map { selected.appendingPathComponent($0).resolvingSymlinksInPath().path }),
            readProcesses: { try SystemDesktopProcesses.snapshot(matchingExecutableNames: [URL(fileURLWithPath: main).lastPathComponent, "codex"]) },
            requestQuit: { apps.forEach { _ = $0.terminate() } }, sendSignal: SystemDesktopProcesses.signal)
        self.shutdown = shutdown
        try await shutdown.stop(terminationAlreadyApproved: terminationAlreadyApproved, confirm: confirmTermination, phase: phase)
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
        guard let shutdown else { throw AccountsError.message("尚未确认 Codex 已退出，已停止写入认证。") }
        try preflight()
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).allSatisfy(\.isTerminated) else {
            throw AccountsError.message("Codex 已重新启动，已停止写入认证。请退出后重试；已有备份会保留。")
        }
        try shutdown.verifyStopped() // Covers switching, recovery and rollback after a failed launch.
        phase("正在更新认证…")
        if let data { try PrivateFiles.write(data, to: authURL) } else { try PrivateFiles.remove(authURL) }
    }
    func saveBackup(_ backup: SwitchBackup) throws { try store.saveBackup(backup) }
    func archiveDeparting(_ data: Data) throws { _ = try store.upsert(data) }

}
