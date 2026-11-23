#!/usr/bin/env swift
//
// cookplanner-icon.swift
//
// Renders CookPlanner's app icon (1024 × 1024, no alpha) in the family
// look of BakePlanner's: a warm orange glow fading to black, a lit hero
// object in the middle — a cast-iron pan with a fried egg — and a tilted,
// glossy badge at the lower right, here a stopwatch where BakePlanner
// carries its calendar. Light comes from the upper left; every shape has
// its shadow, so the icon reads as three-dimensional like the bread.
//
//   swift scripts/cookplanner/cookplanner-icon.swift [target.png]
//
// Writes CookPlanner/CookPlanner/Assets.xcassets/AppIcon.appiconset/icon.png by
// default. Needs only macOS.
//

import AppKit
import Foundation

let size = 1024
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let target = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("CookPlanner/CookPlanner/Assets.xcassets/AppIcon.appiconset/icon.png")

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
    // Bright around the motif, black at the corners, as BakePlanner's glow.
    gradient([(0.0, color(1.00, 0.68, 0.24)), (0.30, color(0.99, 0.48, 0.07)),
              (0.52, color(0.72, 0.22, 0.01)), (0.72, color(0.16, 0.035, 0.0)), (1.0, color(0, 0, 0))]),
    startCenter: CGPoint(x: s * 0.48, y: s * 0.54), startRadius: 0,
    endCenter: CGPoint(x: s * 0.48, y: s * 0.54), endRadius: s * 0.66,
    options: [.drawsAfterEndLocation])

// MARK: The pan

let center = CGPoint(x: s * 0.42, y: s * 0.56)
let radius = s * 0.265

// The handle, behind the pan, towards the upper right: a rounded bar lit
// across its width like a cylinder.
context.saveGState()
context.translateBy(x: center.x, y: center.y)
context.rotate(by: .pi / 6.2)
let handle = CGRect(x: radius * 0.80, y: -s * 0.034, width: s * 0.30, height: s * 0.068)
context.setShadow(offset: CGSize(width: s * 0.012, height: -s * 0.022), blur: s * 0.035, color: color(0, 0, 0, 0.55))
context.addPath(CGPath(roundedRect: handle, cornerWidth: s * 0.034, cornerHeight: s * 0.034, transform: nil))
context.setFillColor(color(0.1, 0.1, 0.11))
context.fillPath()
context.setShadow(offset: .zero, blur: 0, color: nil)
context.addPath(CGPath(roundedRect: handle, cornerWidth: s * 0.034, cornerHeight: s * 0.034, transform: nil))
context.clip()
context.drawLinearGradient(
    gradient([(0.0, color(0.05, 0.05, 0.06)), (0.45, color(0.42, 0.42, 0.45)), (0.62, color(0.22, 0.22, 0.24)), (1.0, color(0.04, 0.04, 0.05))]),
    start: CGPoint(x: 0, y: handle.minY), end: CGPoint(x: 0, y: handle.maxY), options: [])
context.resetClip()
context.addEllipse(in: CGRect(x: handle.maxX - s * 0.062, y: -s * 0.014, width: s * 0.028, height: s * 0.028))
context.setFillColor(color(0.45, 0.16, 0.02))
context.fillPath()
context.restoreGState()

// The body: a shadow on the glow, then the rim lit from the upper left.
let outer = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
context.saveGState()
context.setShadow(offset: CGSize(width: s * 0.018, height: -s * 0.032), blur: s * 0.06, color: color(0, 0, 0, 0.7))
context.addEllipse(in: outer)
context.setFillColor(color(0.08, 0.08, 0.09))
context.fillPath()
context.restoreGState()

