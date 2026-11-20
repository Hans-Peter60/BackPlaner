#!/usr/bin/env swift
//
// cookplanner-icon.swift
//
// Renders CookPlanner's app icon (1024 × 1024, no alpha) in the family
// look of BakePlanner's: a warm orange glow fading to black, the hero
// object in the middle — a frying pan — and a badge at the lower right,
// here a stopwatch, where BakePlanner carries its calendar.
//
//   swift scripts/cookplanner-icon.swift [target.png]
//
// Writes CookPlanner/Assets.xcassets/AppIcon.appiconset/icon.png by
// default. Needs only macOS.
//

import AppKit
import Foundation

let size = 1024
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let target = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("CookPlanner/Assets.xcassets/AppIcon.appiconset/icon.png")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fail("Cannot create a drawing context") }
context.interpolationQuality = .high
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let s = CGFloat(size)

// MARK: Background — the glow

context.setFillColor(color(0, 0, 0))
context.fill(CGRect(x: 0, y: 0, width: s, height: s))
context.drawRadialGradient(
    gradient([(0.0, color(1.00, 0.58, 0.14)), (0.30, color(0.95, 0.42, 0.06)),
              (0.62, color(0.60, 0.19, 0.01)), (0.86, color(0.12, 0.03, 0.0)), (1.0, color(0, 0, 0))]),
    startCenter: CGPoint(x: s * 0.50, y: s * 0.52), startRadius: 0,
    endCenter: CGPoint(x: s * 0.50, y: s * 0.52), endRadius: s * 0.66,
    options: [])

// MARK: The pan

let panCenter = CGPoint(x: s * 0.41, y: s * 0.52)
let panRadius = s * 0.265

// Soft shadow under the pan.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.06, color: color(0, 0, 0, 0.55))
context.setFillColor(color(0.11, 0.11, 0.12))
context.fillEllipse(in: CGRect(x: panCenter.x - panRadius, y: panCenter.y - panRadius,
                               width: panRadius * 2, height: panRadius * 2))
context.restoreGState()

// Handle: a rounded bar from the rim to the upper right, drawn before the
// rim so the rim covers its root.
context.saveGState()
context.translateBy(x: panCenter.x, y: panCenter.y)
context.rotate(by: .pi / 7)
let handleLength = s * 0.31, handleWidth = s * 0.08
let handle = CGPath(roundedRect: CGRect(x: panRadius - s * 0.03, y: -handleWidth / 2,
                                        width: handleLength, height: handleWidth),
                    cornerWidth: handleWidth / 2, cornerHeight: handleWidth / 2, transform: nil)
context.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.03, color: color(0, 0, 0, 0.5))
context.addPath(handle)
context.setFillColor(color(0.16, 0.16, 0.17))
context.fillPath()
context.setShadow(offset: .zero, blur: 0, color: nil)
// A light edge along the top of the handle.
context.addPath(handle)
context.clip()
context.drawLinearGradient(gradient([(0, color(1, 1, 1, 0.22)), (0.5, color(1, 1, 1, 0.0)), (1, color(0, 0, 0, 0.25))]),
                           start: CGPoint(x: 0, y: handleWidth / 2), end: CGPoint(x: 0, y: -handleWidth / 2), options: [])
// The hole at the end of the handle.
context.setFillColor(color(0.05, 0.05, 0.05))
let holeRadius = s * 0.016
context.fillEllipse(in: CGRect(x: panRadius - s * 0.03 + handleLength - s * 0.055 - holeRadius,
                               y: -holeRadius, width: holeRadius * 2, height: holeRadius * 2))
context.restoreGState()

// Rim: a ring with a highlight running around the upper left.
let rimWidth = s * 0.055
context.saveGState()
context.addEllipse(in: CGRect(x: panCenter.x - panRadius, y: panCenter.y - panRadius, width: panRadius * 2, height: panRadius * 2))
context.addEllipse(in: CGRect(x: panCenter.x - panRadius + rimWidth, y: panCenter.y - panRadius + rimWidth,
                              width: (panRadius - rimWidth) * 2, height: (panRadius - rimWidth) * 2))
context.clip(using: .evenOdd)
context.drawLinearGradient(gradient([(0, color(0.62, 0.62, 0.64)), (0.45, color(0.30, 0.30, 0.32)), (1, color(0.14, 0.14, 0.15))]),
                           start: CGPoint(x: panCenter.x - panRadius, y: panCenter.y + panRadius),
                           end: CGPoint(x: panCenter.x + panRadius, y: panCenter.y - panRadius), options: [])
context.restoreGState()

