import XCTest
import AccountsCore
@testable import CodexAccounts

final class MenuQuotaSummaryTests: XCTestCase {
    let locale = Locale(identifier: "zh_CN")
    func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    func account(now: Date, reset: Date?) throws -> Account {
        var account = try Account(snapshot: AuthSnapshot(syntheticAuth("a")))
        account.updatedAt = now
        account.quotas = [.init(id: "codex.week", label: "7 天", remaining: 43, resetsAt: reset, bucketID: "codex")]
        return account
    }
    func testLocalTimezoneCrossesDateBoundaryAndKeepsPeriodInHelp() throws {
        let now = date("2026-09-20T07:30:00Z")
        let a = try account(now: now, reset: date("2026-09-24T00:30:00Z"))
        let shanghai = MenuQuotaSummary.make(account: a, now: now, timeZone: TimeZone(identifier: "Asia/Shanghai")!, locale: locale)
        let losAngeles = MenuQuotaSummary.make(account: a, now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!, locale: locale)
        XCTAssertTrue(shanghai.text.hasPrefix("剩余 43% · "))
        XCTAssertTrue(shanghai.text.contains("24")); XCTAssertTrue(shanghai.text.contains("08:30"))
        XCTAssertTrue(losAngeles.text.contains("23")); XCTAssertTrue(losAngeles.text.contains("17:30"))
        XCTAssertFalse(shanghai.text.contains("7 天")); XCTAssertFalse(shanghai.text.contains("查询"))
        XCTAssertTrue(shanghai.help.contains("7 天")); XCTAssertTrue(shanghai.help.contains("还剩约 4 天"))
        XCTAssertTrue(shanghai.help.contains("Asia/Shanghai")); XCTAssertTrue(shanghai.help.contains("上次查询"))
        XCTAssertFalse(shanghai.help.contains(a.email))
    }
    func testResetDateUsesTimezoneOffsetAfterDSTTransition() throws {
        let now = date("2026-10-31T08:00:00Z")
        let a = try account(now: now, reset: date("2026-11-02T08:30:00Z"))
        let value = MenuQuotaSummary.make(account: a, now: now, timeZone: TimeZone(identifier: "America/Los_Angeles")!, locale: locale)
        XCTAssertTrue(value.text.contains("00:30")); XCTAssertTrue(value.help.contains("UTC-08:00"))
    }
    func testMissingDateDoesNotInventResetAndOldQuotaStaysMarked() throws {
        let now = date("2026-09-20T07:30:00Z")
        var a = try account(now: now, reset: nil)
        XCTAssertEqual(MenuQuotaSummary.make(account: a, now: now).text, "剩余 43%")
        a.issue = "Synthetic failure"
        let value = MenuQuotaSummary.make(account: a, now: now)
        XCTAssertEqual(value.text, "上次剩余 43%")
        XCTAssertTrue(value.help.contains("未提供重置时间"))
    }
    func testElapsedResetDoesNotClaimRestoredQuota() throws {
        let now = date("2026-09-20T07:30:00Z")
        var a = try account(now: now, reset: now)
        a.updatedAt = now.addingTimeInterval(-60)
        let value = MenuQuotaSummary.make(account: a, now: now)
        XCTAssertEqual(value.text, "上次剩余 43% · 重置时间已到")
        XCTAssertTrue(value.help.contains("等待额度查询确认")); XCTAssertFalse(value.help.contains("还剩"))
    }
    func testYearBoundaryIncludesYearAndUnknownQuotaIsSeparate() throws {
        let now = date("2026-12-30T07:30:00Z")
        var a = try account(now: now, reset: date("2027-01-02T07:30:00Z"))
        XCTAssertTrue(MenuQuotaSummary.make(account: a, now: now, timeZone: TimeZone(secondsFromGMT: 0)!, locale: locale).text.contains("2027"))
        a.quotas = []
        XCTAssertEqual(MenuQuotaSummary.make(account: a, now: now).text, "额度未读取")
    }
    func testRemainingAndResetComeFromSameSelectedWindow() throws {
        let now = date("2026-09-20T07:30:00Z")
        var a = try account(now: now, reset: date("2026-09-24T07:30:00Z"))
        a.quotas.append(.init(id: "codex.short", label: "5 小时", remaining: 10, resetsAt: date("2026-09-20T09:30:00Z"), bucketID: "codex"))
        let value = MenuQuotaSummary.make(account: a, now: now, timeZone: TimeZone(secondsFromGMT: 0)!, locale: locale)
        XCTAssertTrue(value.text.hasPrefix("剩余 10%")); XCTAssertTrue(value.text.contains("09:30"))
        XCTAssertTrue(value.help.contains("5 小时")); XCTAssertFalse(value.help.contains("7 天"))
    }
}
