#!/usr/bin/env swift
//
// appstore-captions.swift
//
// Sets a headline over each App Store screenshot: the picture is scaled down
// onto a warm background in the app's colours, with rounded corners and a soft
// shadow, and the headline for the screen stands above it in the app's
// typeface. The result keeps the pixel size of the original, which is what
// App Store Connect checks, and carries no alpha channel.
//
//   swift scripts/appstore-captions.swift <captions.json> <language> <raw folder> <target folder>
//
// The captions file maps a language to the screens, each keyed by the file
// name after its number ("rezept-backen" for 01-rezept-backen.png). A value
// is the headline, with an optional second, smaller line after a "|". A
// screen without an entry is copied as it is. Run by
// scripts/appstore-screenshots.sh; needs only macOS.
//

import AppKit
import Foundation

struct Palette {
    // Theme.backgroundTop / backgroundBottom / title / subtitle, light.
    static let backgroundTop    = NSColor(red: 0.98, green: 0.93, blue: 0.82, alpha: 1)
    static let backgroundBottom = NSColor(red: 0.93, green: 0.80, blue: 0.62, alpha: 1)
    static let title            = NSColor(red: 0.35, green: 0.20, blue: 0.08, alpha: 1)
    static let subtitle         = NSColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1)
}

/// The proportions of a composed picture, all relative to the width (iPhone
/// and iPad pictures differ in their aspect ratio, so nothing hangs on the
/// height).
struct Layout {
    let width: CGFloat
    let height: CGFloat

    var margin: CGFloat { width * 0.07 }
    var headlineSize: CGFloat { width * 0.056 }
    var sublineSize: CGFloat { width * 0.034 }
    var lineGap: CGFloat { width * 0.012 }
    var headlineTop: CGFloat { height * 0.045 }
    var textToPicture: CGFloat { width * 0.045 }
    // Relative to the shorter side, so the iPad's wide picture does not cut
    // into its status bar.
    var cornerRadius: CGFloat { min(width, height) * 0.045 }
    var bottomMargin: CGFloat { height * 0.03 }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func font(_ name: String, size: CGFloat) -> NSFont {
    NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: name.contains("Heavy") ? .heavy : .medium)
}

func attributed(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph
    ])
}

func textHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
    let bounds = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading])
    return ceil(bounds.height)
}

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func save(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot write \(url.path)") }
}

/// Composes `picture` with the headline `caption` into a picture of the same
/// size.
func compose(_ picture: CGImage, caption: String) -> CGImage {
    let width = CGFloat(picture.width), height = CGFloat(picture.height)
    let layout = Layout(width: width, height: height)

    // 32 bits per pixel without alpha: the PNG comes out opaque RGB.
    guard let context = CGContext(data: nil, width: picture.width, height: picture.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fail("Cannot create a drawing context") }

    // Background: the app's gradient, light at the top.
    let colors = [Palette.backgroundTop.cgColor, Palette.backgroundBottom.cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

    // The text: headline, and a subline when the caption has one.
    let parts = caption.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let headline = attributed(parts[0], font: font("Avenir-Heavy", size: layout.headlineSize), color: Palette.title)
    let subline = parts.count > 1
        ? attributed(parts[1], font: font("Avenir-Medium", size: layout.sublineSize), color: Palette.subtitle)
        : nil
    let textWidth = width - 2 * layout.margin
    let headlineHeight = textHeight(of: headline, width: textWidth)
    let sublineHeight = subline.map { textHeight(of: $0, width: textWidth) } ?? 0
    let textBlockHeight = headlineHeight + (subline == nil ? 0 : layout.lineGap + sublineHeight)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    // CoreGraphics counts y from the bottom.
    var y = height - layout.headlineTop - headlineHeight
    headline.draw(with: CGRect(x: layout.margin, y: y, width: textWidth, height: headlineHeight),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    if let subline {
        y -= layout.lineGap + sublineHeight
        subline.draw(with: CGRect(x: layout.margin, y: y, width: textWidth, height: sublineHeight),
                     options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
    NSGraphicsContext.restoreGraphicsState()

    // The picture under the text, scaled to the room that is left.
    let pictureTop = height - layout.headlineTop - textBlockHeight - layout.textToPicture
    let room = pictureTop - layout.bottomMargin
    let scale = min(room / height, (width - 2 * layout.margin) / width)
    let size = CGSize(width: width * scale, height: height * scale)
    let frame = CGRect(x: (width - size.width) / 2, y: pictureTop - size.height, width: size.width, height: size.height)
    let path = CGPath(roundedRect: frame, cornerWidth: layout.cornerRadius * scale,
                      cornerHeight: layout.cornerRadius * scale, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -width * 0.015), blur: width * 0.04,
                      color: NSColor.black.withAlphaComponent(0.22).cgColor)
    context.setFillColor(NSColor.white.cgColor)
    context.addPath(path)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.interpolationQuality = .high
    context.draw(picture, in: frame)
    context.restoreGState()

    guard let result = context.makeImage() else { fail("Cannot render the picture") }
    return result
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail("Usage: appstore-captions.swift <captions.json> <language> <raw folder> <target folder>")
}
let captionsURL = URL(fileURLWithPath: arguments[1])
let language = arguments[2]
let rawFolder = URL(fileURLWithPath: arguments[3])
let targetFolder = URL(fileURLWithPath: arguments[4])

guard let data = try? Data(contentsOf: captionsURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
else { fail("Cannot read \(captionsURL.path)") }
let captions = json[language] ?? [:]
if captions.isEmpty {
    FileHandle.standardError.write("No captions for „\(language)“ in \(captionsURL.lastPathComponent); copying the pictures as they are.\n".data(using: .utf8)!)
}

try? FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
let files = ((try? FileManager.default.contentsOfDirectory(atPath: rawFolder.path)) ?? [])
    .filter { $0.hasSuffix(".png") }
    .sorted()

for file in files {
    let source = rawFolder.appendingPathComponent(file)
    let target = targetFolder.appendingPathComponent(file)
    // "01-rezept-backen.png" → "rezept-backen"
    let name = file.dropLast(4)
    let key = name.contains("-") ? String(name.drop(while: { $0 != "-" }).dropFirst()) : String(name)

    guard let caption = captions[key], !caption.isEmpty, let picture = loadImage(source) else {
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
        continue
    }
    save(compose(picture, caption: caption), to: target)
}
