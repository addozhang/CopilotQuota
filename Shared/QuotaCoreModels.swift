import Foundation
import SwiftUI

/// Supported AI quota providers.
///
/// Additional providers (such as Google AI Pro in v2.1) can be added as new
/// cases without changing the storage, ring renderer, or widget architecture.
public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case copilot
    case deepseek
    case openrouter
    case glm

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .copilot: return "GitHub Copilot"
        case .deepseek: return "DeepSeek"
        case .openrouter: return "OpenRouter"
        case .glm: return "GLM Coding"
        }
    }

    public var shortName: String {
        switch self {
        case .copilot: return "Copilot"
        case .deepseek: return "DeepSeek"
        case .openrouter: return "OpenRouter"
        case .glm: return "GLM"
        }
    }

    public var isBalanceBased: Bool {
        switch self {
        case .deepseek, .openrouter: return true
        case .copilot, .glm: return false
        }
    }

    public var defaultCurrencySymbol: String {
        switch self {
        case .deepseek: return "¥"
        case .openrouter: return "$"
        case .copilot, .glm: return ""
        }
    }
}

public enum GLMRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case cn
    case global

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cn: return "BigModel (open.bigmodel.cn)"
        case .global: return "Z.ai (api.z.ai)"
        }
    }

    public var quotaURL: URL {
        switch self {
        case .cn:
            return URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!
        case .global:
            return URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
        }
    }
}

/// A configured provider account.
///
/// Keyed by UUID so the data model natively supports multiple accounts per
/// provider even when the v2.0 UI defaults to one account per provider.
public struct ProviderAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ProviderKind
    public var displayName: String?
    public var region: String?
    /// Optional cap for prepaid balance providers (e.g. ¥100 / $20).
    /// When set, the ring fills proportionally (`balance / cap`); otherwise it
    /// renders full and changes color based on warning/critical thresholds.
    public var balanceReferenceCap: Double?
    public var warningThreshold: Double?
    public var criticalThreshold: Double?
    public var isEnabled: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        kind: ProviderKind,
        displayName: String? = nil,
        region: String? = nil,
        balanceReferenceCap: Double? = nil,
        warningThreshold: Double? = nil,
        criticalThreshold: Double? = nil,
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.region = region
        self.balanceReferenceCap = balanceReferenceCap
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    public var resolvedTitle: String {
        if let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return kind.displayName
    }

    public var glmRegion: GLMRegion {
        GLMRegion(rawValue: region ?? "") ?? .cn
    }
}

/// A single rolling time window (e.g. GLM 5-hour or weekly quota).
public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    /// Remaining percentage in `0...100`.
    public let percentRemaining: Double
    public let resetAt: Date?

    public init(id: String, label: String, percentRemaining: Double, resetAt: Date? = nil) {
        self.id = id
        self.label = label
        self.percentRemaining = min(100, max(0, percentRemaining))
        self.resetAt = resetAt
    }
}

/// Unified representation of all AI quota types.
public enum QuotaMetric: Codable, Equatable, Sendable {
    case metered(
        percentRemaining: Double,
        remaining: Double?,
        entitlement: Double?,
        resetAt: Date?,
        unlimited: Bool
    )
    case rollingWindows([QuotaWindow])
    case balance(
        amount: Double,
        currency: String,
        granted: Double?,
        toppedUp: Double?
    )
}

/// Latest fetched snapshot for a single configured `ProviderAccount`.
public struct ProviderSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let accountID: UUID
    public let kind: ProviderKind
    public let accountLabel: String?
    public let planLabel: String?
    public let metric: QuotaMetric
    public let fetchedAt: Date
    public let lastError: String?

    public var id: UUID { accountID }

    public init(
        accountID: UUID,
        kind: ProviderKind,
        accountLabel: String? = nil,
        planLabel: String? = nil,
        metric: QuotaMetric,
        fetchedAt: Date = .now,
        lastError: String? = nil
    ) {
        self.accountID = accountID
        self.kind = kind
        self.accountLabel = accountLabel
        self.planLabel = planLabel
        self.metric = metric
        self.fetchedAt = fetchedAt
        self.lastError = lastError
    }
}

// MARK: - Unified Ring Presentation

public enum RingTone: Equatable, Sendable {
    case normal
    case warning
    case critical
    case unavailable