func disc(_ r: CGFloat, _ stops: [(CGFloat, CGColor)], from: CGPoint, to: CGPoint) {
    context.saveGState()
    context.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    context.clip()
    context.drawLinearGradient(gradient(stops), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}
let upperLeft = CGPoint(x: center.x - radius, y: center.y + radius)
let lowerRight = CGPoint(x: center.x + radius, y: center.y - radius)
// Outer rim: bright where the light falls, dark where it does not.
disc(radius, [(0.0, color(0.62, 0.62, 0.66)), (0.5, color(0.24, 0.24, 0.26)), (1.0, color(0.05, 0.05, 0.06))],
     from: upperLeft, to: lowerRight)
// The inner wall slopes the other way: dark at the upper left, catching light at the lower right.
disc(radius * 0.90, [(0.0, color(0.04, 0.04, 0.05)), (0.6, color(0.14, 0.14, 0.15)), (1.0, color(0.40, 0.36, 0.34))],
     from: upperLeft, to: lowerRight)
// The floor: deep charcoal, warmed by the glow from below.
context.saveGState()
let floorRadius = radius * 0.80
context.addEllipse(in: CGRect(x: center.x - floorRadius, y: center.y - floorRadius, width: floorRadius * 2, height: floorRadius * 2))
context.clip()
context.drawRadialGradient(
    gradient([(0.0, color(0.20, 0.19, 0.19)), (0.75, color(0.09, 0.09, 0.10)), (1.0, color(0.05, 0.05, 0.05))]),
    startCenter: CGPoint(x: center.x - floorRadius * 0.25, y: center.y + floorRadius * 0.25), startRadius: 0,
    endCenter: center, endRadius: floorRadius, options: [])
context.drawRadialGradient(
    gradient([(0.0, color(0.85, 0.35, 0.05, 0.28)), (1.0, color(0.85, 0.35, 0.05, 0))]),
    startCenter: CGPoint(x: center.x + floorRadius * 0.45, y: center.y - floorRadius * 0.5), startRadius: 0,
    endCenter: CGPoint(x: center.x + floorRadius * 0.45, y: center.y - floorRadius * 0.5), endRadius: floorRadius * 0.8, options: [])
context.restoreGState()
// A specular arc on the rim at the upper left.
context.saveGState()
context.setLineCap(.round)
context.setLineWidth(s * 0.014)
context.setStrokeColor(color(1, 1, 1, 0.55))
context.addArc(center: center, radius: radius * 0.955, startAngle: .pi * 0.62, endAngle: .pi * 0.92, clockwise: false)
context.strokePath()
context.setLineWidth(s * 0.006)
context.setStrokeColor(color(1, 1, 1, 0.35))
context.addArc(center: center, radius: radius * 0.955, startAngle: .pi * 0.40, endAngle: .pi * 0.58, clockwise: false)
context.strokePath()
context.restoreGState()

// MARK: The fried egg

let eggCenter = CGPoint(x: center.x + s * 0.01, y: center.y - s * 0.005)
let white = CGMutablePath()
// A soft, uneven white: a ring of bulges around the yolk.
let lobes: [(angle: CGFloat, reach: CGFloat)] = [
    (0.0, 0.165), (0.9, 0.150), (1.7, 0.172), (2.6, 0.148), (3.4, 0.168), (4.3, 0.152), (5.2, 0.170),
]
for (index, lobe) in lobes.enumerated() {
    let next = lobes[(index + 1) % lobes.count]
    let point = CGPoint(x: eggCenter.x + cos(lobe.angle) * s * lobe.reach, y: eggCenter.y + sin(lobe.angle) * s * lobe.reach)
    let nextAngle = index + 1 == lobes.count ? next.angle + .pi * 2 : next.angle
    let middle = (lobe.angle + nextAngle) / 2
    let control = CGPoint(x: eggCenter.x + cos(middle) * s * (max(lobe.reach, next.reach) + 0.03),
                          y: eggCenter.y + sin(middle) * s * (max(lobe.reach, next.reach) + 0.03))
    let nextPoint = CGPoint(x: eggCenter.x + cos(nextAngle) * s * next.reach, y: eggCenter.y + sin(nextAngle) * s * next.reach)
    if index == 0 { white.move(to: point) }
    white.addQuadCurve(to: nextPoint, control: control)
}
white.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: s * 0.006, height: -s * 0.010), blur: s * 0.02, color: color(0, 0, 0, 0.6))
context.addPath(white)
context.setFillColor(color(0.96, 0.95, 0.92))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(white)
context.clip()
context.drawRadialGradient(
    gradient([(0.0, color(1, 1, 1)), (0.7, color(0.97, 0.96, 0.93)), (1.0, color(0.86, 0.82, 0.76))]),
    startCenter: CGPoint(x: eggCenter.x - s * 0.04, y: eggCenter.y + s * 0.05), startRadius: 0,
    endCenter: eggCenter, endRadius: s * 0.2, options: [.drawsAfterEndLocation])
