import Foundation
import CryptoKit

public enum AccountsError: Error, LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

/// Parsed claims are labels, not cryptographic proof of authentication.
public struct AuthSnapshot {
    public let data: Data
    public let identity: String
    public let accountID: String
    public let email: String
    public let plan: String
    public let accessToken: String
    public let subject: String

    public init(_ data: Data) throws {
        guard data.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["OPENAI_API_KEY"] == nil || root["OPENAI_API_KEY"] is NSNull,
              root["auth_mode"] == nil || root["auth_mode"] as? String == "chatgpt",
              let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty,
              let idToken = tokens["id_token"] as? String,
              let claims = Self.claims(idToken),
              let sub = claims["sub"] as? String, !sub.isEmpty,
              let account = tokens["account_id"] as? String, !account.isEmpty else {
            throw AccountsError.message("这不是完整的 ChatGPT 登录凭据。请使用浏览器添加账号，或重新导入 auth.json。")
        }
        self.data = data
        accountID = account
        accessToken = access
        subject = sub
        identity = Self.digest(Data((account + "\u{0}" + sub).utf8))
        email = claims["email"] as? String ?? "未提供邮箱"
        let details = claims["https://api.openai.com/auth"] as? [String: Any]
        plan = details?["chatgpt_plan_type"] as? String ?? "未知套餐"
    }

    public var accessTokenExpiresAt: Date? {
        guard let expiry = Self.claims(accessToken)?["exp"] as? Double, expiry.isFinite else { return nil }
        return Date(timeIntervalSince1970: expiry)
    }

    static func claims(_ token: String) -> [String: Any]? {
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct QuotaWindow: Codable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let remaining: Double
    public let resetsAt: Date?
    public let bucketID: String?
    public let bucketName: String?
    public init(id: String, label: String, remaining: Double, resetsAt: Date? = nil, bucketID: String? = nil, bucketName: String? = nil) {
        self.id = id; self.label = label; self.remaining = remaining; self.resetsAt = resetsAt
        self.bucketID = bucketID; self.bucketName = bucketName
    }
    public static func parse(_ response: [String: Any]) -> [QuotaWindow] {
        var buckets: [(String, [String: Any])] = []
        if let map = response["rateLimitsByLimitId"] as? [String: [String: Any]], !map.isEmpty {
            buckets = map.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value) }
        } else if let legacy = response["rateLimits"] as? [String: Any] { buckets = [("codex", legacy)] }
        return buckets.flatMap { name, bucket in
            ["primary", "secondary"].compactMap { slot -> QuotaWindow? in
                guard let row = bucket[slot] as? [String: Any],
                      let used = row["usedPercent"] as? Double, used.isFinite else { return nil }
                let minutes = (row["windowDurationMins"] as? NSNumber)?.intValue
                let duration: String
                switch minutes {
                case 300: duration = "5 小时"
                case 10080: duration = "7 天"
                case .some(let m) where m > 0: duration = m % 60 == 0 ? "\(m / 60) 小时" : "\(m) 分钟"
                default: duration = slot == "primary" ? "主要窗口" : "次要窗口"
                }
                let reset = (row["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
                return QuotaWindow(id: "\(name).\(slot)", label: duration, remaining: min(100, max(0, 100-used)), resetsAt: reset, bucketID: name, bucketName: bucket["limitName"] as? String)
            }
        }
    }
}

public struct Account: Codable, Identifiable, Equatable {
    public var id: String
    public var nickname: String
    public var email: String
    public var plan: String
    public var quotas: [QuotaWindow]
    public var updatedAt: Date?
    public var issue: String?
    public var quotaNeedsLogin: Bool?
    public var quotaRejectedFingerprint: String?
    public var dailyUsage: DailyQuotaUsage?
    public init(snapshot: AuthSnapshot) {
        id = snapshot.identity; nickname = ""; email = snapshot.email; plan = snapshot.plan; quotas = []
    }
    public var title: String { nickname.isEmpty ? email : nickname }
}