// Cooking surface: dark, with a warm sheen from the glow and a specular.
let innerRadius = panRadius - rimWidth
context.saveGState()
context.addEllipse(in: CGRect(x: panCenter.x - innerRadius, y: panCenter.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
context.clip()
context.drawRadialGradient(gradient([(0, color(0.22, 0.20, 0.19)), (0.7, color(0.12, 0.11, 0.11)), (1, color(0.06, 0.06, 0.06))]),
                           startCenter: CGPoint(x: panCenter.x - innerRadius * 0.25, y: panCenter.y + innerRadius * 0.25), startRadius: 0,
                           endCenter: panCenter, endRadius: innerRadius, options: [])
// Specular highlight, upper left.
context.drawRadialGradient(gradient([(0, color(1, 1, 1, 0.20)), (1, color(1, 1, 1, 0))]),
                           startCenter: CGPoint(x: panCenter.x - innerRadius * 0.45, y: panCenter.y + innerRadius * 0.45), startRadius: 0,
                           endCenter: CGPoint(x: panCenter.x - innerRadius * 0.45, y: panCenter.y + innerRadius * 0.45), endRadius: innerRadius * 0.7,
                           options: [])
// Depth: the rim casts a shade onto the surface along its upper edge.
context.drawRadialGradient(gradient([(0, color(0, 0, 0, 0)), (0.80, color(0, 0, 0, 0)), (1, color(0, 0, 0, 0.55))]),
                           startCenter: CGPoint(x: panCenter.x, y: panCenter.y - innerRadius * 0.12), startRadius: 0,
                           endCenter: CGPoint(x: panCenter.x, y: panCenter.y - innerRadius * 0.12), endRadius: innerRadius * 1.12,
                           options: [])
// Warm reflection of the glow, lower right.
context.drawRadialGradient(gradient([(0, color(1.0, 0.45, 0.10, 0.28)), (1, color(1.0, 0.45, 0.10, 0))]),
                           startCenter: CGPoint(x: panCenter.x + innerRadius * 0.4, y: panCenter.y - innerRadius * 0.4), startRadius: 0,
                           endCenter: CGPoint(x: panCenter.x + innerRadius * 0.4, y: panCenter.y - innerRadius * 0.4), endRadius: innerRadius * 0.8,
                           options: [])
context.restoreGState()

// MARK: The badge — a stopwatch, where BakePlanner carries its calendar

let badgeCenter = CGPoint(x: s * 0.70, y: s * 0.30)
let badgeSize = s * 0.31
let badgeRect = CGRect(x: badgeCenter.x - badgeSize / 2, y: badgeCenter.y - badgeSize / 2, width: badgeSize, height: badgeSize)
let cream = color(0.99, 0.94, 0.86)
let brandOrange = color(0.93, 0.36, 0.08)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: color(0, 0, 0, 0.5))
context.addPath(CGPath(roundedRect: badgeRect, cornerWidth: badgeSize * 0.24, cornerHeight: badgeSize * 0.24, transform: nil))
context.setFillColor(cream)
context.fillPath()
context.restoreGState()

// The stopwatch: crown and button on top, orange dial, white hands.
let dialRadius = badgeSize * 0.30
let dialCenter = CGPoint(x: badgeCenter.x, y: badgeCenter.y - badgeSize * 0.03)
context.setFillColor(brandOrange)
// Crown (the stem) and the side button.
context.fill(CGRect(x: dialCenter.x - badgeSize * 0.045, y: dialCenter.y + dialRadius - badgeSize * 0.01,
                    width: badgeSize * 0.09, height: badgeSize * 0.09))
context.fill(CGRect(x: dialCenter.x - badgeSize * 0.09, y: dialCenter.y + dialRadius + badgeSize * 0.06,
                    width: badgeSize * 0.18, height: badgeSize * 0.05))
context.saveGState()
context.translateBy(x: dialCenter.x, y: dialCenter.y)
context.rotate(by: -.pi / 4)
context.fill(CGRect(x: -badgeSize * 0.03, y: dialRadius - badgeSize * 0.005, width: badgeSize * 0.06, height: badgeSize * 0.08))
context.restoreGState()
// Dial.
context.fillEllipse(in: CGRect(x: dialCenter.x - dialRadius, y: dialCenter.y - dialRadius, width: dialRadius * 2, height: dialRadius * 2))
// Tick marks at the quarters.
context.setStrokeColor(color(1, 1, 1, 0.85))
context.setLineCap(.round)
context.setLineWidth(badgeSize * 0.02)
for quarter in 0..<4 {
    let angle = CGFloat(quarter) * .pi / 2
    let outer = CGPoint(x: dialCenter.x + cos(angle) * dialRadius * 0.82, y: dialCenter.y + sin(angle) * dialRadius * 0.82)
    let inner = CGPoint(x: dialCenter.x + cos(angle) * dialRadius * 0.66, y: dialCenter.y + sin(angle) * dialRadius * 0.66)
    context.move(to: outer)
    context.addLine(to: inner)
    context.strokePath()
}
// Hands: minute hand up, the other a little past the hour — the clock is
// running.
context.setStrokeColor(color(1, 1, 1))
context.setLineWidth(badgeSize * 0.035)
context.move(to: dialCenter)
context.addLine(to: CGPoint(x: dialCenter.x, y: dialCenter.y + dialRadius * 0.62))
context.strokePath()
context.move(to: dialCenter)
context.addLine(to: CGPoint(x: dialCenter.x + dialRadius * 0.46, y: dialCenter.y - dialRadius * 0.22))
context.strokePath()
context.setFillColor(color(1, 1, 1))
context.fillEllipse(in: CGRect(x: dialCenter.x - badgeSize * 0.03, y: dialCenter.y - badgeSize * 0.03,
                               width: badgeSize * 0.06, height: badgeSize * 0.06))

// MARK: Write

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)
else { fail("Cannot write \(target.path)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("Cannot write \(target.path)") }
print("Wrote \(target.path)")