// Crisp golden lace at the edge.
context.addPath(white)
context.setLineWidth(s * 0.012)
context.setStrokeColor(color(0.85, 0.62, 0.30, 0.55))
context.strokePath()
context.restoreGState()

// The yolk: a glossy dome.
let yolkRadius = s * 0.072
let yolkCenter = CGPoint(x: eggCenter.x - s * 0.012, y: eggCenter.y + s * 0.012)
context.saveGState()
context.setShadow(offset: CGSize(width: s * 0.008, height: -s * 0.012), blur: s * 0.022, color: color(0.45, 0.25, 0.05, 0.6))
context.addEllipse(in: CGRect(x: yolkCenter.x - yolkRadius, y: yolkCenter.y - yolkRadius, width: yolkRadius * 2, height: yolkRadius * 2))
context.setFillColor(color(0.98, 0.58, 0.05))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addEllipse(in: CGRect(x: yolkCenter.x - yolkRadius, y: yolkCenter.y - yolkRadius, width: yolkRadius * 2, height: yolkRadius * 2))
context.clip()
context.drawRadialGradient(
    gradient([(0.0, color(1.0, 0.86, 0.32)), (0.55, color(1.0, 0.66, 0.08)), (1.0, color(0.88, 0.42, 0.02))]),
    startCenter: CGPoint(x: yolkCenter.x - yolkRadius * 0.35, y: yolkCenter.y + yolkRadius * 0.35), startRadius: 0,
    endCenter: yolkCenter, endRadius: yolkRadius, options: [])
context.restoreGState()
context.addEllipse(in: CGRect(x: yolkCenter.x - yolkRadius * 0.55, y: yolkCenter.y + yolkRadius * 0.18,
                              width: yolkRadius * 0.55, height: yolkRadius * 0.38))
context.setFillColor(color(1, 1, 1, 0.75))
context.fillPath()

// MARK: The badge — a stopwatch, tilted and lifted like the calendar

let watchRadius = s * 0.145
context.saveGState()
context.translateBy(x: s * 0.715, y: s * 0.275)
context.rotate(by: -0.18)
func circle(_ r: CGFloat, _ c: CGPoint = .zero) -> CGRect {
    CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
}
// Crown and side pusher, behind the case.
let crown = CGRect(x: -watchRadius * 0.17, y: watchRadius * 0.92, width: watchRadius * 0.34, height: watchRadius * 0.30)
let stem = CGRect(x: -watchRadius * 0.09, y: watchRadius * 0.84, width: watchRadius * 0.18, height: watchRadius * 0.14)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.01, color: color(0, 0, 0, 0.45))
context.addPath(CGPath(roundedRect: crown, cornerWidth: watchRadius * 0.08, cornerHeight: watchRadius * 0.08, transform: nil))
context.addRect(stem)
context.setFillColor(color(0.96, 0.90, 0.80))
context.fillPath()
context.restoreGState()
context.saveGState()
context.rotate(by: -.pi / 4)
let pusher = CGRect(x: -watchRadius * 0.10, y: watchRadius * 0.90, width: watchRadius * 0.20, height: watchRadius * 0.20)
context.addPath(CGPath(roundedRect: pusher, cornerWidth: watchRadius * 0.05, cornerHeight: watchRadius * 0.05, transform: nil))
context.setFillColor(color(0.93, 0.86, 0.74))
context.fillPath()
context.restoreGState()
// The case: a cream bezel with its shadow on the glow.
context.saveGState()
context.setShadow(offset: CGSize(width: s * 0.012, height: -s * 0.024), blur: s * 0.045, color: color(0, 0, 0, 0.65))
context.addEllipse(in: circle(watchRadius))
context.setFillColor(color(0.97, 0.92, 0.83))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addEllipse(in: circle(watchRadius))
context.clip()
context.drawLinearGradient(gradient([(0.0, color(1.0, 0.99, 0.95)), (1.0, color(0.86, 0.76, 0.62))]),
                           start: CGPoint(x: -watchRadius, y: watchRadius), end: CGPoint(x: watchRadius, y: -watchRadius), options: [])
