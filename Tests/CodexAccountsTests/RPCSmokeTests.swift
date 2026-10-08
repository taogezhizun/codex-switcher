import XCTest
import AccountsCore
@testable import CodexAccounts

final class RPCSmokeTests: XCTestCase {
    @MainActor func testRealCLIInEmptyIsolatedHome() async throws {
        let environment = ProcessInfo.processInfo.environment
        let executable: URL
        if let app = environment["CODEX_ACCOUNTS_TEST_APP"] {
            executable = try Desktop.resolveExecutable(in: URL(fileURLWithPath: app))
        } else if let path = environment["CODEX_ACCOUNTS_TEST_CLI"] {
            executable = URL(fileURLWithPath: path)
        } else {
            throw XCTSkip("Set CODEX_ACCOUNTS_TEST_APP or CODEX_ACCOUNTS_TEST_CLI to a trusted local Codex installation for the opt-in smoke test.")
        }
        let root = (try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory)).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try IsolatedSession(root: root)
        do {
            try await session.rpc.start(executable: executable, home: session.home)
            let account = try await session.rpc.request("account/read", ["refreshToken": false])
            XCTAssertTrue(account["account"] is NSNull)
            let response = try await session.rpc.request("config/read", ["includeLayers": false])
            let config = response["config"] as? [String: Any]
            XCTAssertEqual(config?["cli_auth_credentials_store"] as? String, "file")
            await session.close()
            XCTAssertFalse(FileManager.default.fileExists(atPath: session.home.path))
        } catch {
            await session.close(); throw error
        }
    }
}

