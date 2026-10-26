import SwiftUI

/// Draws the GitHub Copilot mark (Octicons `copilot-24`) as a SwiftUI shape.
///
/// The SVG path data is embedded directly, so no asset pipeline is involved and
/// the glyph scales cleanly at any size and can be tinted via `.fill(...)`.
/// Icon source: https://github.com/primer/octicons (MIT license).
public struct CopilotIconShape: Shape {
    static let pathData: [String] = [
        // Main body with visor holes.
        "M23.922 16.992c-.861 1.495-5.859 5.023-11.922 5.023-6.063 0-11.061-3.528-11.922-5.023A.641.641 0 0 1 0 16.736v-2.869a.841.841 0 0 1 .053-.22c.372-.935 1.347-2.292 2.605-2.656.167-.429.414-1.055.644-1.517a10.195 10.195 0 0 1-.052-1.086c0-1.331.282-2.499 1.132-3.368.397-.406.89-.717 1.474-.952 1.399-1.136 3.392-2.093 6.122-2.093 2.731 0 4.767.957 6.166 2.093.584.235 1.077.546 1.474.952.85.869 1.132 2.037 1.132 3.368 0 .368-.014.733-.052 1.086.23.462.477 1.088.644 1.517 1.258.364 2.233 1.721 2.605 2.656a.832.832 0 0 1 .053.22v2.869a.641.641 0 0 1-.078.256ZM12.172 11h-.344a4.323 4.323 0 0 1-.355.508C10.703 12.455 9.555 13 7.965 13c-1.725 0-2.989-.359-3.782-1.259a2.005 2.005 0 0 1-.085-.104L4 11.741v6.585c1.435.779 4.514 2.179 8 2.179 3.486 0 6.565-1.4 8-2.179v-6.585l-.098-.104s-.033.045-.085.104c-.793.9-2.057 1.259-3.782 1.259-1.59 0-2.738-.545-3.508-1.492a4.323 4.323 0 0 1-.355-.508h-.016.016Zm.641-2.935c.136 1.057.403 1.913.878 2.497.442.544 1.134.938 2.344.938 1.573 0 2.292-.337 2.657-.751.384-.435.558-1.15.558-2.361 0-1.14-.243-1.847-.705-2.319-.477-.488-1.319-.862-2.824-1.025-1.487-.161-2.192.138-2.533.529-.269.307-.437.808-.438 1.578v.021c0 .265.021.562.063.893Zm-1.626 0c.042-.331.063-.628.063-.894v-.02c-.001-.77-.169-1.271-.438-1.578-.341-.391-1.046-.69-2.533-.529-1.505.163-2.347.537-2.824 1.025-.462.472-.705 1.179-.705 2.319 0 1.211.175 1.926.558 2.361.365.414 1.084.751 2.657.751 1.21 0 1.902-.394 2.344-.938.475-.584.742-1.44.878-2.497Z",
        // The two "mouth" bars.
        "M14.5 14.25a1 1 0 0 1 1 1v2a1 1 0 0 1-2 0v-2a1 1 0 0 1 1-1Zm-5 0a1 1 0 0 1 1 1v2a1 1 0 0 1-2 0v-2a1 1 0 0 1 1-1Z",
    ]

    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        for data in Self.pathData {
            path.addPath(SVGPath.path(from: data))
        }
        // Uniformly scale the 24×24 viewBox into `rect`, centered.
        let scale = min(rect.width, rect.height) / 24
        let side = 24 * scale
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let transform = CGAffineTransform.identity
            .translatedBy(x: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
        return path.applying(transform)
    }
}

