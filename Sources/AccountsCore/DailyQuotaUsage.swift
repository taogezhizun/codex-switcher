import Foundation

/// Local observations, in percentage points of each independent quota window.
/// This is not an official daily allowance or a complete usage ledger.
public struct DailyQuotaUsage: Codable, Equatable {
    public struct Observation: Codable, Equatable {
        public var used: Double?
        public var startedAt: Date
        public var observedAt: Date
        public var incomplete: Bool
        var remaining: Double
        var resetsAt: Date?
        var label: String
        var bucketID: String?
    }
    public private(set) var day: Date
    public private(set) var timeZoneID: String
    private var windows: [String: Observation] = [:]

    public init(at date: Date, calendar: Calendar = .autoupdatingCurrent) {
        day = calendar.startOfDay(for: date)
        timeZoneID = calendar.timeZone.identifier
    }

    public mutating func record(_ quotas: [QuotaWindow], at date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard date.timeIntervalSince1970.isFinite else { return }
        // Never move history backwards because of a delayed response or clock correction.
        guard !windows.values.contains(where: { $0.observedAt > date }) else { return }
        if day != calendar.startOfDay(for: date) || timeZoneID != calendar.timeZone.identifier {
            self = Self(at: date, calendar: calendar)
        }
        for quota in quotas where quota.remaining.isFinite && (0...100).contains(quota.remaining) {
            guard quota.resetsAt?.timeIntervalSince1970.isFinite != false else { continue }
            if var previous = windows[quota.id], previous.label == quota.label, previous.bucketID == quota.bucketID {
                guard date > previous.observedAt else { continue }
                let sameReset = previous.resetsAt == quota.resetsAt
                let beforeReset = previous.resetsAt.map { date < $0 } ?? true
                if sameReset && beforeReset && quota.remaining <= previous.remaining {
                    previous.used = (previous.used ?? 0) + previous.remaining - quota.remaining
                } else {
                    // Reset, replenishment or correction: keep already observed usage,
                    // but do not guess consumption across this discontinuity.
                    previous.incomplete = true
                }
                previous.remaining = quota.remaining
                previous.resetsAt = quota.resetsAt
                previous.observedAt = date
                windows[quota.id] = previous
            } else {
                windows[quota.id] = Observation(used: nil, startedAt: date, observedAt: date, incomplete: false,
                                                remaining: quota.remaining, resetsAt: quota.resetsAt,
                                                label: quota.label, bucketID: quota.bucketID)
            }
        }
    }

    public func observation(for quota: QuotaWindow, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Observation? {
        guard day == calendar.startOfDay(for: now), timeZoneID == calendar.timeZone.identifier,
              let value = windows[quota.id], value.label == quota.label, value.bucketID == quota.bucketID,
              value.observedAt <= now else { return nil }
        return value
    }
}
