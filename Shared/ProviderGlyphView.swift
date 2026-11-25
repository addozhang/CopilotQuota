import SwiftUI

/// Official DeepSeek whale mark (`@lobehub/icons-static-svg`, viewBox 0 0 24 24, even-odd fill).
public struct DeepSeekIconShape: Shape {
    private static let pathData =
        "M23.748 4.482c-.254-.124-.364.113-.512.234-.051.039-.094.09-.137.136-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.156-.708-.311-.955-.65-.172-.241-.219-.51-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.093.172.187.129.323-.082.28-.18.552-.266.833-.055.179-.137.217-.329.14a5.526 5.526 0 01-1.736-1.18c-.857-.828-1.631-1.742-2.597-2.458a11.365 11.365 0 00-.689-.471c-.985-.957.13-1.743.388-1.836.27-.098.093-.432-.779-.428-.872.004-1.67.295-2.687.684a3.055 3.055 0 01-.465.137 9.597 9.597 0 00-2.883-.102c-1.885.21-3.39 1.102-4.497 2.623C.082 8.606-.231 10.684.152 12.85c.403 2.284 1.569 4.175 3.36 5.653 1.858 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.133-.284 4.994-1.86.47.234.962.327 1.78.397.63.059 1.236-.03 1.705-.128.735-.156.684-.837.419-.961-2.155-1.004-1.682-.595-2.113-.926 1.096-1.296 2.746-2.642 3.392-7.003.05-.347.007-.565 0-.845-.004-.17.035-.237.23-.256a4.173 4.173 0 001.545-.475c1.396-.763 1.96-2.015 2.093-3.517.02-.23-.004-.467-.247-.588zM11.581 18c-2.089-1.642-3.102-2.183-3.52-2.16-.392.024-.321.471-.235.763.09.288.207.486.371.739.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.167-1.361-.802-2.5-1.86-3.301-3.307-.774-1.393-1.224-2.887-1.298-4.482-.02-.386.093-.522.477-.592a4.696 4.696 0 011.529-.039c2.132.312 3.946 1.265 5.468 2.774.868.86 1.525 1.887 2.202 2.891.72 1.066 1.494 2.082 2.48 2.914.348.292.625.514.891.677-.802.09-2.14.11-3.054-.614zm1-6.44a.306.306 0 01.415-.287.302.302 0 01.2.288.306.306 0 01-.31.307.303.303 0 01-.304-.308zm3.11 1.596c-.2.081-.399.151-.59.16a1.245 1.245 0 01-.798-.254c-.274-.23-.47-.358-.552-.758a1.73 1.73 0 01.016-.588c.07-.327-.008-.537-.239-.727-.187-.156-.426-.199-.688-.199a.559.559 0 01-.254-.078c-.11-.054-.2-.19-.114-.358.028-.054.16-.186.192-.21.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.391.451.462.576.685.914.176.265.336.537.445.848.067.195-.019.354-.25.452z"

    public init() {}

    public func path(in rect: CGRect) -> Path {
        scaleViewBox24(SVGPath.path(from: Self.pathData), into: rect)
    }
}

/// GLM / Zhipu / Z.ai bold geometric "Z" emblem on a 24×24 viewBox.
public struct GLMIconShape: Shape {
    private static let pathData =
        "M4.5 5.2h15c.6 0 1 .4 1 1v1.4c0 .3-.1.6-.3.8L10.4 18.8H19.5c.6 0 1 .4 1 1v1.2c0 .6-.4 1-1 1h-15c-.6 0-1-.4-1-1v-1.4c0-.3.1-.6.3-.8L13.6 8.4H4.5c-.6 0-1-.4-1-1V6.2c0-.6.4-1 1-1Z"

    public init() {}

    public func path(in rect: CGRect) -> Path {
        scaleViewBox24(SVGPath.path(from: Self.pathData), into: rect)
    }
}

/// Official OpenRouter emblem (`@lobehub/icons-static-svg`, viewBox 0 0 24 24, even-odd fill).
public struct OpenRouterIconShape: Shape {
    private static let pathData =
        "M18.654 3.87a5.087 5.087 0 110 10.174L23.7 19.09c.64.641.187 1.737-.72 1.737H8.48a8.479 8.479 0 010-16.958h10.175zM8.479 7.26a5.087 5.087 0 100 10.176 5.087 5.087 0 000-10.175z"

    public init() {}

    public func path(in rect: CGRect) -> Path {
        scaleViewBox24(SVGPath.path(from: Self.pathData), into: rect)
    }
}