    public var color: Color {
        switch self {
        case .normal:
            return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .warning:
            return Color(red: 1.00, green: 0.62, blue: 0.04)
        case .critical:
            return Color(red: 1.00, green: 0.27, blue: 0.23)
        case .unavailable:
            return Color.primary.opacity(0.25)
        }
    }
}

/// Pure view-model consumed identically by the Popover, `systemSmall`, and `systemMedium` widgets.
public struct RingPresentation: Equatable, Sendable {
    /// `nil` draws an empty track; `0...1` draws the colored arc.
    public let fillFraction: Double?
    public let tone: RingTone
    /// Primary compact label below/beside the ring (e.g. `"83%"`, `"∞"`, `"¥42.5"`, `"—"`).
    public let primaryText: String
    /// Optional detail subtitle (e.g. `"249 / 300"`, `"5h 72% · 7d 45%"`).
    public let secondaryText: String?

    public static let placeholder = RingPresentation(
        fillFraction: 0.83,
        tone: .normal,
        primaryText: "83%",
        secondaryText: "249 / 300"
    )

    public static let empty = RingPresentation(
        fillFraction: nil,
        tone: .unavailable,
        primaryText: "—",
        secondaryText: nil
    )

    public static func from(snapshot: ProviderSnapshot?, account: ProviderAccount?) -> RingPresentation {
        guard let snapshot else { return .empty }

        switch snapshot.metric {
        case .metered(let percent, let remaining, let entitlement, _, let unlimited):
            if unlimited {
                return RingPresentation(
                    fillFraction: 1.0,
                    tone: .normal,
                    primaryText: "∞",
                    secondaryText: nil
                )
            }
            let clamped = min(100, max(0, percent))
            let secondary: String?
            if let remaining, let entitlement, entitlement > 0 {
                secondary = "\(Int(remaining.rounded())) / \(Int(entitlement.rounded()))"
            } else {
                secondary = nil
            }
            return RingPresentation(
                fillFraction: clamped / 100.0,
                tone: toneForPercent(clamped),
                primaryText: "\(Int(clamped.rounded()))%",
                secondaryText: secondary
            )

        case .rollingWindows(let windows):
            guard let tightest = windows.min(by: { $0.percentRemaining < $1.percentRemaining }) else {
                return .empty
            }
            let clamped = min(100, max(0, tightest.percentRemaining))
            let summary = windows
                .map { "\($0.label) \(Int($0.percentRemaining.rounded()))%" }
                .joined(separator: " · ")
            return RingPresentation(
                fillFraction: clamped / 100.0,
                tone: toneForPercent(clamped),
                primaryText: "\(Int(clamped.rounded()))%",
                secondaryText: summary.isEmpty ? nil : summary
            )

        case .balance(let amount, let currency, let granted, let toppedUp):
            let safeAmount = max(0, amount)
            let symbol = currencySymbol(for: currency)
            let formattedAmount = formatCurrencyAmount(safeAmount, symbol: symbol)

            let warning = account?.warningThreshold ?? 10.0
            let critical = account?.criticalThreshold ?? 5.0

            let fill: Double
            let tone: RingTone
            if let cap = account?.balanceReferenceCap, cap > 0 {
                let ratio = min(1.0, max(0.0, safeAmount / cap))
                fill = ratio
                if safeAmount <= critical || ratio < 0.10 {
                    tone = .critical
                } else if safeAmount <= warning || ratio < 0.20 {
                    tone = .warning
                } else {
                    tone = .normal
                }
            } else {
                fill = safeAmount > 0 ? 1.0 : 0.0
                if safeAmount <= critical {
                    tone = .critical
                } else if safeAmount <= warning {
                    tone = .warning
                } else {
                    tone = .normal
                }
            }

            var detailParts: [String] = []
            if let toppedUp, toppedUp > 0 {
                detailParts.append("\(symbol)\(formatCompactNumber(toppedUp))")
            }
            if let granted, granted > 0 {
                detailParts.append("+\(symbol)\(formatCompactNumber(granted))")
            }
            let secondary = detailParts.count == 2 ? detailParts.joined(separator: " ") : nil

            return RingPresentation(
                fillFraction: fill,
                tone: tone,
                primaryText: formattedAmount,
                secondaryText: secondary
            )
        }
    }

    public static func toneForPercent(_ percent: Double) -> RingTone {
        switch percent {
        case ..<10: return .critical
        case ..<20: return .warning
        default: return .normal
        }
    }

