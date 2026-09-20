import XCTest
import AccountsCore
@testable import CodexAccounts

@MainActor private final class QueryProbe {
    var started: [String] = []
    var tokens: [String: String] = [:]
    var failures: Set<String> = []
    var remaining: [String: Double] = [:]
    var expired: Set<String> = []
    var active = 0
    var peak = 0
    var cancelled = 0
    var delay: UInt64 = 10_000_000
    var onRead: ((AuthSnapshot) throws -> Void)?
}
@MainActor private final class StubQuotaReader: QuotaReading {
    let probe: QueryProbe
    init(_ probe: QueryProbe) { self.probe = probe }
    func read(_ snapshot: AuthSnapshot, executable: URL, root: URL) async throws -> [QuotaWindow] {
        probe.started.append(snapshot.identity); probe.tokens[snapshot.identity] = snapshot.accessToken
        probe.active += 1; probe.peak = max(probe.peak, probe.active)
        defer { probe.active -= 1 }
        try probe.onRead?(snapshot)
        try await Task.sleep(nanoseconds: probe.delay)
        if probe.expired.contains(snapshot.identity) { throw QuotaReadError.needsLogin }
        if probe.failures.contains(snapshot.identity) { throw AccountsError.message("Synthetic network error") }
        return [.init(id: "codex.week", label: "7 天", remaining: probe.remaining[snapshot.identity] ?? 74, bucketID: "codex")]
    }
    func cancel() { probe.cancelled += 1 }
}