/// Official Kimi emblem (`@lobehub/icons-static-svg`, viewBox 0 0 24 24, even-odd fill).
public struct KimiIconShape: Shape {
    private static let pathData: [String] = [
        "M21.846 0a1.923 1.923 0 110 3.846H20.15a.226.226 0 01-.227-.226V1.923C19.923.861 20.784 0 21.846 0z",
        "M11.065 11.199l7.257-7.2c.137-.136.06-.41-.116-.41H14.3a.164.164 0 00-.117.051l-7.82 7.756c-.122.12-.302.013-.302-.179V3.82c0-.127-.083-.23-.185-.23H3.186c-.103 0-.186.103-.186.23V19.77c0 .128.083.23.186.23h2.69c.103 0 .186-.102.186-.23v-3.25c0-.069.025-.135.069-.178l2.424-2.406a.158.158 0 01.205-.023l6.484 4.772a7.677 7.677 0 003.453 1.283c.108.012.2-.095.2-.23v-3.06c0-.117-.07-.212-.164-.227a5.028 5.028 0 01-2.027-.807l-5.613-4.064c-.117-.078-.132-.279-.028-.381z",
    ]

    public init() {}

    public func path(in rect: CGRect) -> Path {
        var combined = Path()
        for data in Self.pathData {
            combined.addPath(SVGPath.path(from: data))
        }
        return scaleViewBox24(combined, into: rect)
    }
}

/// Official MiniMax emblem (`@lobehub/icons-static-svg`, viewBox 0 0 24 24, even-odd fill).
public struct MiniMaxIconShape: Shape {
    private static let pathData =
        "M16.278 2c1.156 0 2.093.927 2.093 2.07v12.501a.74.74 0 00.744.709.74.74 0 00.743-.709V9.099a2.06 2.06 0 012.071-2.049A2.06 2.06 0 0124 9.1v6.561a.649.649 0 01-.652.645.649.649 0 01-.653-.645V9.1a.762.762 0 00-.766-.758.762.762 0 00-.766.758v7.472a2.037 2.037 0 01-2.048 2.026 2.037 2.037 0 01-2.048-2.026v-12.5a.785.785 0 00-.788-.753.785.785 0 00-.789.752l-.001 15.904A2.037 2.037 0 0113.441 22a2.037 2.037 0 01-2.048-2.026V18.04c0-.356.292-.645.652-.645.36 0 .652.289.652.645v1.934c0 .263.142.506.372.638.23.131.514.131.744 0a.734.734 0 00.372-.638V4.07c0-1.143.937-2.07 2.093-2.07zm-5.674 0c1.156 0 2.093.927 2.093 2.07v11.523a.648.648 0 01-.652.645.648.648 0 01-.652-.645V4.07a.785.785 0 00-.789-.78.785.785 0 00-.789.78v14.013a2.06 2.06 0 01-2.07 2.048 2.06 2.06 0 01-2.071-2.048V9.1a.762.762 0 00-.766-.758.762.762 0 00-.766.758v3.8a2.06 2.06 0 01-2.071 2.049A2.06 2.06 0 010 12.9v-1.378c0-.357.292-.646.652-.646.36 0 .653.29.653.646V12.9c0 .418.343.757.766.757s.766-.339.766-.757V9.099a2.06 2.06 0 012.07-2.048 2.06 2.06 0 012.071 2.048v8.984c0 .419.343.758.767.758.423 0 .766-.339.766-.758V4.07c0-1.143.937-2.07 2.093-2.07z"

    public init() {}

    public func path(in rect: CGRect) -> Path {
        scaleViewBox24(SVGPath.path(from: Self.pathData), into: rect)
    }
}

private func scaleViewBox24(_ path: Path, into rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 24
    let side = 24 * scale
    let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    let transform = CGAffineTransform.identity
        .translatedBy(x: origin.x, y: origin.y)
        .scaledBy(x: scale, y: scale)
    return path.applying(transform)
}

/// Renders the monochrome brand glyph for any `ProviderKind` inside a battery ring or header.
public struct ProviderGlyphView: View {
    public let kind: ProviderKind
    public let size: CGFloat
    public let dimmed: Bool

    public init(kind: ProviderKind, size: CGFloat, dimmed: Bool = false) {
        self.kind = kind
        self.size = size
        self.dimmed = dimmed
    }

    public var body: some View {
        let opacity = dimmed ? 0.30 : 0.92
        let tint = Color.primary.opacity(opacity)
        Group {
            switch kind {
            case .copilot:
                CopilotIconShape()
                    .fill(tint)
            case .deepseek:
                DeepSeekIconShape()
                    .fill(tint, style: FillStyle(eoFill: true))
            case .glm:
                GLMIconShape()
                    .fill(tint)
            case .openrouter:
                OpenRouterIconShape()
                    .fill(tint, style: FillStyle(eoFill: true))
            case .kimi:
                KimiIconShape()
                    .fill(tint, style: FillStyle(eoFill: true))
            case .minimax:
                MiniMaxIconShape()
                    .fill(tint, style: FillStyle(eoFill: true))
            }
        }
        .frame(width: size, height: size)
    }
}
