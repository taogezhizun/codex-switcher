import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AccountsCore

@MainActor final class AppModel: ObservableObject {
    @Published var hideEmails = true {
        didSet { if !demo { defaults.set(hideEmails, forKey: "hideEmails") } }
    }
    @Published var showMenuBarQuota = true {
        didSet { if !demo { defaults.set(showMenuBarQuota, forKey: "showMenuBarQuota") } }
    }
    @Published private(set) var needsMigration = false
    @Published var showMigration = false
    @Published var appearance = "system" {
        didSet { if !demo { defaults.set(appearance, forKey: "appearance") } }
    }
    @Published var automaticRefresh = true {
        didSet {
            if !demo {
                defaults.set(automaticRefresh, forKey: "automaticRefresh")
                if !automaticRefresh && refreshingAutomatically { cancel() }
                updateNextRefresh()
            }
        }
    }
    @Published private(set) var quotaDisplayDate = Date()
    @Published private(set) var nextRefresh: Date?
    @Published private(set) var refreshingAutomatically = false
    let updates: AppUpdates
    private var refreshSchedule = RefreshSchedule()
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    @Published var accounts: [Account] = []
    @Published var selection: String?
    @Published var currentIdentity: String?
    @Published var busy = false
    @Published var status = "从添加一个账号开始。"
    @Published var error: String?
    @Published var loginCode: String?
    @Published private(set) var recoveryNeedsUnlock = false
    @Published var hasBackup = false
    @Published var awaitingConfirmation = false
    @Published var application: URL?
    @Published var home: URL
    let demo: Bool
    private let defaults: UserDefaults
    private var store: AccountStore?
    private var operation: Task<Void, Never>?
    private var session: IsolatedSession?
    private let quotaReaderFactory: @MainActor () -> any QuotaReading
    private var quotaReaders: [String: any QuotaReading] = [:]
    private var liveCredentialFingerprint: String?
    @Published private(set) var refreshingAccountIDs: Set<String> = []

