import XCTest
import AccountsCore
import Darwin
@testable import CodexAccounts

/// Synthetic process tables exercise shutdown without touching any running Codex instance.
@MainActor final class DesktopShutdownTests: XCTestCase {
    private static let main = "/tmp/Synthetic Codex.app/Contents/MacOS/Codex"
    private static let cli = "/tmp/Synthetic Codex.app/Contents/Resources/codex"
    private static let packagedCLI = "/tmp/Synthetic Codex.app/Contents/Resources/codex-cli/vendor/codex"

    private func process(_ pid: Int32, parent: Int32 = 1, executable: String? = nil,
                         seconds: UInt64 = 100, microseconds: UInt64 = 20,
                         uid: UInt32 = 501, zombie: Bool = false) -> DesktopProcess {
        DesktopProcess(identity: .init(pid: pid, startedSeconds: seconds,
                                       startedMicroseconds: microseconds,
                                       executable: executable ?? Self.cli, uid: uid),
                       parent: parent, zombie: zombie)
    }

    @MainActor private final class Host {
        var rows: [DesktopProcess]
        var reads = 0
        var quits = 0
        var waits = 0
        var prompts: [DesktopShutdownPrompt] = []
        var signals: [(DesktopProcess.Identity, Int32)] = []
        var phases: [String] = []
        var readFailureAt: Int?
        var signalFails = false
        var approved = false
        var onQuit: () -> Void = {}
        var onWait: () throws -> Void = {}
        var onConfirm: () -> Void = {}
        var onSignal: (DesktopProcess.Identity, Int32) -> Void = { _, _ in }

        init(_ rows: [DesktopProcess]) { self.rows = rows }

        func shutdown() -> DesktopShutdown {
            DesktopShutdown(mainExecutable: DesktopShutdownTests.main,
                            cliExecutables: [DesktopShutdownTests.cli, DesktopShutdownTests.packagedCLI],
                            readProcesses: {
                                self.reads += 1
                                if self.readFailureAt == self.reads { throw AccountsError.message("Synthetic inspection failure") }
                                return self.rows
                            }, requestQuit: {
                                self.quits += 1; self.onQuit()
                            }, sendSignal: { identity, signal in
                                if self.signalFails { throw AccountsError.message("Synthetic signal failure") }
                                self.signals.append((identity, signal)); self.onSignal(identity, signal)
                            }, wait: {
                                self.waits += 1; try self.onWait()
                            }, gracefulPolls: 2, terminationPolls: 2)
        }

        func stop(_ shutdown: DesktopShutdown, terminationAlreadyApproved: Bool = false) async throws {
            try await shutdown.stop(terminationAlreadyApproved: terminationAlreadyApproved, confirm: { prompt in
                self.prompts.append(prompt); self.onConfirm(); return self.approved
            }, phase: { self.phases.append($0) })
        }
    }

    @discardableResult private func failure(_ host: Host, _ shutdown: DesktopShutdown,
                                            terminationAlreadyApproved: Bool = false,
                                            file: StaticString = #filePath, line: UInt = #line) async -> Error? {
        do {
            try await host.stop(shutdown, terminationAlreadyApproved: terminationAlreadyApproved)
            XCTFail("Shutdown should have stopped safely", file: file, line: line)
            return nil
        } catch { return error }
    }

    @MainActor private final class TransactionEnvironment: SwitchEnvironment {
        let homePath = "/tmp/synthetic-shutdown-auth"
        let host: Host
        let shutdown: DesktopShutdown
        var live: Data?
        var backup: SwitchBackup?
        var writes: [Data?] = []
        var events: [String] = []
        var terminationAlreadyApproved = false
        var onBackup: () -> Void = {}
        var onStart: () throws -> Void = {}
        init(host: Host, live: Data) {
            self.host = host; self.shutdown = host.shutdown(); self.live = live
        }
        func preflight() throws { events.append("preflight") }
        func stopDesktop() async throws {
            events.append("stop")
            try await host.stop(shutdown, terminationAlreadyApproved: terminationAlreadyApproved)
            events.append("stopped")
        }
        func startDesktop() async throws { events.append("start"); try onStart() }
        func readLive() throws -> Data? { live }
        func writeLive(_ data: Data?) throws {
            try shutdown.verifyStopped()
            events.append("write"); writes.append(data); live = data
        }
        func saveBackup(_ backup: SwitchBackup) throws {
            events.append("backup"); self.backup = backup; onBackup()
        }
        func archiveDeparting(_ data: Data) throws { events.append("archive") }
    }