final class LocalStoreTests: XCTestCase {
    func testOnlyAbandonedUUIDSessionsAreReaped() throws {
        let root = try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("Sessions")
        let abandoned = sessions.appendingPathComponent(UUID().uuidString)
        let unrelated = sessions.appendingPathComponent("not-a-session")
        try PrivateFiles.makeDirectory(abandoned)
        try PrivateFiles.write(Data("synthetic-login-placeholder".utf8), to: abandoned.appendingPathComponent("auth.json"))
        try PrivateFiles.makeDirectory(unrelated)
        let store = try AccountStore(directory: root)
        withExtendedLifetime(store) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        }
    }
    func testSessionCleanupRefusesSymlink() throws {
        let root = try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("preserve")
        try PrivateFiles.makeDirectory(outside)
        let sessions = root.appendingPathComponent("Sessions")
        try FileManager.default.createSymbolicLink(at: sessions, withDestinationURL: outside)
        XCTAssertThrowsError(try AccountStore(directory: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    @MainActor func testDemoUsesOnlyExampleAccountsAndRejectsMutation() {
        let model = AppModel(demo: true)
        let original = model.accounts
        XCTAssertEqual(original.count, 3)
        XCTAssertTrue(original.allSatisfy { $0.email.hasSuffix("@example.com") })
        XCTAssertFalse(model.configured)
        model.importCurrent(); model.switchTo(original[1].id); model.delete(original[0].id)
        XCTAssertFalse(model.busy); XCTAssertEqual(model.accounts, original)
    }
}

final class PresentationTests: XCTestCase {
    @MainActor func testPrivacyProjectionDoesNotChangeAccountData() {
        let model = AppModel(demo: true)
        var account = model.accounts[0]; account.nickname = ""
        let original = account
        XCTAssertFalse(AccountPresentation.title(account, hideEmails: true).contains("@"))
        XCTAssertEqual(AccountPresentation.email(account, hideEmails: true), "邮箱已隐藏")
        XCTAssertEqual(AccountPresentation.title(account, hideEmails: false), account.email)
        XCTAssertEqual(account, original)
        model.hideEmails = false
        XCTAssertEqual(model.accounts.count, 3)
    }
    @MainActor func testSearchTrimsWhitespaceAndKeepsCurrentFirstWithoutDroppingAccounts() {
        let model = AppModel(demo: true)
        var accounts = model.accounts
        accounts.append(contentsOf: model.accounts.map { row in var row = row; row.id += "-more"; return row })
        let sorted = AccountPresentation.ordered(accounts, current: accounts[2].id, query: "  ")
        XCTAssertEqual(sorted.count, 6)
        XCTAssertEqual(sorted.first?.id, accounts[2].id)
        XCTAssertEqual(Array(sorted.dropFirst()).map(\.id), accounts.filter { $0.id != accounts[2].id }.map(\.id))
        XCTAssertEqual(AccountPresentation.ordered(accounts, current: nil, query: " WORK@EXAMPLE.COM ").count, 2)
        XCTAssertTrue(AccountPresentation.ordered(accounts, current: nil, query: "no-match").isEmpty)
    }
    @MainActor func testUnknownFailedOldAndResetQuotaNeedRefresh() {
        let model = AppModel(demo: true)
        let now = Date(); var account = model.accounts[0]; account.updatedAt = now
        XCTAssertFalse(AccountPresentation.needsRefresh(account, now: now))
        account.updatedAt = now.addingTimeInterval(-901)
        XCTAssertTrue(AccountPresentation.needsRefresh(account, now: now))
        account.updatedAt = now; account.issue = "synthetic failure"
        XCTAssertTrue(AccountPresentation.needsRefresh(account, now: now))
        account.issue = nil; account.quotas = []
        XCTAssertTrue(AccountPresentation.needsRefresh(account, now: now))
        account.updatedAt = now.addingTimeInterval(-120)
        account.quotas = [.init(id: "test", label: "test", remaining: 50, resetsAt: now.addingTimeInterval(-60))]
        XCTAssertTrue(AccountPresentation.needsRefresh(account, now: now))
    }
    @MainActor func testSwitchEligibilityPreventsRedundantOrPendingRestarts() {
        let model = AppModel(demo: true)
        XCTAssertNotNil(model.switchBlockReason(model.currentIdentity!))
        let other = model.accounts.first { $0.id != model.currentIdentity }!
        XCTAssertNil(model.switchBlockReason(other.id))
        model.awaitingConfirmation = true
        XCTAssertNotNil(model.switchBlockReason(other.id))
        model.awaitingConfirmation = false; model.busy = true
        XCTAssertNotNil(model.switchBlockReason(other.id))
    }
    @MainActor func testUpdatedTextNeverSaysNegativeTime() {
        let model = AppModel(demo: true)
        var account = model.accounts[0]; let now = Date()
        account.updatedAt = now.addingTimeInterval(120)
        XCTAssertEqual(AccountPresentation.updatedLabel(account, now: now), "刚刚更新")
        account.updatedAt = nil
        XCTAssertEqual(AccountPresentation.updatedLabel(account, now: now), "尚未刷新")
    }
}

final class QuotaPresentationTests: XCTestCase {
    func testOfficialDisplayNameWinsAndPeriodIsSeparate() throws {
        let windows = QuotaWindow.parse(["rateLimitsByLimitId": [
            "codex": ["limitName": " Codex 标准额度 ", "primary": ["usedPercent": 35.0, "windowDurationMins": 300]]
        ]])
        XCTAssertEqual(windows.first?.bucketName, " Codex 标准额度 ")
        XCTAssertEqual(windows.first?.label, "5 小时")
        XCTAssertEqual(QuotaPresentation.groups(windows).first?.title, "Codex 标准额度")
        XCTAssertEqual(try JSONDecoder().decode([QuotaWindow].self, from: JSONEncoder().encode(windows)), windows)
    }
    func testInternalOrBlankNamesRemainUnidentifiedWithoutLosingWindows() {
        let windows = QuotaWindow.parse(["rateLimitsByLimitId": [
            "pool_a": ["limitName": "pool_a", "primary": ["usedPercent": 20.0]],
            "pool_b": ["limitName": "  ", "primary": ["usedPercent": 40.0]],
            "pool_c": ["limitName": "another_internal_name", "primary": ["usedPercent": 55.0]],
            "codex": ["limitName": NSNull(), "secondary": ["usedPercent": 70.0]]
        ]])
        let groups = QuotaPresentation.groups(windows)
        XCTAssertEqual(groups.map(\.title), ["Codex", "其他额度 1", "其他额度 2", "其他额度 3"])
        XCTAssertEqual(groups.flatMap(\.windows).count, 4)
        XCTAssertEqual(groups.filter(\.unidentified).count, 3)
        XCTAssertEqual(groups.flatMap(\.windows).map(\.remaining).sorted(), [30, 45, 60, 80])
    }
    func testOldCacheDecodesAndHidesRawNamesWithoutRefresh() throws {
        let old = Data(#"[{"id":"pool_a.primary","label":"pool_a · 5 小时","remaining":82},{"id":"codex.secondary","label":"codex · 7 天","remaining":24}]"#.utf8)
        let windows = try JSONDecoder().decode([QuotaWindow].self, from: old)
        XCTAssertNil(windows[0].bucketID)
        XCTAssertEqual(QuotaPresentation.duration(windows[0]), "5 小时")
        XCTAssertEqual(QuotaPresentation.groups(windows).map(\.title), ["Codex", "其他额度 1"])
        XCTAssertEqual(QuotaPresentation.summary(windows)?.remaining, 24)
        XCTAssertEqual(try JSONDecoder().decode([QuotaWindow].self, from: JSONEncoder().encode(windows)), windows)
    }
    func testSummaryUsesTightestCodexWindowAndNeverAnotherPool() {
        let windows = QuotaWindow.parse(["rateLimitsByLimitId": [
            "aaa_other": ["primary": ["usedPercent": 0.0]],
            "codex": ["primary": ["usedPercent": 20.0, "windowDurationMins": 300], "secondary": ["usedPercent": 75.0, "windowDurationMins": 10080]]
        ]])
        XCTAssertEqual(QuotaPresentation.summary(windows)?.remaining, 25)
        XCTAssertEqual(QuotaPresentation.summary(windows).map(QuotaPresentation.duration), "7 天")
        XCTAssertNil(QuotaPresentation.summary(windows.filter { QuotaPresentation.bucketID($0) != "codex" }))
    }
    func testDottedBucketIdentifierSurvivesOldCacheAndLegacyResponseWorks() {
        let old = QuotaWindow(id: "pool.example.primary", label: "pool.example · 主要窗口", remaining: 66)
        XCTAssertEqual(QuotaPresentation.bucketID(old), "pool.example")
        let legacy = QuotaWindow.parse(["rateLimits": ["limitName": "Codex", "primary": ["usedPercent": 12.0]]])
        XCTAssertEqual(QuotaPresentation.groups(legacy).first?.title, "Codex")
        XCTAssertEqual(QuotaPresentation.summary(legacy)?.remaining, 88)
    }
}