@MainActor final class AllAccountQuotaTests: XCTestCase {
    @MainActor private final class Fixture {
        let storage: StoreFixture
        let defaults: UserDefaults
        let suite = "org.codexaccounts.quota-tests.\(UUID().uuidString)"
        let probe = QueryProbe()
        var model: AppModel!
        var ids: [String] = []
        init(legacy: Bool = false) throws {
            storage = try StoreFixture(); defaults = UserDefaults(suiteName: suite)!
            let home = storage.root.appendingPathComponent("home")
            try PrivateFiles.write(syntheticAuth("a", token: "fresh-live-token"), to: home.appendingPathComponent("auth.json"))
            if legacy { try storage.legacy(["a", "b", "c"]) }
            try storage.open()
            if !legacy {
                for name in ["a", "b", "c"] { _ = try storage.store!.upsert(syntheticAuth(name)) }
            }
            for index in storage.store!.accounts.indices {
                storage.store!.accounts[index].quotas = [.init(id: "codex.week", label: "7 天", remaining: 10, bucketID: "codex")]
                storage.store!.accounts[index].updatedAt = Date(timeIntervalSince1970: 1000)
            }
            try storage.store!.save(); ids = storage.store!.accounts.map(\.id); storage.store = nil
            // Only the injected reader runs; this fake bundle satisfies metadata preflight without a real app.
            let app = storage.root.appendingPathComponent("Synthetic.app")
            try PrivateFiles.write(PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.openai.codex"], format: .xml, options: 0), to: app.appendingPathComponent("Contents/Info.plist"))
            let executable = app.appendingPathComponent("Contents/Resources/codex")
            try PrivateFiles.write(Data("never execute this fixture".utf8), to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            defaults.set(home.path, forKey: "codexHome"); defaults.set(app.path, forKey: "desktopApplication")
            defaults.set(false, forKey: "automaticRefresh")
            reopen()
        }
        func reopen() {
            model = nil
            model = AppModel(directory: storage.root, defaults: defaults, startServices: false, vault: storage.vault,
                             quotaReaderFactory: { [probe] in StubQuotaReader(probe) })
        }
        func finish() async {
            for _ in 0..<400 {
                if !model.busy { return }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTFail("Batch did not finish")
        }
        func close() { probe.onRead = nil; model = nil; defaults.removePersistentDomain(forName: suite) }
    }
    func testAllAccountsUseOwnCredentialsWithBoundedConcurrencyAndNoLiveWrites() async throws {
        let f = try Fixture(); defer { f.close() }
        let original = try PrivateFiles.read(f.model.home.appendingPathComponent("auth.json"))
        f.model.refreshAll(); await f.finish()
        XCTAssertEqual(Set(f.probe.started), Set(f.ids)); XCTAssertEqual(f.probe.peak, 2)
        XCTAssertEqual(f.probe.tokens[f.ids[0]], "fresh-live-token")
        XCTAssertEqual(f.probe.tokens[f.ids[1]], "example-access")
        XCTAssertTrue(f.model.accounts.allSatisfy { $0.quotas.first?.remaining == 74 && $0.issue == nil })
        XCTAssertEqual(f.model.currentIdentity, f.ids[0])
        XCTAssertEqual(try PrivateFiles.read(f.model.home.appendingPathComponent("auth.json")), original)
        XCTAssertTrue(f.storage.reads.isEmpty)
    }
    func testSingleAccountFailureKeepsItsCacheWhileOthersUpdate() async throws {
        let f = try Fixture(); defer { f.close() }
        f.probe.failures = [f.ids[1]]; f.model.refreshAll(); await f.finish()
        let failed = try XCTUnwrap(f.model.accounts.first { $0.id == f.ids[1] })
        XCTAssertEqual(failed.quotas.first?.remaining, 10)
        XCTAssertEqual(failed.updatedAt, Date(timeIntervalSince1970: 1000)); XCTAssertNotNil(failed.issue)
        XCTAssertEqual(f.model.accounts.filter { $0.quotas.first?.remaining == 74 }.count, 2)
        XCTAssertTrue(f.model.status.contains("2/3"))
    }
    func testDailyEstimatesPersistPerAccountAndFailedQueriesDoNotChangeThem() async throws {
        let f = try Fixture(); defer { f.close() }
        f.model.refreshAll(); await f.finish()
        XCTAssertTrue(f.model.accounts.allSatisfy { DailyUsagePresentation.make(account: $0, now: Date()).text == "今日已用 —" })
        f.probe.remaining[f.ids[0]] = 66
        f.model.refreshAll(); await f.finish()
        XCTAssertEqual(DailyUsagePresentation.make(account: f.model.accounts[0], now: f.model.quotaDisplayDate).text, "今日已用≈8%")
        XCTAssertEqual(DailyUsagePresentation.make(account: f.model.accounts[1], now: f.model.quotaDisplayDate).text, "今日已用≈0%")
        f.reopen()
        XCTAssertEqual(DailyUsagePresentation.make(account: f.model.accounts[0], now: Date()).text, "今日已用≈8%")
        let before = f.model.accounts[0].dailyUsage
        f.probe.failures = [f.ids[0]]
        f.model.refresh(f.ids[0]); await f.finish()
        XCTAssertEqual(f.model.accounts[0].dailyUsage, before)
        XCTAssertTrue(f.storage.reads.isEmpty)
    }
    func testExpiredAccountPausesAcrossRestartAndManualRetryCanRecover() async throws {
        let f = try Fixture(); defer { f.close() }
        f.probe.expired = [f.ids[1]]; f.model.refreshAll(); await f.finish()
        XCTAssertEqual(f.model.accounts[1].quotaNeedsLogin, true)
        f.reopen(); f.probe.started = []
        f.model.automaticRefresh = true; f.model.automaticRefreshTick(); await f.finish()
        XCTAssertFalse(f.probe.started.contains(f.ids[1]))
        f.model.automaticRefresh = false; f.probe.expired = []
        f.model.refresh(f.ids[1]); await f.finish()
        XCTAssertEqual(f.model.accounts[1].quotaNeedsLogin, false)
        XCTAssertNil(f.model.accounts[1].issue)
    }
    func testFreshLiveCredentialResumesAnExpiredCurrentAccount() async throws {
        let f = try Fixture(); defer { f.close() }
        f.probe.expired = [f.ids[0]]; f.model.refreshAll(); await f.finish()
        f.reopen(); f.probe.started = []; f.model.automaticRefresh = true
        f.model.automaticRefreshTick(); await f.finish()
        XCTAssertFalse(f.probe.started.contains(f.ids[0]))
        f.probe.expired = []
        try PrivateFiles.write(syntheticAuth("a", token: "new-live-token"), to: f.model.home.appendingPathComponent("auth.json"))
        f.model.automaticRefreshTick(); await f.finish()
        XCTAssertEqual(f.model.accounts[0].quotaNeedsLogin, false)
        XCTAssertEqual(f.probe.tokens[f.ids[0]], "new-live-token")
    }
    func testCredentialChangesDuringReadDiscardOnlyAffectedResults() async throws {
        let f = try Fixture(); defer { f.close() }
        let home = f.model.home
        f.probe.onRead = { snapshot in
            if snapshot.identity == f.ids[0] { try PrivateFiles.write(syntheticAuth("unsaved"), to: home.appendingPathComponent("auth.json")) }
        }
        f.model.refreshAll(); await f.finish()
        XCTAssertEqual(f.model.accounts[0].quotas.first?.remaining, 10)
        XCTAssertEqual(f.model.accounts[1].quotas.first?.remaining, 74)
        XCTAssertNil(f.model.currentAccount)
    }
    func testCancelStopsQueuedAccountsAndDoesNotRestartImmediately() async throws {
        let f = try Fixture(); defer { f.close() }
        f.probe.delay = 2_000_000_000
        f.model.automaticRefresh = true; f.model.automaticRefreshTick()
        for _ in 0..<100 {
            if f.probe.active == 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        f.model.cancel(); await f.finish()
        XCTAssertEqual(f.probe.started.count, 2); XCTAssertEqual(f.probe.cancelled, 2)
        XCTAssertTrue(f.model.refreshingAccountIDs.isEmpty); XCTAssertFalse(f.model.refreshingAutomatically)
        f.model.automaticRefreshTick(); XCTAssertFalse(f.model.busy)
    }
    func testLegacyDeferredMigrationRefreshesOnlyLiveAndNeverReadsKeychain() async throws {
        let f = try Fixture(legacy: true); defer { f.close() }
        f.model.refreshAll(); await f.finish()
        XCTAssertEqual(f.probe.started, [f.ids[0]])
        XCTAssertFalse(f.model.canRefresh(f.ids[1])); XCTAssertTrue(f.storage.reads.isEmpty)
    }
    func testLogoutStillAllowsSavedAccountRefreshAndPendingRecoveryBlocksIt() async throws {
        let f = try Fixture(); defer { f.close() }
        try PrivateFiles.remove(f.model.home.appendingPathComponent("auth.json"))
        f.model.refreshAll(); await f.finish()
        XCTAssertEqual(Set(f.probe.started), Set(f.ids)); XCTAssertNil(f.model.currentAccount)
        f.probe.started = []; f.model.awaitingConfirmation = true
        f.model.refreshAll(); XCTAssertFalse(f.model.busy); XCTAssertTrue(f.probe.started.isEmpty)
    }
    func testExpiredJWTIsRejectedWithoutLaunchingAHelper() async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["exp": 1000]).base64EncodedString()
        let snapshot = try AuthSnapshot(syntheticAuth("a", token: "demo.\(payload).demo"))
        XCTAssertEqual(snapshot.accessTokenExpiresAt, Date(timeIntervalSince1970: 1000))
        let f = try StoreFixture()
        do {
            _ = try await QuotaReader().read(snapshot, executable: f.root.appendingPathComponent("absent"), root: f.root)
            XCTFail("Expected expiry")
        } catch { XCTAssertTrue(error is QuotaReadError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.root.path).isEmpty)
    }
    func testServerRequestsReauthenticationAndPrivateSessionIsRemoved() async throws {
        let f = try StoreFixture()
        let executable = f.root.appendingPathComponent("synthetic-server")
        // Exercise the real stdio transport without contacting OpenAI or reading real credentials.
        let script = #"""
        #!/bin/sh
        IFS= read -r request
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r request
        IFS= read -r request
        case "$request" in *chatgptAuthTokens*) ;; *) exit 1 ;; esac
        case "$request" in *refresh_token*) exit 1 ;; esac
        printf '%s\n' '{"id":2,"result":{}}'
        IFS= read -r request
        printf '%s\n' '{"id":"refresh-example","method":"account/chatgptAuthTokens/refresh","params":{"reason":"unauthorized"}}'
        IFS= read -r request
        case "$request" in *refresh-example*) ;; *) exit 1 ;; esac
        printf '%s\n' '{"id":3,"error":{"code":-1,"message":"synthetic unauthorized"}}'
        while IFS= read -r request; do :; done
        """#
        try PrivateFiles.write(Data(script.utf8), to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let sessions = f.root.appendingPathComponent("Sessions")
        do {
            _ = try await QuotaReader().read(AuthSnapshot(syntheticAuth("a")), executable: executable, root: sessions)
            XCTFail("Expected reauthentication")
        } catch { XCTAssertTrue(error is QuotaReadError) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: sessions.path).isEmpty)
    }
    func testSavedCredentialReplacementAndSourceChangesRejectStaleResults() throws {
        let original = try syntheticAuth("a")
        let identity = try AuthSnapshot(original).identity
        let credentials = try QuotaCredentials.load(id: identity, live: nil) { original }
        XCTAssertThrowsError(try credentials.validate(id: identity, live: nil) { try syntheticAuth("a", token: "renewed") })
        XCTAssertThrowsError(try credentials.validate(id: identity, live: original) { original })
        XCTAssertThrowsError(try credentials.validate(id: identity, live: nil) { try syntheticAuth("other") })
        XCTAssertNoThrow(try credentials.validate(id: identity, live: syntheticAuth("other")) { original })
    }
}