    @discardableResult private func transactionFailure(_ env: TransactionEnvironment, target: Data,
                                                       file: StaticString = #filePath, line: UInt = #line) async -> Error? {
        do {
            _ = try await SwitchTransaction.run(target: target, environment: env)
            XCTFail("The transaction should not complete", file: file, line: line)
            return nil
        } catch { return error }
    }

    func testDeclinedOrUnsuccessfulForcedShutdownNeverBacksUpOrWritesAuthentication() async throws {
        let previous = try syntheticAuth("previous"), target = try syntheticAuth("next")
        for approved in [false, true] {
            let host = Host([process(10, executable: Self.main)]); host.approved = approved
            let env = TransactionEnvironment(host: host, live: previous)
            await transactionFailure(env, target: target)
            XCTAssertEqual(env.live, previous)
            XCTAssertNil(env.backup)
            XCTAssertTrue(env.writes.isEmpty)
            XCTAssertEqual(env.events, ["preflight", "stop"])
            XCTAssertEqual(host.signals.count, approved ? 2 : 0)
        }
    }

    func testApprovedShutdownCompletesBeforeBackupAndAuthenticationWrite() async throws {
        let previous = try syntheticAuth("previous"), target = try syntheticAuth("next")
        let host = Host([process(10, executable: Self.main)]); host.approved = true
        host.onSignal = { _, _ in host.rows = [] }
        let env = TransactionEnvironment(host: host, live: previous)
        _ = try await SwitchTransaction.run(target: target, environment: env)
        XCTAssertEqual(env.events, ["preflight", "stop", "stopped", "archive", "backup", "write", "start"])
        XCTAssertEqual(env.live, target)
        XCTAssertEqual(env.writes, [target])
        XCTAssertEqual(env.backup?.previous, previous)
        XCTAssertEqual(env.backup?.isPending, true)
    }

    func testRestartAfterBackupBlocksFirstAuthenticationWriteAndRetainsBackup() async throws {
        let previous = try syntheticAuth("previous"), target = try syntheticAuth("next")
        let host = Host([process(10, executable: Self.main)])
        host.onQuit = { host.rows = [] }
        let env = TransactionEnvironment(host: host, live: previous)
        let restarted = process(20, executable: Self.main, seconds: 200)
        env.onBackup = { host.rows = [restarted] }
        await transactionFailure(env, target: target)
        XCTAssertEqual(env.live, previous)
        XCTAssertTrue(env.writes.isEmpty)
        XCTAssertEqual(env.backup?.previous, previous)
        XCTAssertEqual(env.backup?.isPending, true)
        XCTAssertFalse(env.events.contains("start"))
    }

    func testLaunchFailureWithRemainingProcessDoesNotRollBackOverRunningApp() async throws {
        let previous = try syntheticAuth("previous"), target = try syntheticAuth("next")
        let host = Host([process(10, executable: Self.main)])
        host.onQuit = { host.rows = [] }
        let env = TransactionEnvironment(host: host, live: previous)
        let restarted = process(20, executable: Self.main, seconds: 200)
        env.onStart = { host.rows = [restarted]; throw AccountsError.message("Synthetic partial launch failure") }
        await transactionFailure(env, target: target)
        XCTAssertEqual(env.writes, [target])
        XCTAssertEqual(env.live, target)
        XCTAssertEqual(env.backup?.previous, previous)
        XCTAssertEqual(env.backup?.isPending, true)
        XCTAssertEqual(env.events.filter { $0 == "start" }.count, 1)
    }

