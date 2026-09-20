import Foundation
import AccountsCore

struct DailyUsagePresentation {
    let text: String
    let help: String

    static func make(account: Account, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Self {
        guard let quota = QuotaPresentation.summary(account.quotas),
              let observation = account.dailyUsage?.observation(for: quota, now: now, calendar: calendar),
              let used = observation.used, used.isFinite else {
            return Self(text: "今日已用 —", help: "今天还没有足够的有效记录。至少需要两次可比较的额度查询；不会把本周期已用当作今日用量。")
        }
        let number = used.formatted(.number.precision(.fractionLength(0...1)))
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        var help = "本机今日观察到的 Codex \(QuotaPresentation.duration(quota))额度消耗，单位为该周期额度的百分点。\n从 \(formatter.string(from: observation.startedAt)) 开始记录，更新于 \(formatter.string(from: observation.observedAt))（\(calendar.timeZone.identifier)）。\n这是估算，并非官方日额度；未记录期间的用量可能未计入。"
        if observation.incomplete { help += "\n遇到重置或额度回升，跨越该变化的消耗未计入。" }
        if AccountPresentation.needsRefresh(account, now: now) { help += "\n当前为上次记录，请刷新确认。" }
        return Self(text: "今日已用≈\(number)%", help: help)
    }
}