    init(demo: Bool = false, directory: URL? = nil, defaults: UserDefaults = .standard,
         startServices: Bool = true, vault: KeychainVault = KeychainVault(),
         quotaReaderFactory: @escaping @MainActor () -> any QuotaReading = { QuotaReader() }) {
        self.quotaReaderFactory = quotaReaderFactory
        self.demo = demo
        self.defaults = defaults
        updates = AppUpdates(enabled: !demo)
        let defaultHome = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().appendingPathComponent(".codex")
        home = demo ? URL(fileURLWithPath: "/demo/.codex") : defaults.string(forKey: "codexHome").map { URL(fileURLWithPath: $0) } ?? defaultHome
        application = demo ? nil : defaults.string(forKey: "desktopApplication").map { URL(fileURLWithPath: $0) } ?? Desktop.discover()
        if demo {
            loadDemo()
            if PreviewConfiguration.variant == "migration" { needsMigration = true }
            if PreviewConfiguration.variant == "update" { updates.receiveReminder(version: "0.5.0（演示）", handledBySparkle: false) }
            if (CommandLine.arguments.contains("--demo-empty") || PreviewConfiguration.variant == "empty") { accounts = []; selection = nil; currentIdentity = nil }
            if (CommandLine.arguments.contains("--demo-pending") || PreviewConfiguration.variant == "pending") { awaitingConfirmation = true; hasBackup = true; currentIdentity = selection; status = "演示：桌面 App 已重开，请核对账号。" }
            if (CommandLine.arguments.contains("--demo-dark") || PreviewConfiguration.variant == "dark") { appearance = "dark" }
            if PreviewConfiguration.variant == "recovery-lock" { recoveryNeedsUnlock = true; awaitingConfirmation = true; hasBackup = false }
            return
        }
        showMenuBarQuota = defaults.object(forKey: "showMenuBarQuota") as? Bool ?? true
        automaticRefresh = defaults.object(forKey: "automaticRefresh") as? Bool ?? true
        hideEmails = defaults.object(forKey: "hideEmails") as? Bool ?? true
        appearance = defaults.string(forKey: "appearance") ?? "system"
        do {
            let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .resolvingSymlinksInPath().appendingPathComponent("CodexAccounts", isDirectory: true)
            store = try AccountStore(directory: root, vault: vault)
            accounts = store!.accounts
            selection = accounts.first?.id
            needsMigration = store!.needsMigration
            // Legacy records are accessed only by the explicit migration action.
            if !needsMigration { _ = try loadRecoveryState() }
            refreshFileIdentity()
            status = accounts.isEmpty ? "从添加一个账号开始。" : "选择账号，随时切换。"
        } catch { self.error = "本地账号库无法打开。\(safeMessage(error))" }
        updates.isOperationBusy = { [weak self] in self?.busy ?? false }
        updates.onSessionEnd = { [weak self] in self?.automaticRefreshTick() }
        guard startServices else { return }
        // One timer per model, shared by all windows and the menu bar.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.automaticRefreshTick() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.automaticRefreshTick() }
        }
        Task { @MainActor [weak self] in
            self?.updates.start()
            self?.automaticRefreshTick()
        }
    }
    deinit {
        refreshTimer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
    private func updateNextRefresh() {
        nextRefresh = automaticRefresh ? refreshSchedule.next.filter { !refreshSchedule.paused.contains($0.key) }.values.min() : nil
    }
    func automaticRefreshTick(now: Date = Date()) {
        guard !demo else { return }
        quotaDisplayDate = now
        guard !busy, !updates.sessionInProgress else { return }
        refreshFileIdentity(now: now)
        updateNextRefresh()
        let ids = refreshSchedule.dueIDs(now: now, enabled: automaticRefresh,
                                         blocked: busy || !configured || awaitingConfirmation || updates.sessionInProgress)
        if !ids.isEmpty { refreshAccounts(ids, automatic: true) }
    }

    var selected: Account? { accounts.first { $0.id == selection } }
    var configured: Bool { application != nil && store != nil }
    var credentialActionsBlocked: Bool { needsMigration || busy || updates.sessionInProgress || demo }
    var canCancel: Bool { session != nil || !refreshingAccountIDs.isEmpty }
    func canRefresh(_ id: String) -> Bool {
        !busy && !demo && !updates.sessionInProgress && !awaitingConfirmation &&
        accounts.contains(where: { $0.id == id }) && (!needsMigration || id == currentIdentity)
    }
    var currentAccount: Account? { accounts.first { $0.id == currentIdentity } }
    var preferredColorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    func title(_ account: Account) -> String { AccountPresentation.title(account, hideEmails: hideEmails) }
    func switchBlockReason(_ id: String) -> String? {
        if needsMigration { return "请先迁移已保存账号" }
        if busy { return "请等待当前操作完成" }
        if updates.sessionInProgress { return "请先完成或关闭应用更新窗口" }
        if awaitingConfirmation { return "请先核对或恢复上次切换" }
        if id == currentIdentity { return "已是当前认证，无需再次切换" }
        if !demo && !configured { return "请先在设置中选择桌面 App" }
        if !accounts.contains(where: { $0.id == id }) { return "账号已不存在" }
        return nil
    }
    func checkCurrentIdentity() { if !demo { refreshFileIdentity() } }
    func openDesktop() {
        run("正在打开桌面 App…") {
            try await self.desktop().startDesktop()
            self.status = "桌面 App 已打开。"
        }
    }

    func chooseApplication() {
        guard !busy, !updates.sessionInProgress, !demo else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        panel.message = "选择 Codex 桌面 App（也可能显示为 ChatGPT）。"
        if panel.runModal() == .OK, let url = panel.url {
            guard Bundle(url: url)?.bundleIdentifier == Desktop.bundleID else { error = "所选应用不是 Codex 桌面 App。"; return }
            application = url; defaults.set(url.path, forKey: "desktopApplication")
        }
    }
    func chooseHome() {
        guard !busy, !updates.sessionInProgress, !demo else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.showsHiddenFiles = true
        panel.message = "选择桌面 App 使用的 Codex 目录。通常是用户目录下的 .codex。"
        if panel.runModal() == .OK, let url = panel.url {
            home = url.resolvingSymlinksInPath(); defaults.set(home.path, forKey: "codexHome"); refreshFileIdentity()
        }
    }
    func importCurrent() {
        guard allowCredentialAction() else { return }
        run("正在保存当前账号…") {
            let desktop = try self.desktop(); try desktop.preflight()
            guard let data = try desktop.readLive() else { throw AccountsError.message("当前目录没有 auth.json。请先在桌面 App 登录，或检查设置中的认证目录。") }
            try self.importData(data); self.refreshFileIdentity()
            self.status = "当前账号已保存到本机私有文件。"
        }
    }
    func importFile() {
        guard allowCredentialAction() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "导入你自己的 ChatGPT 登录凭据。文件不会复制到项目目录。"
        if panel.runModal() == .OK, let url = panel.url {
            run("正在导入账号…") {
                guard let data = try PrivateFiles.read(url.resolvingSymlinksInPath()) else { throw AccountsError.message("文件不存在。") }
                try self.importData(data); self.status = "账号已保存到本机私有文件。"
            }
        }
    }
    func addViaLogin(device: Bool = false) {
        guard allowCredentialAction() else { return }
        run("正在准备浏览器登录…") {
            let desktop = try self.desktop()
            let helper = try self.makeSession(); self.session = helper
            do {
                try await helper.rpc.start(executable: desktop.executable, home: helper.home)
                let result = try await helper.rpc.request("account/login/start", ["type": device ? "chatgptDeviceCode" : "chatgpt"])
                guard let loginID = result["loginId"] as? String,
                      let address = result[device ? "verificationUrl" : "authUrl"] as? String,
                      let url = URL(string: address), url.scheme == "https", url.host == "auth.openai.com" else {
                    throw AccountsError.message("登录未返回受支持的 OpenAI 官方授权地址。")
                }
                self.loginCode = result["userCode"] as? String
                self.status = "请在浏览器完成登录。此操作不会切换桌面 App 的当前账号。"
                NSWorkspace.shared.open(url)
                try await helper.rpc.waitForLogin(loginID)
                guard let data = try PrivateFiles.read(helper.home.appendingPathComponent("auth.json")) else { throw AccountsError.message("登录完成，但没有生成可保存的凭据。") }
                try self.importData(data)
                self.status = "新账号已添加，选择它即可切换。"
                await helper.close(); self.session = nil
            } catch {
                await helper.close(); self.session = nil; throw error
            }
        }
    }
    func cancel() {
        operation?.cancel()
        if let session { Task { await session.rpc.close() } }
        quotaReaders.values.forEach { $0.cancel() }
    }
    func refresh(_ id: String, automatic: Bool = false) {
        guard canRefresh(id) else { return }
        refreshAccounts([id], automatic: automatic)
    }
    func refreshAll() {
        guard !busy, !demo, !updates.sessionInProgress else { return }
        refreshFileIdentity()
        refreshAccounts(refreshSchedule.next.keys.sorted(), automatic: false)
    }
    private func refreshAccounts(_ ids: [String], automatic: Bool) {
        guard !busy, !demo, !updates.sessionInProgress, !awaitingConfirmation, !ids.isEmpty else { return }
        let eligible = Set(accounts.map(\.id))
        let requested = ids.filter { eligible.contains($0) && (!needsMigration || $0 == currentIdentity) }
        guard !requested.isEmpty else { return }
        refreshingAutomatically = automatic
        refreshingAccountIDs = Set(requested)
        run("正在刷新 \(requested.count) 个账号的额度…", quietly: automatic) {
            var succeeded = 0
            await QuotaBatch.run(requested) { id in
                if await self.refreshOne(id) { succeeded += 1 }
            }
            if Task.isCancelled {
                self.refreshSchedule.deferCancelled(requested, now: Date())
                self.status = "已取消额度刷新，保留已完成的结果。"
            } else {
                self.status = "额度刷新完成：\(succeeded)/\(requested.count) 个成功。"
            }
            self.refreshingAccountIDs = []; self.refreshingAutomatically = false
            self.checkCurrentIdentity(); self.updateNextRefresh()
        }
    }
    private func refreshOne(_ id: String) async -> Bool {
        guard !Task.isCancelled, let store else { return false }
        let reader = quotaReaderFactory()
        quotaReaders[id] = reader
        var fingerprint: String?
        defer { quotaReaders.removeValue(forKey: id); refreshingAccountIDs.remove(id) }
        do {
            let desktop = try self.desktop(); try desktop.preflight()
            let credentials = try QuotaCredentials.load(id: id, live: desktop.readLive()) { try store.snapshot(id) }
            fingerprint = AuthSnapshot.digest(credentials.snapshot.data)
            let windows = try await reader.read(credentials.snapshot, executable: desktop.executable,
                                                root: store.directory.appendingPathComponent("Sessions", isDirectory: true))
            try Task.checkCancellation()
            try credentials.validate(id: id, live: desktop.readLive()) { try store.snapshot(id) }
            guard !windows.isEmpty, let index = store.accounts.firstIndex(where: { $0.id == id }) else {
                throw AccountsError.message("未返回可用额度，保留上次记录。")
            }
            store.accounts[index].quotas = windows; store.accounts[index].updatedAt = Date()
            store.accounts[index].issue = nil; store.accounts[index].quotaNeedsLogin = false; store.accounts[index].quotaRejectedFingerprint = nil
            try store.save(); sync()
            refreshSchedule.request(id, now: Date())
            refreshSchedule.completed(id, succeeded: true, now: Date())
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { return false }
            let needsLogin = error is QuotaReadError
            if let index = store.accounts.firstIndex(where: { $0.id == id }) {
                store.accounts[index].quotaNeedsLogin = needsLogin
                store.accounts[index].quotaRejectedFingerprint = needsLogin ? fingerprint : nil
                store.accounts[index].issue = needsLogin
                    ? "登录凭据已过期或失效，自动刷新已暂停。请通过浏览器重新添加此账号；当前账号也可在 Codex 登录后保存。"
                    : "刷新未完成，保留上次额度并稍后重试。可检查网络；持续失败时请重新登录此账号。"
                do { try store.save() } catch { self.error = "无法保存额度状态，请检查本地文件权限。" }
                sync()
            }
            if needsLogin { refreshSchedule.pause(id) }
            else { refreshSchedule.completed(id, succeeded: false, now: Date()) }
            return false
        }
    }
    func switchTo(_ id: String) {
        guard !demo else { return }
        if let reason = switchBlockReason(id) { error = reason; return }
        run("正在检查切换条件…") {
            guard let store = self.store else { return }
            // Read the durable journal before accessing a target or stopping the desktop.
            // A crash/relaunch must never let a second switch overwrite a pending backup.
            _ = try self.loadRecoveryState()
            if self.awaitingConfirmation { throw AccountsError.message("请先核对或恢复上次切换，再进行下一次切换。") }
            let target = try store.snapshot(id)
            let desktop = try self.desktop()
            self.invalidateRecoveryState()
            _ = try await SwitchTransaction.run(target: target, environment: desktop)
            self.awaitingConfirmation = true; self.hasBackup = true; self.recoveryNeedsUnlock = false
            self.refreshFileIdentity(); self.sync()
            self.status = "认证已更新，桌面 App 已重开。请在 App 中核对账号；当前还未确认桌面登录成功。"
        }
    }
    func restore() {
        guard allowCredentialAction() else { return }
        run("正在准备恢复…") {
            guard let backup = try self.loadRecoveryState() else { throw AccountsError.message("没有可恢复的备份。") }
            self.invalidateRecoveryState()
            try await SwitchTransaction.restore(backup, environment: self.desktop())
            self.awaitingConfirmation = true; self.hasBackup = true; self.recoveryNeedsUnlock = false
            self.refreshFileIdentity(); self.sync()
            self.status = "原认证已恢复，桌面 App 已重开。请核对账号。"
        }
    }
    func confirmDesktopAccount() {
        guard allowCredentialAction(), !recoveryNeedsUnlock else { return }
        do {
            try store?.confirmBackup(); awaitingConfirmation = false
            status = "已记录你的核对结果。上一次认证备份仍可恢复。"
            automaticRefreshTick()
        } catch { self.error = safeMessage(error) }
    }
    func rename(_ id: String, nickname: String) {
        guard allowCredentialAction(), let store, let i = store.accounts.firstIndex(where: { $0.id == id }) else { return }
        store.accounts[i].nickname = String(nickname.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        do { try store.save(); sync() } catch { self.error = safeMessage(error) }
    }
    func delete(_ id: String) {
        guard allowCredentialAction(), let store else { return }
        do { try store.delete(id); sync(); selection = accounts.first?.id; status = "已从本工具移除账号，桌面 App 的登录未更改。" }
        catch { self.error = safeMessage(error) }
    }
    private func allowCredentialAction() -> Bool {
        guard !demo, !busy, !updates.sessionInProgress else { return false }
        if needsMigration { showMigration = true; return false }
        return true
    }
    func migrateAccounts() {
        guard needsMigration, let store else { return }
        run("正在迁移已保存账号，请处理系统授权提示…") {
            // Keep the main thread responsive while the OS waits for legacy Keychain consent.
            // busy prevents all model/store mutations until this worker has returned.
            try await Task.detached { try store.migrate() }.value
            self.needsMigration = store.needsMigration
            self.sync()
            _ = try self.loadRecoveryState()
            self.showMigration = false
            self.status = "迁移完成。今后的账号操作使用本地文件，旧钥匙串记录保留但不再使用。"
        }
    }
    private func importData(_ data: Data) throws {
        guard let store else { throw AccountsError.message("本地账号库未就绪。") }
        let account = try store.upsert(data); sync(); selection = account.id
        refreshSchedule.request(account.id, now: Date())
    }
    private func desktop() throws -> Desktop {
        guard let application, let store else { throw AccountsError.message("请先在设置中选择 Codex 桌面 App。") }
        let desktop = Desktop(application: application, home: home, store: store)
        desktop.phase = { [weak self] in self?.status = $0 }
        return desktop
    }
    private func makeSession() throws -> IsolatedSession {
        guard let store else { throw AccountsError.message("本地账号库未就绪。") }
        return try IsolatedSession(root: store.directory.appendingPathComponent("Sessions", isDirectory: true))
    }
    private func sync() { accounts = store?.accounts ?? [] }
    private func refreshFileIdentity(now: Date = Date()) {
        let live = try? PrivateFiles.read(home.appendingPathComponent("auth.json"))
        currentIdentity = live.flatMap { try? AuthSnapshot($0).identity }
        let eligible = needsMigration ? accounts.filter { $0.id == currentIdentity } : accounts
        refreshSchedule.reconcile(eligible.map(\.id), now: now)
        let fingerprint = live.map(AuthSnapshot.digest)
        for account in eligible where account.quotaNeedsLogin == true {
            if account.id == currentIdentity, let fingerprint, fingerprint != account.quotaRejectedFingerprint {
                refreshSchedule.request(account.id, now: now)
            } else { refreshSchedule.pause(account.id) }
        }
        if fingerprint != liveCredentialFingerprint, let id = currentIdentity,
           eligible.contains(where: { $0.id == id && $0.quotaNeedsLogin != true }) {
            refreshSchedule.request(id, now: now)
        }
        liveCredentialFingerprint = fingerprint
        updateNextRefresh()
    }
    private func run(_ message: String, quietly: Bool = false, body: @escaping () async throws -> Void) {
        guard !busy, !demo, !updates.sessionInProgress else { return }
        busy = true
        if !quietly { error = nil }
        status = message
        operation = Task {
            do { try await body() }
            catch is CancellationError { status = "已取消。" }
            catch {
                if !quietly { self.error = safeMessage(error) }
                status = quietly ? "自动刷新未完成，保留上次额度并稍后重试。" : "操作未完成。"
            }
            loginCode = nil; busy = false
            // Re-evaluate the live account after the operation, avoiding overlapping helpers.
            Task { @MainActor [weak self] in self?.automaticRefreshTick() }
        }
    }
    private func invalidateRecoveryState() {
        // A failed transaction may already have persisted a pending journal.
        recoveryNeedsUnlock = true
        awaitingConfirmation = true
        hasBackup = false
    }
    private func loadRecoveryState() throws -> SwitchBackup? {
        do {
            guard let store else { throw AccountsError.message("本地账号库未就绪。") }
            let backup = try store.backup()
            hasBackup = backup != nil
            awaitingConfirmation = backup?.isPending ?? false
            recoveryNeedsUnlock = false
            return backup
        } catch {
            invalidateRecoveryState()
            throw error
        }
    }
    func unlockRecoveryRecord() {
        guard allowCredentialAction() else { return }
        error = nil
        do {
            _ = try loadRecoveryState()
            status = awaitingConfirmation ? "恢复记录已读取，请核对上次切换。" : "恢复记录已检查，可以继续使用。"
            automaticRefreshTick()
        } catch { self.error = safeMessage(error) }
    }
    private func safeMessage(_ error: Error) -> String {
        if let known = error as? AccountsError { return known.localizedDescription }
        return "本地操作失败，请检查应用设置、文件权限；迁移旧数据时还需允许钥匙串访问。"
    }
    private func loadDemo() {
        // Entirely synthetic UI data. Demo mode never initializes the store, Keychain or RPC.
        func account(_ id: String, _ title: String, _ email: String, _ plan: String, _ short: Double, _ long: Double) -> Account {
            let object: [String: Any] = ["sub": id, "email": email]
            let payload = try! JSONSerialization.data(withJSONObject: object).base64EncodedString()
            let data = try! JSONSerialization.data(withJSONObject: ["tokens": ["account_id": id, "id_token": "demo.\(payload).demo", "access_token": "demo", "refresh_token": "demo"]])
            var account = try! Account(snapshot: AuthSnapshot(data)); account.nickname = title; account.plan = plan
            account.quotas = [.init(id: "short", label: "5 小时", remaining: short, resetsAt: Date().addingTimeInterval(7200), bucketID: "codex"), .init(id: "long", label: "7 天", remaining: long, resetsAt: Date().addingTimeInterval(172800), bucketID: "codex")]
            account.updatedAt = Date(); return account
        }
        accounts = [account("demo-one", "日常工作", "work@example.com", "pro", 84, 62), account("demo-two", "个人探索", "personal@example.com", "plus", 96, 89), account("demo-three", "备用账号", "backup@example.com", "plus", 18, 43)]
        accounts[2].issue = "上次刷新未完成，显示的是缓存额度。"
        accounts[2].updatedAt = Date().addingTimeInterval(-3600)
        if PreviewConfiguration.variant == "all-quota" {
            accounts[2].quotaNeedsLogin = true
            accounts[2].issue = "登录凭据已过期或失效，自动刷新已暂停。请通过浏览器重新添加此账号；当前账号也可在 Codex 登录后保存。"
        }
        if CommandLine.arguments.contains("--demo-quotas") || PreviewConfiguration.variant == "quotas" {
            accounts[1].quotas = QuotaWindow.parse(["rateLimitsByLimitId": [
                "codex": ["limitName": "Codex", "secondary": ["usedPercent": 72.0, "windowDurationMins": 10080]],
                "demo_unknown_a": ["primary": ["usedPercent": 15.0, "windowDurationMins": 300]],
                "demo_unknown_b": ["limitName": "demo_unknown_b", "secondary": ["usedPercent": 25.0, "windowDurationMins": 10080]],
                "demo_named": ["limitName": "示例模型额度", "primary": ["usedPercent": 30.0, "windowDurationMins": 300]]
            ]])
        }
        selection = accounts[1].id; currentIdentity = accounts[0].id
        if PreviewConfiguration.variant == "layout" {
            accounts[0].quotas = [accounts[0].quotas[1]]
            selection = accounts[0].id
        }
        status = "演示模式 · 所有账号与额度均为虚构，操作已禁用。"
    }
}