context.restoreGState()
// The dial sits a little deeper: an inner shadow ring, then the glossy orange face.
let dialRadius = watchRadius * 0.80
context.saveGState()
context.addEllipse(in: circle(dialRadius * 1.04))
context.clip()
context.drawLinearGradient(gradient([(0.0, color(0.55, 0.42, 0.30)), (1.0, color(1.0, 0.97, 0.92))]),
                           start: CGPoint(x: -dialRadius, y: dialRadius), end: CGPoint(x: dialRadius, y: -dialRadius), options: [])
context.restoreGState()
context.saveGState()
context.addEllipse(in: circle(dialRadius))
context.clip()
context.drawRadialGradient(
    gradient([(0.0, color(1.0, 0.70, 0.32)), (0.6, color(0.97, 0.45, 0.07)), (1.0, color(0.80, 0.28, 0.02))]),
    startCenter: CGPoint(x: -dialRadius * 0.35, y: dialRadius * 0.4), startRadius: 0,
    endCenter: .zero, endRadius: dialRadius, options: [])
context.restoreGState()
// Ticks at twelve, three, six and nine.
context.setLineCap(.round)
context.setStrokeColor(color(1, 1, 1, 0.9))
context.setLineWidth(watchRadius * 0.07)
for step in 0..<4 {
    let angle = CGFloat(step) * .pi / 2
    context.move(to: CGPoint(x: cos(angle) * dialRadius * 0.74, y: sin(angle) * dialRadius * 0.74))
    context.addLine(to: CGPoint(x: cos(angle) * dialRadius * 0.88, y: sin(angle) * dialRadius * 0.88))
}
context.strokePath()
// The hands: running, at about ten minutes past.
context.setStrokeColor(color(1, 1, 1))
context.setLineWidth(watchRadius * 0.10)
context.move(to: .zero)
context.addLine(to: CGPoint(x: 0, y: dialRadius * 0.62))
context.move(to: .zero)
context.addLine(to: CGPoint(x: dialRadius * 0.46, y: dialRadius * 0.26))
context.strokePath()
context.addEllipse(in: circle(watchRadius * 0.09))
context.setFillColor(color(1, 1, 1))
context.fillPath()
// Gloss: a soft highlight across the upper left of the glass.
context.saveGState()
context.addEllipse(in: circle(dialRadius))
context.clip()
context.addEllipse(in: CGRect(x: -dialRadius * 1.1, y: dialRadius * 0.05, width: dialRadius * 1.7, height: dialRadius * 1.25))
context.clip()
context.drawLinearGradient(gradient([(0.0, color(1, 1, 1, 0.45)), (1.0, color(1, 1, 1, 0.0))]),
                           start: CGPoint(x: -dialRadius, y: dialRadius), end: CGPoint(x: 0, y: 0), options: [])
context.restoreGState()
context.restoreGState()

// MARK: Write

guard let image = context.makeImage() else { fail("Cannot render the icon") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else { fail("Cannot encode the PNG") }
do {
    try png.write(to: target)
    print("Wrote \(target.path)")
} catch {
    fail("Cannot write \(target.path): \(error)")
}
