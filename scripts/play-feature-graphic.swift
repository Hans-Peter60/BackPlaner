#!/usr/bin/env swift
//
// play-feature-graphic.swift
//
// Renders the feature graphic of the Google Play listing (1024 × 500, no
// alpha): the bakery photograph the app shows behind its screens, under the
// same light veil, the app icon on the left, and the name with the one-line
// promise on the right in the typeface of the App Store screenshots.
//
//   swift scripts/play-feature-graphic.swift <language> <target.png>
//
// The texts per language live in this file (one line each); the photo and
// the icon come from the iOS asset catalog. Needs only macOS.
//

import AppKit
import Foundation

struct Palette {
    // Theme.title / subtitle, light.
    static let title    = NSColor(red: 0.35, green: 0.20, blue: 0.08, alpha: 1)
    static let subtitle = NSColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1)
}

let texts: [String: (name: String, promise: String)] = [
    "de": ("BakePlanner", "Sag, wann das Brot fertig sein soll."),
    "en": ("BakePlanner", "Say when the bread should be ready."),
    "fr": ("BakePlanner", "Dites quand le pain doit être prêt."),
]

let width = 1024, height = 500
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let photoURL = root.appendingPathComponent("BackPlaner/Assets.xcassets/BakeryBackdrop.imageset/bakery-backdrop.jpg")
let iconURL = root.appendingPathComponent("BackPlaner/Assets.xcassets/AppIcon.appiconset/icon-light.png")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("Cannot read \(url.path)") }
    return image
}

func font(_ name: String, size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: name.contains("Heavy") ? .heavy : .medium)
}

guard CommandLine.arguments.count == 3, let text = texts[CommandLine.arguments[1]] else {
    fail("Usage: play-feature-graphic.swift <de|en|fr> <target.png>")
}
let target = URL(fileURLWithPath: CommandLine.arguments[2])

guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fail("Cannot create a drawing context") }
context.interpolationQuality = .high

// The photo, filled and shifted so the baker (at 68 % of its width) sits
// towards the right third, behind the text rather than under the icon.
let photo = loadImage(photoURL)
let scale = max(CGFloat(width) / CGFloat(photo.width), CGFloat(height) / CGFloat(photo.height))
let photoSize = CGSize(width: CGFloat(photo.width) * scale, height: CGFloat(photo.height) * scale)
let wantedX = CGFloat(width) * 0.72 - 0.68 * photoSize.width
let x = min(0, max(CGFloat(width) - photoSize.width, wantedX))
let y = (CGFloat(height) - photoSize.height) / 2
context.draw(photo, in: CGRect(x: x, y: y, width: photoSize.width, height: photoSize.height))
// The app's veil over the photo (BakeryBackdrop.lightOverlayOpacity).
context.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

// The icon with the rounded corners of a home-screen icon and a soft shadow.
let icon = loadImage(iconURL)
let iconSide: CGFloat = 300
let iconFrame = CGRect(x: 92, y: (CGFloat(height) - iconSide) / 2, width: iconSide, height: iconSide)
let iconPath = CGPath(roundedRect: iconFrame, cornerWidth: iconSide * 0.2237, cornerHeight: iconSide * 0.2237, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.3).cgColor)
context.setFillColor(NSColor.black.cgColor)
context.addPath(iconPath)
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(iconPath)
context.clip()
context.draw(icon, in: iconFrame)
context.restoreGState()

// Name and promise, left-aligned beside the icon.
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .left
paragraph.lineBreakMode = .byWordWrapping
let name = NSAttributedString(string: text.name, attributes: [
    .font: font("Avenir-Heavy", size: 84), .foregroundColor: Palette.title, .paragraphStyle: paragraph])
let promise = NSAttributedString(string: text.promise, attributes: [
    .font: font("Avenir-Medium", size: 40), .foregroundColor: Palette.subtitle, .paragraphStyle: paragraph])
let textX = iconFrame.maxX + 64
let textWidth = CGFloat(width) - textX - 56
let nameHeight = ceil(name.boundingRect(with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin]).height)
let promiseHeight = ceil(promise.boundingRect(with: CGSize(width: textWidth, height: 1000), options: [.usesLineFragmentOrigin]).height)
let gap: CGFloat = 10
let blockHeight = nameHeight + gap + promiseHeight
var textY = (CGFloat(height) + blockHeight) / 2 - nameHeight
name.draw(with: CGRect(x: textX, y: textY, width: textWidth, height: nameHeight), options: [.usesLineFragmentOrigin])
textY -= gap + promiseHeight
promise.draw(with: CGRect(x: textX, y: textY, width: textWidth, height: promiseHeight), options: [.usesLineFragmentOrigin])
NSGraphicsContext.restoreGraphicsState()

try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let result = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil)
else { fail("Cannot render") }
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { fail("Cannot write \(target.path)") }
print("wrote \(target.path)")