/// Minimal SVG path `d`-attribute parser producing a SwiftUI `Path`.
///
/// Supports the full command set M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z,
/// implicit command repetition, relative coordinates, and arc→cubic conversion
/// per the SVG specification (F.6.5 endpoint parameterization).
public enum SVGPath {
    public static func path(from d: String) -> Path {
        var parser = Parser(scalars: Array(d.unicodeScalars))
        return parser.parse()
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var previousCommand: Unicode.Scalar = " "

        init(scalars: [Unicode.Scalar]) {
            self.scalars = scalars
        }

        mutating func parse() -> Path {
            while let command = nextCommand() {
                switch command {
                case "M", "m": parseMove(relative: command == "m")
                case "L", "l": parseLine(relative: command == "l")
                case "H", "h": parseHorizontal(relative: command == "h")
                case "V", "v": parseVertical(relative: command == "v")
                case "C", "c": parseCubic(relative: command == "c")
                case "S", "s": parseSmoothCubic(relative: command == "s")
                case "Q", "q": parseQuad(relative: command == "q")
                case "T", "t": parseSmoothQuad(relative: command == "t")
                case "A", "a": parseArc(relative: command == "a")
                case "Z", "z": closeSubpath()
                default: break
                }
                previousCommand = command
            }
            return path
        }

        // MARK: - Command fetching (with implicit repeats)

        mutating func nextCommand() -> Unicode.Scalar? {
            skipSeparators()
            guard index < scalars.count else { return nil }
            let s = scalars[index]
            if isCommandLetter(s) {
                index += 1
                return s
            }
            guard isNumberStart(s) else { return nil }
            switch previousCommand {
            case "M": return "L"
            case "m": return "l"
            case "Z", "z": return nil
            case " ": return nil
            default: return previousCommand
            }
        }

        // MARK: - Commands

        mutating func parseMove(relative: Bool) {
            guard let p = readPoint() else { return }
            let target = relative ? current.offsetBy(p) : p
            path.move(to: target)
            current = target
            subpathStart = target
            lastCubicControl = nil
            lastQuadControl = nil
        }

        mutating func parseLine(relative: Bool) {
            guard let p = readPoint() else { return }
            let target = relative ? current.offsetBy(p) : p
            path.addLine(to: target)
            current = target
        }

        mutating func parseHorizontal(relative: Bool) {
            guard let x = readNumber() else { return }
            let target = CGPoint(x: relative ? current.x + x : x, y: current.y)
            path.addLine(to: target)
            current = target
        }

        mutating func parseVertical(relative: Bool) {
            guard let y = readNumber() else { return }
            let target = CGPoint(x: current.x, y: relative ? current.y + y : y)
            path.addLine(to: target)
            current = target
        }

        mutating func parseCubic(relative: Bool) {
            guard let c1Raw = readPoint(), let c2Raw = readPoint(), let endRaw = readPoint() else { return }
            // Per SVG spec, all coordinates of one command are relative to the
            // point at the start of that command.
            let c1 = relative ? current.offsetBy(c1Raw) : c1Raw
            let c2 = relative ? current.offsetBy(c2Raw) : c2Raw
            let end = relative ? current.offsetBy(endRaw) : endRaw
            path.addCurve(to: end, control1: c1, control2: c2)
            current = end
            lastCubicControl = c2
        }

        mutating func parseSmoothCubic(relative: Bool) {
            guard let c2Raw = readPoint(), let endRaw = readPoint() else { return }
            let c1: CGPoint
            if let last = lastCubicControl {
                c1 = CGPoint(x: 2 * current.x - last.x, y: 2 * current.y - last.y)
            } else {
                c1 = current
            }
            let c2 = relative ? current.offsetBy(c2Raw) : c2Raw
            let end = relative ? current.offsetBy(endRaw) : endRaw
            path.addCurve(to: end, control1: c1, control2: c2)
            current = end
            lastCubicControl = c2
        }

        mutating func parseQuad(relative: Bool) {
            guard let cRaw = readPoint(), let endRaw = readPoint() else { return }
            let c = relative ? current.offsetBy(cRaw) : cRaw
            let end = relative ? current.offsetBy(endRaw) : endRaw
            path.addQuadCurve(to: end, control: c)
            current = end
            lastQuadControl = c
        }

        mutating func parseSmoothQuad(relative: Bool) {
            guard let endRaw = readPoint() else { return }
            let c: CGPoint
            if let last = lastQuadControl {
                c = CGPoint(x: 2 * current.x - last.x, y: 2 * current.y - last.y)
            } else {
                c = current
            }
            let end = relative ? current.offsetBy(endRaw) : endRaw
            path.addQuadCurve(to: end, control: c)
            current = end
            lastQuadControl = c
        }

        mutating func parseArc(relative: Bool) {
            guard let rx = readNumber(), let ry = readNumber(), let rotation = readNumber(),
                  let largeFlag = readNumber(), let sweepFlag = readNumber(),
                  let endRaw = readPoint() else { return }
            let end = relative ? current.offsetBy(endRaw) : endRaw
            addArc(from: current, to: end,
                   rx: abs(rx), ry: abs(ry),
                   xAxisRotationDegrees: rotation,
                   largeArc: largeFlag != 0,
                   sweep: sweepFlag != 0)
            current = end
        }

        mutating func closeSubpath() {
            path.closeSubpath()
            current = subpathStart
            lastCubicControl = nil
            lastQuadControl = nil
        }

        // MARK: - Arc → cubic segments (SVG spec F.6.5)

        private mutating func addArc(from p0: CGPoint, to p1: CGPoint,
                            rx rxIn: Double, ry ryIn: Double,
                            xAxisRotationDegrees: Double,
                            largeArc: Bool, sweep: Bool) {
            guard rxIn > 0, ryIn > 0, p0 != p1 else {
                path.addLine(to: p1)
                return
            }
            var rx = rxIn
            var ry = ryIn
            let phi = xAxisRotationDegrees * .pi / 180
            let cosPhi = cos(phi)
            let sinPhi = sin(phi)

            let dx2 = (p0.x - p1.x) / 2
            let dy2 = (p0.y - p1.y) / 2
            let x1p = cosPhi * dx2 + sinPhi * dy2
            let y1p = -sinPhi * dx2 + cosPhi * dy2

            // Scale radii up if the arc is impossible (F.6.6).
            let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
            if lambda > 1 {
                let s = sqrt(lambda)
                rx *= s
                ry *= s
            }

            let sign: Double = (largeArc != sweep) ? 1 : -1
            let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
            let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
            let coefficient = sqrt(max(0, numerator / denominator)) * sign

            let cxp = coefficient * rx * y1p / ry
            let cyp = -coefficient * ry * x1p / rx
            let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
            let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

            let theta1 = atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
            var deltaTheta = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx) - theta1
            if !sweep && deltaTheta > 0 {
                deltaTheta -= 2 * .pi
            } else if sweep && deltaTheta < 0 {
                deltaTheta += 2 * .pi
            }

            // Emit at most ~90° per cubic segment for accuracy.
            let segmentCount = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
            let segmentDelta = deltaTheta / Double(segmentCount)
            let t = 4 / 3 * tan(segmentDelta / 4)

            var theta = theta1
            for _ in 0..<segmentCount {
                let nextTheta = theta + segmentDelta
                let start = Self.point(cx: cx, cy: cy, rx: rx, ry: ry, phi: phi, theta: theta)
                let end = Self.point(cx: cx, cy: cy, rx: rx, ry: ry, phi: phi, theta: nextTheta)
                let dStart = Self.derivative(rx: rx, ry: ry, phi: phi, theta: theta)
                let dEnd = Self.derivative(rx: rx, ry: ry, phi: phi, theta: nextTheta)
                let c1 = CGPoint(x: start.x + t * dStart.x, y: start.y + t * dStart.y)
                let c2 = CGPoint(x: end.x - t * dEnd.x, y: end.y - t * dEnd.y)
                path.addCurve(to: end, control1: c1, control2: c2)
                theta = nextTheta
            }
        }