    public static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "CNY", "RMB", "JPY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        default: return code.isEmpty ? "$" : "\(code) "
        }
    }

    public static func formatCurrencyAmount(_ amount: Double, symbol: String) -> String {
        if amount >= 1000 {
            return "\(symbol)\(Int(amount.rounded()))"
        } else if amount >= 100 {
            return String(format: "%@%.0f", symbol, amount)
        } else {
            return String(format: "%@%.1f", symbol, amount)
        }
    }

    private static func formatCompactNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - Widget Slot Resolution

/// A single ring slot rendered in a Small (1-ring) or Medium (2-ring) widget.
public struct WidgetRingSlot: Equatable, Sendable {
    public let id: String
    public let kind: ProviderKind
    public let title: String
    /// Optional compact window badge rendered inside the ring (e.g. `"5h"`, `"7d"`).
    public let windowLabel: String?
    public let presentation: RingPresentation

    public init(
        id: String,
        kind: ProviderKind,
        title: String,
        windowLabel: String? = nil,
        presentation: RingPresentation
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.windowLabel = windowLabel
        self.presentation = presentation
    }
}

/// Pure resolver mapping widget configuration (1 or 2 selected account IDs) +
/// cached accounts/snapshots into rendered ring slots.
public enum WidgetSlotResolver {
    public static func resolveSingle(
        selectedAccountID: UUID?,
        accounts: [ProviderAccount],
        snapshots: [UUID: ProviderSnapshot]
    ) -> WidgetRingSlot? {
        let enabled = accounts.filter(\.isEnabled)
        let target: ProviderAccount?
        if let selectedAccountID {
            target = enabled.first(where: { $0.id == selectedAccountID }) ?? enabled.first
        } else {
            target = enabled.first
        }
        guard let account = target else { return nil }
        return makeSlot(for: account, snapshot: snapshots[account.id])
    }

    /// Resolves rings for the Dual-Ring widget, which always displays a SINGLE provider:
    /// - Uses `selectedAccountID` when set; otherwise prefers the first enabled provider
    ///   that has multiple rolling windows (e.g. GLM 5h + 7d), falling back to the first enabled provider.
    /// - Splits multi-window providers across two rings (`5h` + `7d`) and never mixes two different providers.
    public static func resolveDual(
        selectedAccountID: UUID?,
        accounts: [ProviderAccount],
        snapshots: [UUID: ProviderSnapshot]
    ) -> [WidgetRingSlot] {
        let enabled = accounts.filter(\.isEnabled)
        guard !enabled.isEmpty else { return [] }

        let target: ProviderAccount
        if let selectedAccountID, let match = enabled.first(where: { $0.id == selectedAccountID }) {
            target = match
        } else if let multiWindow = enabled.first(where: { acc in
            if case .rollingWindows(let windows) = snapshots[acc.id]?.metric {
                return windows.count >= 2
            }
            return acc.kind == .glm
        }) {
            target = multiWindow
        } else {
            target = enabled[0]
        }

        if let split = splitRollingWindows(for: target, snapshot: snapshots[target.id]) {
            return split
        }
        return [makeSlot(for: target, snapshot: snapshots[target.id])]
    }

    private static func makeSlot(for account: ProviderAccount, snapshot: ProviderSnapshot?) -> WidgetRingSlot {
        WidgetRingSlot(
            id: account.id.uuidString,
            kind: account.kind,
            title: account.resolvedTitle,
            windowLabel: nil,
            presentation: RingPresentation.from(snapshot: snapshot, account: account)
        )
    }

    private static func splitRollingWindows(
        for account: ProviderAccount,
        snapshot: ProviderSnapshot?
    ) -> [WidgetRingSlot]? {
        guard case .rollingWindows(let windows) = snapshot?.metric, windows.count >= 2 else {
            return nil
        }
        return windows.prefix(2).map { window in
            let clamped = min(100, max(0, window.percentRemaining))
            let presentation = RingPresentation(
                fillFraction: clamped / 100.0,
                tone: RingPresentation.toneForPercent(clamped),
                primaryText: "\(Int(clamped.rounded()))%",
                secondaryText: nil
            )
            return WidgetRingSlot(
                id: "\(account.id.uuidString)-\(window.id)",
                kind: account.kind,
                title: account.resolvedTitle,
                windowLabel: window.label,
                presentation: presentation
            )
        }
    }
}
