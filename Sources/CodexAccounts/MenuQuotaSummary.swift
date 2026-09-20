import Foundation
import AccountsCore

/// Compact visible quota plus complete, local-time details for hover and VoiceOver.
struct MenuQuotaSummary {
    let text: String
    let help: String

    private static func offset(_ timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        return String(format: "UTC%@%02d:%02d", seconds >= 0 ? "+" : "-", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
    }

    static func make(account: Account, now: Date, timeZone: TimeZone = .autoupdatingCurrent,
                     locale: Locale = .autoupdatingCurrent) -> Self {
        guard let quota = QuotaPresentation.summary(account.quotas), quota.remaining.isFinite else {
            return Self(text: "额度未读取", help: "尚未读取 Codex 额度")
        }
        let stale = AccountPresentation.needsRefresh(account, now: now)
        let percent = Int(min(100, max(0, quota.remaining)))
        var text = "\(stale ? "上次剩余" : "剩余") \(percent)%"
        var details = ["\(account.plan.uppercased()) · Codex \(QuotaPresentation.duration(quota))额度"]
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        if let reset = quota.resetsAt, reset.timeIntervalSince1970.isFinite {
            let sameYear = calendar.component(.year, from: now) == calendar.component(.year, from: reset)
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMdjmm" : "yMMMdjmm")
            text += reset > now ? " · \(formatter.string(from: reset)) 重置" : " · 重置时间已到"
            formatter.setLocalizedDateFormatFromTemplate("yMMMdjmm")
            details.append("重置时间：\(formatter.string(from: reset))（\(timeZone.identifier)，\(offset(timeZone, at: reset))）")
            let seconds = reset.timeIntervalSince(now)
            if seconds > 0 {
                let countdown: String
                if seconds >= 86400 { countdown = "约 \(Int(ceil(seconds / 86400))) 天" }
                else if seconds >= 3600 { countdown = "约 \(Int(ceil(seconds / 3600))) 小时" }
                else { countdown = "约 \(max(1, Int(ceil(seconds / 60)))) 分钟" }
                details.append("距重置还剩\(countdown)")
            } else { details.append("重置时间已到，等待额度查询确认") }
        } else { details.append("接口未提供重置时间") }
        if let updated = account.updatedAt {
            formatter.setLocalizedDateFormatFromTemplate("yMMMdjmm")
            details.append("上次查询：\(formatter.string(from: updated))（\(timeZone.identifier)）")
        } else { details.append("尚未刷新") }
        if stale { details.append("当前显示上次记录，请刷新确认") }
        return Self(text: text, help: details.joined(separator: "\n"))
    }
}
