import SwiftUI

/// Ring color, mimicking the system battery widget
/// (green normally, orange when low, red when critical).
public func quotaRingColor(percentRemaining: Double) -> Color {
    RingPresentation.toneForPercent(percentRemaining).color
}

/// A circular progress ring with either the provider brand glyph or a compact
/// window label (e.g. `5h`, `7d`) in the middle.
public struct QuotaRingView: View {
    public var fillFraction: Double?
    public var tone: RingTone
    public var kind: ProviderKind
    public var centerLabel: String?
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var iconSize: CGFloat

    /// `lineWidth` / `iconSize` default to proportions of `size`, so every
    /// usage scales as one unit — pixel-measured from the system battery
    /// widget: stroke ≈ 9.5% of the ring diameter.
    public init(
        presentation: RingPresentation,
        kind: ProviderKind = .copilot,
        centerLabel: String? = nil,
        size: CGFloat = 64,
        lineWidth: CGFloat? = nil,
        iconSize: CGFloat? = nil
    ) {
        self.fillFraction = presentation.fillFraction
        self.tone = presentation.tone
        self.kind = kind
        self.centerLabel = centerLabel
        self.size = size
        self.lineWidth = lineWidth ?? size * 0.095
        self.iconSize = iconSize ?? size * 0.52
    }

    /// Legacy convenience initializer for simple percent rings.
    public init(
        percent: Double?,
        kind: ProviderKind = .copilot,
        size: CGFloat = 64,
        lineWidth: CGFloat? = nil,
        iconSize: CGFloat? = nil
    ) {
        self.fillFraction = percent.map { min(1, max(0, $0 / 100)) }
        self.tone = percent.map { RingPresentation.toneForPercent($0) } ?? .unavailable
        self.kind = kind
        self.centerLabel = nil
        self.size = size
        self.lineWidth = lineWidth ?? size * 0.095
        self.iconSize = iconSize ?? size * 0.52
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.14),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if let fillFraction {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.015, min(1, fillFraction))))
                    .stroke(tone.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if let centerLabel, !centerLabel.isEmpty {
                Text(centerLabel)
                    .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.primary.opacity(fillFraction == nil ? 0.30 : 0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                ProviderGlyphView(kind: kind, size: iconSize, dimmed: fillFraction == nil)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.35), value: fillFraction)
    }
}
