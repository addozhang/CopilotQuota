import Foundation

/// Raw `/copilot_internal/user` response (only the fields we consume).
///
/// Docs of the community-verified shape:
/// https://github.com/steipete/CodexBar/blob/main/docs/copilot.md
struct CopilotUserResponse: Decodable {
    let login: String?
    let copilotPlan: String?
    let accessTypeSku: String?
    let quotaResetDateUTC: String?
    let quotaSnapshots: QuotaSnapshots?

    enum CodingKeys: String, CodingKey {
        case login
        case copilotPlan = "copilot_plan"
        case accessTypeSku = "access_type_sku"
        case quotaResetDateUTC = "quota_reset_date_utc"
        case quotaResetDate = "quota_reset_date"
        case quotaSnapshots = "quota_snapshots"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        login = try c.decodeIfPresent(String.self, forKey: .login)
        copilotPlan = try c.decodeIfPresent(String.self, forKey: .copilotPlan)
        accessTypeSku = try c.decodeIfPresent(String.self, forKey: .accessTypeSku)
        quotaResetDateUTC = try c.decodeIfPresent(String.self, forKey: .quotaResetDateUTC)
            ?? c.decodeIfPresent(String.self, forKey: .quotaResetDate)
        quotaSnapshots = try c.decodeIfPresent(QuotaSnapshots.self, forKey: .quotaSnapshots)
    }
}

struct QuotaSnapshots: Decodable {
    let chat: QuotaSnapshot?
    let completions: QuotaSnapshot?
    let premiumInteractions: QuotaSnapshot?

    enum CodingKeys: String, CodingKey {
        case chat
        case completions
        case premiumInteractions = "premium_interactions"
    }
}

struct QuotaSnapshot: Decodable {
    let entitlement: Double?
    let remaining: Double?
    let percentRemaining: Double?
    let unlimited: Bool?

    enum CodingKeys: String, CodingKey {
        case entitlement
        case remaining
        case unlimited
        case percentRemaining = "percent_remaining"
    }
}

/// Per-category quota distilled for display.
struct CategoryQuota: Codable, Equatable {
    /// `nil` when the category is unlimited.
    var percentRemaining: Double?
    var unlimited: Bool
}

/// The value the widget renders / the app shows.
struct QuotaDisplay: Codable, Equatable {
    /// Primary category, 0–100 (unlimited counts as 100).
    var percentRemaining: Double
    var primaryCategoryLabel: String
    var planLabel: String?
    var login: String?
    var resetDate: String?
    var fetchedAt: Date
    var premium: CategoryQuota?
    var chat: CategoryQuota?
    var completions: CategoryQuota?

    static var placeholder: QuotaDisplay {
        QuotaDisplay(percentRemaining: 83,
                     primaryCategoryLabel: "Premium requests",
                     planLabel: "Copilot Pro",
                     login: "octocat",
                     resetDate: nil,
                     fetchedAt: .now,
                     premium: CategoryQuota(percentRemaining: 83, unlimited: false),
                     chat: CategoryQuota(percentRemaining: 100, unlimited: false),
                     completions: nil)
    }

    /// Reset date rendered as a localized medium date ("Nov 1, 2026" /
    /// "2026年11月1日"). `nil` when the raw value is missing or unparseable.
    var resetDateLocalized: String? {
        guard let date = Self.parseResetDate(resetDate) else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC") // GitHub reports a calendar date at UTC midnight
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Accepts ISO-8601 with/without fractional seconds and plain "yyyy-MM-dd".
    static func parseResetDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.count == 10 {
            let dayOnly = DateFormatter()
            dayOnly.dateFormat = "yyyy-MM-dd"
            dayOnly.timeZone = TimeZone(identifier: "UTC")
            return dayOnly.date(from: raw)
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

extension CopilotUserResponse {
    var friendlyPlan: String? {
        guard let copilotPlan else { return nil }
        switch copilotPlan {
        case "free": return "Copilot Free"
        case "individual": return "Copilot Pro"
        case "business": return "Copilot Business"
        case "enterprise": return "Copilot Enterprise"
        default:
            return "Copilot " + copilotPlan.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func category(_ snapshot: QuotaSnapshot?) -> CategoryQuota? {
        guard let snapshot else { return nil }
        if snapshot.unlimited == true {
            return CategoryQuota(percentRemaining: nil, unlimited: true)
        }
        let percent = min(100, max(0, snapshot.percentRemaining ?? 100))
        return CategoryQuota(percentRemaining: percent, unlimited: false)
    }

    /// Prefer the metered "premium interactions" bucket, then chat, then completions.
    /// (Same priority CodexBar uses: primary = premiumInteractions, secondary = chat.)
    var primaryCategory: (label: String, quota: CategoryQuota)? {
        let candidates: [(String, QuotaSnapshot?)] = [
            ("Premium requests", quotaSnapshots?.premiumInteractions),
            ("Chat", quotaSnapshots?.chat),
            ("Completions", quotaSnapshots?.completions),
        ]
        // First pass: a metered (non-unlimited) bucket wins.
        for (label, snapshot) in candidates {
            if let quota = category(snapshot), !quota.unlimited {
                return (label, quota)
            }
        }
        // Fall back to anything present (e.g. unlimited plan).
        for (label, snapshot) in candidates {
            if let quota = category(snapshot) {
                return (label, quota)
            }
        }
        return nil
    }

    var display: QuotaDisplay? {
        guard let primary = primaryCategory else { return nil }
        return QuotaDisplay(
            percentRemaining: primary.quota.unlimited ? 100 : (primary.quota.percentRemaining ?? 100),
            primaryCategoryLabel: primary.label,
            planLabel: friendlyPlan,
            login: login,
            resetDate: quotaResetDateUTC,
            fetchedAt: .now,
            premium: category(quotaSnapshots?.premiumInteractions),
            chat: category(quotaSnapshots?.chat),
            completions: category(quotaSnapshots?.completions))
    }
}