        private static func point(cx: Double, cy: Double, rx: Double, ry: Double,
                                  phi: Double, theta: Double) -> CGPoint {
            let px = rx * cos(theta)
            let py = ry * sin(theta)
            return CGPoint(x: cx + cos(phi) * px - sin(phi) * py,
                           y: cy + sin(phi) * px + cos(phi) * py)
        }

        private static func derivative(rx: Double, ry: Double, phi: Double, theta: Double) -> CGPoint {
            let dx = -rx * sin(theta)
            let dy = ry * cos(theta)
            return CGPoint(x: cos(phi) * dx - sin(phi) * dy,
                           y: sin(phi) * dx + cos(phi) * dy)
        }

        // MARK: - Lexer

        mutating func readPoint() -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return CGPoint(x: x, y: y)
        }

        mutating func readNumber() -> Double? {
            skipSeparators()
            guard index < scalars.count else { return nil }
            let start = index
            if scalars[index] == "+" || scalars[index] == "-" {
                index += 1
            }
            var seenDigit = false
            var seenDot = false
            while index < scalars.count {
                let s = scalars[index]
                if isDigit(s) {
                    seenDigit = true
                    index += 1
                } else if s == "." && !seenDot {
                    seenDot = true
                    index += 1
                } else if (s == "e" || s == "E") && seenDigit {
                    var lookahead = index + 1
                    if lookahead < scalars.count,
                       scalars[lookahead] == "+" || scalars[lookahead] == "-" {
                        lookahead += 1
                    }
                    guard lookahead < scalars.count, isDigit(scalars[lookahead]) else { break }
                    index = lookahead
                    while index < scalars.count, isDigit(scalars[index]) {
                        index += 1
                    }
                    break
                } else {
                    break
                }
            }
            guard seenDigit, index > start else { return nil }
            let text = String(String.UnicodeScalarView(scalars[start..<index]))
            return Double(text)
        }

        mutating func skipSeparators() {
            while index < scalars.count {
                let s = scalars[index]
                if s == " " || s == "," || s == "\n" || s == "\t" || s == "\r" {
                    index += 1
                } else {
                    break
                }
            }
        }

        func isCommandLetter(_ s: Unicode.Scalar) -> Bool {
            let v = s.value
            return (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
        }

        func isDigit(_ s: Unicode.Scalar) -> Bool {
            s.value >= 48 && s.value <= 57
        }

        func isNumberStart(_ s: Unicode.Scalar) -> Bool {
            isDigit(s) || s == "+" || s == "-" || s == "."
        }
    }
}

private extension CGPoint {
    func offsetBy(_ delta: CGPoint) -> CGPoint {
        CGPoint(x: x + delta.x, y: y + delta.y)
    }
}