    func testInitiallyApprovedTerminationSendsTERMWithoutNormalQuitWaitOrAnotherPrompt() async throws {
        let root = process(10, executable: Self.main), child = process(11, parent: 10)
        let host = Host([root, child])
        host.onSignal = { identity, _ in
            XCTAssertEqual(host.quits, 0)
            XCTAssertEqual(host.waits, 0)
            XCTAssertTrue(host.prompts.isEmpty)
            host.rows.removeAll { $0.identity == identity }
        }
        let shutdown = host.shutdown()
        try await host.stop(shutdown, terminationAlreadyApproved: true)
        XCTAssertEqual(Set(host.signals.map(\.0)), [root.identity, child.identity])
        XCTAssertTrue(host.signals.allSatisfy { $0.1 == SIGTERM })
        try shutdown.verifyStopped()
    }

    func testInitiallyApprovedTerminationEscalatesToKILLWithoutRepeatedConfirmation() async throws {
        let root = process(10, executable: Self.main)
        let host = Host([root])
        var waitsAtSignals: [Int] = []
        host.onSignal = { _, signal in
            waitsAtSignals.append(host.waits)
            if signal == SIGKILL { host.rows = [] }
        }
        let shutdown = host.shutdown()
        try await host.stop(shutdown, terminationAlreadyApproved: true)
        XCTAssertEqual(host.signals.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertEqual(waitsAtSignals, [0, 2])
        XCTAssertEqual(host.quits, 0)
        XCTAssertTrue(host.prompts.isEmpty)
        try shutdown.verifyStopped()
    }

    func testInitialApprovalNeverAuthorizesUnknownOrphanOrIndependentCLI() async {
        let root = process(10, executable: Self.main)
        let child = process(11, parent: 10), independent = process(12, parent: 400)
        for rows in [[independent], [root, child, independent]] {
            let host = Host(rows)
            let shutdown = host.shutdown()
            await failure(host, shutdown, terminationAlreadyApproved: true)
            XCTAssertEqual(host.quits, 0)
            XCTAssertEqual(host.waits, 0)
            XCTAssertTrue(host.prompts.isEmpty)
            XCTAssertTrue(host.signals.isEmpty)
            XCTAssertEqual(host.rows, rows)
            XCTAssertThrowsError(try shutdown.verifyStopped())
        }
    }

    func testInitiallyApprovedShutdownStillVerifiesExitImmediatelyBeforeAuthenticationWrite() async throws {
        let previous = try syntheticAuth("previous"), target = try syntheticAuth("next")
        let host = Host([process(10, executable: Self.main)])
        host.onSignal = { _, _ in host.rows = [] }
        let env = TransactionEnvironment(host: host, live: previous)
        env.terminationAlreadyApproved = true
        let restarted = process(20, executable: Self.main, seconds: 200)
        env.onBackup = { host.rows = [restarted] }
        await transactionFailure(env, target: target)
        XCTAssertEqual(host.quits, 0)
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertEqual(host.signals.map(\.1), [SIGTERM])
        XCTAssertTrue(env.writes.isEmpty)
        XCTAssertEqual(env.live, previous)
        XCTAssertEqual(env.backup?.previous, previous)
        XCTAssertEqual(env.backup?.isPending, true)
        XCTAssertFalse(env.events.contains("start"))
    }

    func testInitiallyApprovedButUnsuccessfulTerminationNeverWritesAuthenticationOrBackup() async throws {
        let previous = try syntheticAuth("previous"), target = try syntheticAuth("next")
        let host = Host([process(10, executable: Self.main)])
        let env = TransactionEnvironment(host: host, live: previous)
        env.terminationAlreadyApproved = true
        await transactionFailure(env, target: target)
        XCTAssertEqual(host.quits, 0)
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertEqual(host.signals.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertEqual(env.live, previous)
        XCTAssertNil(env.backup)
        XCTAssertTrue(env.writes.isEmpty)
        XCTAssertEqual(env.events, ["preflight", "stop"])
    }

    func testNormalQuitNeverRequestsForceOrSendsSignals() async throws {
        let host = Host([process(10, executable: Self.main), process(11, parent: 10)])
        host.onQuit = { host.rows = [] }
        let shutdown = host.shutdown()
        try await host.stop(shutdown)
        XCTAssertEqual(host.quits, 1)
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertTrue(host.signals.isEmpty)
        try shutdown.verifyStopped()
    }

    func testAlreadyStoppedDoesNotPromptOrSignal() async throws {
        let host = Host([]), shutdown = host.shutdown()
        try await host.stop(shutdown)
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertTrue(host.signals.isEmpty)
        try shutdown.verifyStopped()
    }

    func testDecliningForcePreservesRunningProcesses() async {
        let root = process(10, executable: Self.main)
        let host = Host([root]), shutdown = host.shutdown()
        await failure(host, shutdown)
        XCTAssertEqual(host.prompts.count, 1)
        XCTAssertEqual(host.prompts.first?.mainAppRunning, true)
        XCTAssertEqual(host.prompts.first?.processCount, 1)
        XCTAssertTrue(host.signals.isEmpty)
        XCTAssertEqual(host.rows, [root])
        XCTAssertThrowsError(try shutdown.verifyStopped())
    }

    func testExplicitConsentUsesTERMAndStopsBeforeKILLWhenProcessExits() async throws {
        let root = process(10, executable: Self.main)
        let host = Host([root]); host.approved = true
        host.onSignal = { identity, _ in host.rows.removeAll { $0.identity == identity } }
        let shutdown = host.shutdown()
        try await host.stop(shutdown)
        XCTAssertEqual(host.prompts.count, 1)
        XCTAssertEqual(host.signals.map(\.0), [root.identity])
        XCTAssertEqual(host.signals.map(\.1), [SIGTERM])
        try shutdown.verifyStopped()
    }

    func testExplicitConsentEscalatesToKILLOnlyAfterTERMWait() async throws {
        let root = process(10, executable: Self.main)
        let host = Host([root]); host.approved = true
        var waitsAtSignals: [Int] = []
        host.onSignal = { identity, signal in
            waitsAtSignals.append(host.waits)
            if signal == SIGKILL { host.rows.removeAll { $0.identity == identity } }
        }
        let shutdown = host.shutdown()
        try await host.stop(shutdown)
        XCTAssertEqual(host.signals.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertEqual(waitsAtSignals, [2, 4])
        try shutdown.verifyStopped()
    }

    func testCapturedChildRemainsOwnedAfterBecomingOrphan() async throws {
        let root = process(10, executable: Self.main), child = process(11, parent: 10)
        let orphan = process(11)
        let host = Host([root, child]); host.approved = true
        host.onQuit = { host.rows = [orphan] }
        host.onSignal = { identity, _ in host.rows.removeAll { $0.identity == identity } }
        let shutdown = host.shutdown()
        try await host.stop(shutdown)
        XCTAssertEqual(host.prompts.first?.mainAppRunning, false)
        XCTAssertEqual(host.prompts.first?.processCount, 1)
        XCTAssertEqual(host.signals.map(\.0), [child.identity])
        try shutdown.verifyStopped()
    }

    func testChildBornDuringGracefulWaitIsRememberedBeforeRootExits() async throws {
        let root = process(10, executable: Self.main), child = process(11, parent: 10)
        let orphan = process(11)
        let host = Host([root]); host.approved = true
        host.onWait = { host.rows = host.waits == 1 ? [root, child] : [orphan] }
        host.onSignal = { _, _ in host.rows = [] }
        let shutdown = host.shutdown()
        try await host.stop(shutdown)
        XCTAssertEqual(host.signals.map(\.0), [child.identity])
        try shutdown.verifyStopped()
    }

    func testCLIThroughNonCLIHelperIsRecognizedByAncestry() async throws {
        let root = process(10, executable: Self.main)
        let helper = process(11, parent: 10, executable: "/tmp/Synthetic Helper")
        let child = process(12, parent: 11)
        let host = Host([root, helper, child]); host.approved = true
        host.onQuit = { host.rows = [child] }
        host.onSignal = { _, _ in host.rows = [] }
        try await host.stop(host.shutdown())
        XCTAssertEqual(host.signals.map(\.0), [child.identity])
    }

    func testUnknownOrphanIsBlockedWithoutOfferingForce() async {
        let orphan = process(11)
        let host = Host([orphan]); host.approved = true
        await failure(host, host.shutdown())
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertTrue(host.signals.isEmpty)
        XCTAssertEqual(host.rows, [orphan])
    }

    func testIndependentCLIWithSameExecutableIsNeverEnded() async {
        let root = process(10, executable: Self.main), child = process(11, parent: 10)
        let independent = process(12, parent: 400)
        let host = Host([root, child, independent]); host.approved = true
        host.onQuit = { host.rows = [independent] }
        await failure(host, host.shutdown())
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertTrue(host.signals.isEmpty)
    }

    func testZombieDoesNotBlockCompletedShutdown() async throws {
        let root = process(10, executable: Self.main), zombie = process(11, parent: 10, zombie: true)
        let host = Host([root, zombie])
        host.onQuit = { host.rows = [zombie] }
        let shutdown = host.shutdown()
        try await host.stop(shutdown)
        XCTAssertTrue(host.signals.isEmpty)
        XCTAssertTrue(host.prompts.isEmpty)
        try shutdown.verifyStopped()
    }

    func testPIDBirthTimeUIDAndExecutableChangesAreNotApprovedTargets() async {
        let root = process(10, executable: Self.main), child = process(11, parent: 10)
        let replacements = [process(11, seconds: 101), process(11, microseconds: 21),
                            process(11, uid: 502), process(11, executable: Self.packagedCLI)]
        for replacement in replacements {
            let host = Host([root, child]); host.approved = true
            host.onQuit = { host.rows = [replacement] }
            await failure(host, host.shutdown())
            XCTAssertTrue(host.prompts.isEmpty)
            XCTAssertTrue(host.signals.isEmpty)
        }
    }

    func testReusedPIDForUnrelatedExecutableIsNeverSignalled() async throws {
        let root = process(10, executable: Self.main), child = process(11, parent: 10)
        let replacement = process(11, executable: "/usr/bin/unrelated", seconds: 200)
        let host = Host([root, child]); host.approved = true
        host.onQuit = { host.rows = [replacement] }
        try await host.stop(host.shutdown())
        XCTAssertTrue(host.signals.isEmpty)
        XCTAssertEqual(host.rows, [replacement])
    }

    func testKnownProcessExecChangeBlocksWithoutSignallingReplacement() async {
        let root = process(10, executable: Self.main), child = process(11, parent: 10)
        let changed = process(11, executable: "/usr/bin/unrelated")
        let host = Host([root, child]); host.approved = true
        host.onQuit = { host.rows = [changed] }
        await failure(host, host.shutdown())
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertTrue(host.signals.isEmpty)
    }

    func testNewRootDuringGracefulQuitIsNotForceTerminated() async {
        let host = Host([process(10, executable: Self.main)]); host.approved = true
        let restarted = process(20, executable: Self.main, seconds: 200)
        host.onQuit = { host.rows = [restarted] }
        await failure(host, host.shutdown())
        XCTAssertTrue(host.signals.isEmpty)
        XCTAssertTrue(host.prompts.isEmpty)
    }

    func testRestartDuringConfirmationInvalidatesApprovedSet() async {
        let host = Host([process(10, executable: Self.main)]); host.approved = true
        let restarted = process(10, executable: Self.main, seconds: 200)
        host.onConfirm = { host.rows = [restarted] }
        await failure(host, host.shutdown())
        XCTAssertEqual(host.prompts.count, 1)
        XCTAssertTrue(host.signals.isEmpty)
    }

    func testChildBornAfterConfirmationRequiresAnotherAttempt() async {
        let root = process(10, executable: Self.main), newChild = process(11, parent: 10)
        let host = Host([root]); host.approved = true
        host.onConfirm = { host.rows = [root, newChild] }
        await failure(host, host.shutdown())
        XCTAssertEqual(host.prompts.count, 1)
        XCTAssertTrue(host.signals.isEmpty)
    }

    func testReadFailureBeforeQuitDoesNotRequestQuitOrForce() async {
        let host = Host([process(10, executable: Self.main)]); host.readFailureAt = 1
        await failure(host, host.shutdown())
        XCTAssertEqual(host.quits, 0)
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertTrue(host.signals.isEmpty)
    }

    func testReadFailureAfterApprovalDoesNotSendSignals() async {
        let host = Host([process(10, executable: Self.main)]); host.approved = true
        host.onConfirm = { host.readFailureAt = host.reads + 1 }
        await failure(host, host.shutdown())
        XCTAssertEqual(host.prompts.count, 1)
        XCTAssertTrue(host.signals.isEmpty)
    }

    func testSignalFailureStopsWithoutKILLEscalation() async {
        let host = Host([process(10, executable: Self.main)]); host.approved = true; host.signalFails = true
        let shutdown = host.shutdown()
        await failure(host, shutdown)
        XCTAssertEqual(host.prompts.count, 1)
        XCTAssertTrue(host.signals.isEmpty)
        XCTAssertThrowsError(try shutdown.verifyStopped())
    }

    func testSurvivingTERMAndKILLNeverMarksShutdownComplete() async {
        let host = Host([process(10, executable: Self.main)]); host.approved = true
        let shutdown = host.shutdown()
        await failure(host, shutdown)
        XCTAssertEqual(host.signals.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertThrowsError(try shutdown.verifyStopped())
    }

    func testCancellationDuringWaitNeverOffersForce() async {
        let host = Host([process(10, executable: Self.main)]); host.approved = true
        host.onWait = { throw CancellationError() }
        let error = await failure(host, host.shutdown())
        XCTAssertTrue(error is CancellationError)
        XCTAssertTrue(host.prompts.isEmpty)
        XCTAssertTrue(host.signals.isEmpty)
    }

    func testVerifyStoppedRejectsUnfinishedAttemptAndNewRootOrCLI() async throws {
        let host = Host([]), shutdown = host.shutdown()
        XCTAssertThrowsError(try shutdown.verifyStopped())
        try await host.stop(shutdown)
        try shutdown.verifyStopped()
        host.rows = [process(10, executable: Self.main)]
        XCTAssertThrowsError(try shutdown.verifyStopped())
        host.rows = [process(11)]
        XCTAssertThrowsError(try shutdown.verifyStopped())
        host.rows = []; host.readFailureAt = host.reads + 1
        XCTAssertThrowsError(try shutdown.verifyStopped())
    }

    func testSystemAdapterInspectsAndSignalsOnlyItsOwnSleepFixture() throws {
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: "/bin/sleep")
        fixture.arguments = ["10"]
        fixture.standardOutput = FileHandle.nullDevice
        fixture.standardError = FileHandle.nullDevice
        try fixture.run()
        defer {
            if fixture.isRunning { fixture.terminate() }
            fixture.waitUntilExit()
        }
        let observed = try XCTUnwrap(SystemDesktopProcesses.inspect(fixture.processIdentifier))
        XCTAssertEqual(observed.identity.pid, fixture.processIdentifier)
        XCTAssertEqual(observed.identity.uid, getuid())
        XCTAssertEqual(observed.identity.executable, URL(fileURLWithPath: "/bin/sleep").resolvingSymlinksInPath().path)
        XCTAssertEqual(observed.parent, getpid())
        XCTAssertFalse(observed.zombie)
        let mismatch = DesktopProcess.Identity(pid: observed.identity.pid,
                                              startedSeconds: observed.identity.startedSeconds + 1,
                                              startedMicroseconds: observed.identity.startedMicroseconds,
                                              executable: observed.identity.executable, uid: observed.identity.uid)
        XCTAssertThrowsError(try SystemDesktopProcesses.signal(mismatch, SIGTERM))
        XCTAssertTrue(fixture.isRunning)
        try SystemDesktopProcesses.signal(observed.identity, SIGTERM)
        fixture.waitUntilExit()
        XCTAssertEqual(fixture.terminationReason, .uncaughtSignal)
        XCTAssertEqual(fixture.terminationStatus, SIGTERM)
    }

    func testSystemSnapshotCanReadCurrentUserMetadata() throws {
        let rows = try SystemDesktopProcesses.snapshot()
        XCTAssertTrue(rows.contains { $0.identity.pid == getpid() })
        XCTAssertTrue(rows.allSatisfy { $0.identity.uid == getuid() })
    }
}
