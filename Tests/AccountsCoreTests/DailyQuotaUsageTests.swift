import XCTest
@testable import AccountsCore

final class DailyQuotaUsageTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!; return value
    }
    func quota(_ remaining: Double, reset: Date? = nil, id: String = "codex.week", label: String = "7 天") -> QuotaWindow {
        .init(id: id, label: label, remaining: remaining, resetsAt: reset, bucketID: "codex")
    }
    func testBaselineUnknownThenAccumulatesAndSurvivesEncoding() throws {
        let now = date("2026-09-20T04:00:00Z"), cal = calendar()
        var usage = DailyQuotaUsage(at: now, calendar: cal)
        usage.record([quota(80)], at: now, calendar: cal)
        XCTAssertNil(usage.observation(for: quota(80), now: now, calendar: cal)?.used)
        usage.record([quota(72)], at: now.addingTimeInterval(300), calendar: cal)
        usage = try JSONDecoder().decode(DailyQuotaUsage.self, from: JSONEncoder().encode(usage))
        usage.record([quota(70)], at: now.addingTimeInterval(600), calendar: cal)
        XCTAssertEqual(usage.observation(for: quota(70), now: now.addingTimeInterval(600), calendar: cal)?.used, 10)
    }
    func testTwoUnchangedSamplesMeanZeroRatherThanMissing() {
        let now = date("2026-09-20T04:00:00Z"), cal = calendar()
        var usage = DailyQuotaUsage(at: now, calendar: cal)
        usage.record([quota(100)], at: now, calendar: cal)
        usage.record([quota(100)], at: now.addingTimeInterval(1), calendar: cal)
        XCTAssertEqual(usage.observation(for: quota(100), now: now.addingTimeInterval(1), calendar: cal)?.used, 0)
    }
    func testMidnightAndTimeZoneChangesDoNotAttributeEarlierUsage() {
        let before = date("2026-09-20T15:59:00Z"), after = date("2026-09-20T16:01:00Z"), cal = calendar()
        var usage = DailyQuotaUsage(at: before, calendar: cal)
        usage.record([quota(80)], at: before, calendar: cal)
        XCTAssertNil(usage.observation(for: quota(80), now: after, calendar: cal))
        usage.record([quota(60)], at: after, calendar: cal)
        XCTAssertNil(usage.observation(for: quota(60), now: after, calendar: cal)?.used)
        XCTAssertNil(usage.observation(for: quota(60), now: after, calendar: calendar("America/Los_Angeles")))
    }
    func testDSTRepeatedHourStaysWithinSameLocalDay() {
        let first = date("2026-11-01T08:30:00Z"), second = date("2026-11-01T09:30:00Z"), cal = calendar("America/Los_Angeles")
        var usage = DailyQuotaUsage(at: first, calendar: cal)
        usage.record([quota(80)], at: first, calendar: cal)
        usage.record([quota(70)], at: second, calendar: cal)
        XCTAssertEqual(usage.observation(for: quota(70), now: second, calendar: cal)?.used, 10)
    }
    func testResetAndReplenishmentAreNotInventedConsumption() {
        let now = date("2026-09-20T04:00:00Z"), cal = calendar()
        let reset = now.addingTimeInterval(1000), next = now.addingTimeInterval(5000)
        var usage = DailyQuotaUsage(at: now, calendar: cal)
        usage.record([quota(80, reset: reset)], at: now, calendar: cal)
        usage.record([quota(75, reset: reset)], at: now.addingTimeInterval(1), calendar: cal)
        usage.record([quota(10, reset: next)], at: now.addingTimeInterval(1200), calendar: cal)
        usage.record([quota(90, reset: next)], at: now.addingTimeInterval(1300), calendar: cal)
        usage.record([quota(88, reset: next)], at: now.addingTimeInterval(1400), calendar: cal)
        let observation = usage.observation(for: quota(88, reset: next), now: now.addingTimeInterval(1400), calendar: cal)
        XCTAssertEqual(observation?.used, 7); XCTAssertEqual(observation?.incomplete, true)
    }
    func testWindowsRemainIndependentAndChangedDurationStartsUnknown() {
        let now = date("2026-09-20T04:00:00Z"), cal = calendar()
        var usage = DailyQuotaUsage(at: now, calendar: cal)
        usage.record([quota(80), quota(90, id: "codex.short", label: "5 小时")], at: now, calendar: cal)
        usage.record([quota(70), quota(60, id: "codex.short", label: "5 小时")], at: now.addingTimeInterval(1), calendar: cal)
        XCTAssertEqual(usage.observation(for: quota(70), now: now.addingTimeInterval(1), calendar: cal)?.used, 10)
        XCTAssertEqual(usage.observation(for: quota(60, id: "codex.short", label: "5 小时"), now: now.addingTimeInterval(1), calendar: cal)?.used, 30)
        usage.record([quota(20, label: "5 小时")], at: now.addingTimeInterval(2), calendar: cal)
        XCTAssertNil(usage.observation(for: quota(20, label: "5 小时"), now: now.addingTimeInterval(2), calendar: cal)?.used)
    }
    func testInvalidAndOutOfOrderSamplesLeaveHistoryIntact() {
        let now = date("2026-09-20T04:00:00Z"), cal = calendar()
        var usage = DailyQuotaUsage(at: now, calendar: cal)
        usage.record([quota(80)], at: now, calendar: cal)
        usage.record([quota(70)], at: now.addingTimeInterval(1), calendar: cal)
        let original = usage
        usage.record([quota(10)], at: now.addingTimeInterval(-10), calendar: cal)
        usage.record([quota(.nan)], at: now.addingTimeInterval(2), calendar: cal)
        usage.record([quota(200)], at: now.addingTimeInterval(3), calendar: cal)
        XCTAssertEqual(usage, original)
    }
    func testOldAccountWithoutDailyFieldStillDecodes() throws {
        let account = try Account(snapshot: AuthSnapshot(sample()))
        let bytes = try JSONEncoder().encode(account)
        XCTAssertNil(try JSONDecoder().decode(Account.self, from: bytes).dailyUsage)
    }
}
