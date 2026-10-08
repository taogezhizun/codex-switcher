import XCTest
import AccountsCore
@testable import CodexAccounts

@MainActor final class DesktopCompatibilityTests: XCTestCase {
    private func application(in root: URL, bundleID: String = "com.openai.codex") throws -> URL {
        let app = root.appendingPathComponent("Desktop.app")
        try PrivateFiles.write(PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID], format: .xml, options: 0),
                               to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
    private func executable(in app: URL, entry: String) throws -> URL {
        let url = app.appendingPathComponent(entry)
        try PrivateFiles.write(Data("synthetic executable placeholder".utf8), to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    func testResolveLegacyAndUpdatedPackageWithoutCachingOldPath() throws {
        let fixture = try StoreFixture()
        let app = try application(in: fixture.root)
        let legacy = try executable(in: app, entry: "Contents/Resources/codex")
        XCTAssertEqual(try Desktop.resolveExecutable(in: app), legacy)
        let packaged = try executable(in: app, entry: "Contents/Resources/codex-cli/bin/codex")
        XCTAssertEqual(try Desktop.resolveExecutable(in: app), packaged)
        try FileManager.default.removeItem(at: legacy)
        XCTAssertEqual(try Desktop.resolveExecutable(in: app), packaged)
    }
    func testRejectWrongApplicationEvenIfItContainsExecutable() throws {
        let fixture = try StoreFixture()
        let app = try application(in: fixture.root, bundleID: "example.unrelated")
        _ = try executable(in: app, entry: "Contents/Resources/codex-cli/bin/codex")
        XCTAssertThrowsError(try Desktop.resolveExecutable(in: app)) {
            guard case DesktopCompatibilityError.unsupportedApplication = $0 else { return XCTFail("Expected application error") }
        }
    }
    func testMissingNonExecutableAndDirectoryAreNotValidLaunchers() throws {
        let fixture = try StoreFixture()
        let app = try application(in: fixture.root)
        func expectMissing() {
            XCTAssertThrowsError(try Desktop.resolveExecutable(in: app)) {
                guard case DesktopCompatibilityError.missingCLI = $0 else { return XCTFail("Expected compatibility error") }
            }
        }
        expectMissing()
        let packaged = try executable(in: app, entry: "Contents/Resources/codex-cli/bin/codex")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: packaged.path)
        expectMissing()
        try FileManager.default.removeItem(at: packaged)
        try FileManager.default.createDirectory(at: packaged, withIntermediateDirectories: true)
        expectMissing()
        let legacy = try executable(in: app, entry: "Contents/Resources/codex")
        XCTAssertEqual(try Desktop.resolveExecutable(in: app), legacy)
    }
}
