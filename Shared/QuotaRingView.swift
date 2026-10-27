import SwiftUI

/// Ring color, mimicking the system battery widget
/// (green normally, orange when low, red when critical).
public func quotaRingColor(percentRemaining: Double) -> Color {
    switch percentRemaining {
    case ..<10:
        return Color(red: 1.00, green: 0.27, blue: 0.23)
    case ..<20:
        return Color(red: 1.00, green: 0.62, blue: 0.04)
    default:
        return Color(red: 0.20, green: 0.78, blue: 0.35)
    }
}

/// A circular progress ring with the Copilot glyph in the middle —
/// the widget's take on the system battery widget.
public struct QuotaRingView: View {
    public var percent: Double?
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var iconSize: CGFloat

    /// `lineWidth` / `iconSize` default to proportions of `size`, so every
    /// usage scales as one unit — pixel-measured from the system battery
    /// widget: stroke ≈ 9.5% and icon glyph ≈ 36.5% of the ring diameter.
    public init(percent: Double?,
                size: CGFloat = 64,
                lineWidth: CGFloat? = nil,
                iconSize: CGFloat? = nil) {
        self.percent = percent
        self.size = size
        self.lineWidth = lineWidth ?? size * 0.095
        self.iconSize = iconSize ?? size * 0.52
    }

    public var body: some View {
        let strokeColor = percent.map { quotaRingColor(percentRemaining: $0) }
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.14),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.015, min(1, percent / 100))))
                    .stroke(strokeColor ?? .green,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            CopilotIconShape()
                .fill(Color.primary.opacity(percent == nil ? 0.30 : 0.92))
                .frame(width: iconSize, height: iconSize)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.35), value: percent)
    }
}
