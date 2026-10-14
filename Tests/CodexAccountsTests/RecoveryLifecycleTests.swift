import XCTest
import AccountsCore
@testable import CodexAccounts

/// Non-demo models use synthetic files, isolated preferences and a Keychain spy.
@MainActor final class RecoveryLifecycleTests: XCTestCase {
    @MainActor private final class ModelFixture {
        let f: StoreFixture
        let defaults: UserDefaults
        let suite = "org.codexaccounts.tests.\(UUID().uuidString)"
        let current: Account
        let other: Account
        var model: AppModel!
        init(legacy: Bool = false, pending: Bool? = nil) throws {
            f = try StoreFixture()
            defaults = UserDefaults(suiteName: suite)!
            let home = f.root.appendingPathComponent("home")
            try PrivateFiles.write(syntheticAuth("a"), to: home.appendingPathComponent("auth.json"))
            if legacy { try f.legacy(["a", "b"], pending: pending) }
            try f.open()
            if !legacy {
                _ = try f.store!.upsert(syntheticAuth("a")); _ = try f.store!.upsert(syntheticAuth("b"))
                if let pending {
                    var backup = SwitchBackup(previous: try syntheticAuth("a"), targetIdentity: f.store!.accounts[1].id, home: home.path)
                    backup.isPending = pending; try f.store!.saveBackup(backup)
                }
            }
            current = f.store!.accounts[0]; other = f.store!.accounts[1]
            f.store = nil
            defaults.set(home.path, forKey: "codexHome")
            defaults.set(f.root.appendingPathComponent("Missing.app").path, forKey: "desktopApplication")
            defaults.set(false, forKey: "automaticRefresh")
            model = AppModel(directory: f.root, defaults: defaults, startServices: false, vault: f.vault)
        }
        func finish() async {
            for _ in 0..<200 {
                if !model.busy { return }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTFail("Isolated operation did not finish")
        }
        func close() { model = nil; defaults.removePersistentDomain(forName: suite) }
    }
    func testNewBackendStartupLoadsPendingJournalWithoutKeychain() throws {
        let f = try ModelFixture(pending: true); defer { f.close() }
        XCTAssertTrue(f.model.awaitingConfirmation); XCTAssertTrue(f.model.hasBackup)
        XCTAssertFalse(f.model.recoveryNeedsUnlock); XCTAssertTrue(f.f.reads.isEmpty)
        XCTAssertNotNil(f.model.switchBlockReason(f.other.id))
        f.model.confirmDesktopAccount()
        XCTAssertFalse(f.model.awaitingConfirmation); XCTAssertTrue(f.f.reads.isEmpty)
    }
    func testLegacyStartupRefreshAndDeferredActionsNeverReadKeychain() async throws {
        let f = try ModelFixture(legacy: true, pending: true); defer { f.close() }
        XCTAssertTrue(f.model.needsMigration); XCTAssertFalse(f.model.awaitingConfirmation)
        f.model.checkCurrentIdentity(); f.model.automaticRefreshTick()
        f.model.refresh(f.current.id); await f.finish() // Missing fake app fails before any RPC.
        f.model.switchTo(f.other.id); f.model.restore(); f.model.importCurrent()
        f.model.addViaLogin(); f.model.delete(f.other.id); f.model.rename(f.other.id, nickname: "Changed")
        f.model.unlockRecoveryRecord(); f.model.confirmDesktopAccount()
        XCTAssertTrue(f.f.reads.isEmpty)
        XCTAssertEqual(f.model.accounts.count, 2)
        XCTAssertTrue(f.model.showMigration)
    }
    func testExplicitMigrationThenOrdinaryLifecycleUsesOnlyFiles() async throws {
        let f = try ModelFixture(legacy: true, pending: true); defer { f.close() }
        f.model.migrateAccounts(); await f.finish()
        XCTAssertFalse(f.model.needsMigration); XCTAssertTrue(f.model.awaitingConfirmation)
        XCTAssertEqual(f.f.reads, [f.current.id, f.other.id, "switch-recovery"])
        f.f.reads = []
        f.model.confirmDesktopAccount(); f.model.rename(f.other.id, nickname: "Example")
        f.model.refresh(f.current.id); await f.finish()
        f.model.unlockRecoveryRecord(); f.model.delete(f.other.id)
        XCTAssertTrue(f.f.reads.isEmpty)
        XCTAssertEqual(f.model.accounts.count, 1)
    }
    func testMigrationDeniedDoesNotRetryWhenOpeningOrRefreshing() async throws {
        let f = try ModelFixture(legacy: true); defer { f.close() }
        f.f.denied = f.other.id
        f.model.migrateAccounts(); await f.finish()
        XCTAssertTrue(f.model.needsMigration); XCTAssertNotNil(f.model.error)
        let reads = f.f.reads
        f.model.checkCurrentIdentity(); f.model.automaticRefreshTick()
        XCTAssertEqual(f.f.reads, reads)
        f.f.denied = nil; f.model.migrateAccounts(); await f.finish()
        XCTAssertFalse(f.model.needsMigration)
    }
    func testFailedSwitchBeforeBackupReloadsJournalWithoutLeavingRecoveryGuard() async throws {
        let f = try ModelFixture(pending: false); defer { f.close() }
        f.model.switchTo(f.other.id); await f.finish()
        XCTAssertFalse(f.model.awaitingConfirmation); XCTAssertFalse(f.model.recoveryNeedsUnlock)
        XCTAssertTrue(f.model.hasBackup)
        XCTAssertNotNil(f.model.error); XCTAssertTrue(f.f.reads.isEmpty)
        XCTAssertNil(f.model.switchBlockReason(f.other.id))
    }
    func testFailedRestoreKeepsExistingPendingBackupWithoutRequiringManualUnlock() async throws {
        let f = try ModelFixture(pending: true); defer { f.close() }
        f.model.restore(); await f.finish()
        XCTAssertTrue(f.model.awaitingConfirmation); XCTAssertTrue(f.model.hasBackup)
        XCTAssertFalse(f.model.recoveryNeedsUnlock)
        XCTAssertNotNil(f.model.error); XCTAssertTrue(f.f.reads.isEmpty)
    }
    func testFailedSwitchWithNoBackupAllowsRetryAndPreservesLiveCredential() async throws {
        let f = try ModelFixture(); defer { f.close() }
        let before = try PrivateFiles.read(f.model.home.appendingPathComponent("auth.json"))
        f.model.switchTo(f.other.id); await f.finish()
        XCTAssertFalse(f.model.awaitingConfirmation); XCTAssertFalse(f.model.hasBackup)
        XCTAssertFalse(f.model.recoveryNeedsUnlock)
        XCTAssertEqual(try PrivateFiles.read(f.model.home.appendingPathComponent("auth.json")), before)
        XCTAssertNil(f.model.switchBlockReason(f.other.id))
    }
    func testLogoutAndUnsavedIdentityRemoveCurrentAccountAndPercentage() throws {
        let f = try ModelFixture(); defer { f.close() }
        XCTAssertEqual(f.model.currentAccount?.id, f.current.id)
        try PrivateFiles.write(syntheticAuth("unsaved"), to: f.model.home.appendingPathComponent("auth.json"))
        f.model.checkCurrentIdentity(); XCTAssertNil(f.model.currentAccount)
        try PrivateFiles.remove(f.model.home.appendingPathComponent("auth.json"))
        f.model.checkCurrentIdentity(); XCTAssertNil(f.model.currentIdentity)
        XCTAssertTrue(f.f.reads.isEmpty)
    }
    func testStatusBarPreferencePersists() throws {
        let f = try ModelFixture(); defer { f.close() }
        XCTAssertTrue(f.model.showMenuBarQuota)
        f.model.showMenuBarQuota = false
        f.model = nil
        f.model = AppModel(directory: f.f.root, defaults: f.defaults, startServices: false, vault: f.f.vault)
        XCTAssertFalse(f.model.showMenuBarQuota)
        XCTAssertTrue(f.f.reads.isEmpty)
    }
}
