// 生成 App 图标（1024×1024）：复用 Shared/CopilotIconShape.swift 的 SVG 解析器。
// 用法:  swiftc -O Shared/CopilotIconShape.swift tools/make_icon.swift -o make_icon && ./make_icon AppIcon.png

import Foundation
import CoreGraphics
import ImageIO
import SwiftUI

// Renders the macOS app icon: Big-Sur-style rounded square, dark purple
// gradient, battery-widget-style ring at 83%, Copilot glyph in the middle.

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

let size = 1024
guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

// MARK: background squircle

let inset: CGFloat = 100
let side: CGFloat = CGFloat(size) - 2 * inset
let bgRect = CGRect(x: inset, y: inset, width: side, height: side)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 184, cornerHeight: 184, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

let colors = [
    CGColor(red: 0.196, green: 0.125, blue: 0.318, alpha: 1), // top    #32205{1}
    CGColor(red: 0.102, green: 0.059, blue: 0.173, alpha: 1), // bottom #1A0F2C
] as CFArray
if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 100),
                           options: [])
}

// MARK: ring (battery-widget style)

let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 208
let lineWidth: CGFloat = 56
ctx.setLineCap(.round)

// track
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.15))
ctx.setLineWidth(lineWidth)
ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2))
ctx.strokePath()

// progress arc: 83% from 12 o'clock, clockwise (percent purely decorative)
let percent = 0.83
ctx.setStrokeColor(CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1))
ctx.setLineWidth(lineWidth)
ctx.addArc(center: center, radius: radius,
           startAngle: .pi / 2,
           endAngle: .pi / 2 - 2 * .pi * CGFloat(percent),
           clockwise: true)
ctx.strokePath()

// MARK: Copilot glyph (reuses the widget's SVG parser)

var iconPath = Path()
for data in CopilotIconShape.pathData {
    iconPath.addPath(SVGPath.path(from: data))
}
let iconSide: CGFloat = 200
let scale = iconSide / 24
// SVG space is y-down, CoreGraphics is y-up: flip vertically while fitting.
var transform = CGAffineTransform.identity
    .translatedBy(x: center.x - iconSide / 2, y: center.y + iconSide / 2)
    .scaledBy(x: scale, y: -scale)
if let cg = iconPath.cgPath.copy(using: &transform) {
    ctx.addPath(cg)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
}

// MARK: write PNG

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: outPath) as CFURL,
        "public.png" as CFString, 1, nil) else {
    fatalError("write failed")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fatalError("finalize failed")
}
print("wrote \(outPath)")
