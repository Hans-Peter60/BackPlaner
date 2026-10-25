#!/usr/bin/env swift
//
// appstore-preview-captions.swift
//
// Renders the captions of the App Store preview videos as transparent PNG
// overlays, one per caption and language: a rounded pill in the app's
// colours with the headline in the app's typeface and, after a "|", a
// smaller second line. Everything outside the pill is transparent, so the
// picture can lie over the video in iMovie as a cutaway ("Ausschnitt") and
// the app stays visible around it. iMovie's own title templates are not
// used: their names and positions change between versions, and none of
// them matches the headlines on the screenshots.
//
//   swift scripts/appstore-preview-captions.swift <preview-captions.json> <language> <target folder>
//                                                 [--size <width>x<height>] [--position top|bottom]
//
// The captions file holds, per language, an ordered list of { "file", "text" }.
// The overlays come out as <file>.png in the target folder, in the pixel
// size of the finished video (default 886x1920, the iPhone preview iMovie
// exports), so that iMovie lays them over the frame without scaling or
// cropping. --position bottom puts the pill into the lower part of the
// frame for scenes whose top is busy. Needs only macOS.
//

import AppKit
import Foundation

struct Palette {
    // Theme.backgroundTop / title / subtitle, light, as on the screenshots.
    static let pill     = NSColor(red: 0.98, green: 0.93, blue: 0.82, alpha: 0.96)
    static let title    = NSColor(red: 0.35, green: 0.20, blue: 0.08, alpha: 1)
    static let subtitle = NSColor(red: 0.45, green: 0.30, blue: 0.16, alpha: 1)
}

/// Proportions relative to the frame width: the previews are portrait, and
/// the text has to stay legible in the small autoplaying tile of the search
/// results, so the headline is a little larger than on the screenshots.
struct Layout {
    let width: CGFloat
    let height: CGFloat

    var sideMargin: CGFloat { width * 0.06 }
    var pillPadding: CGFloat { width * 0.045 }
    var headlineSize: CGFloat { width * 0.062 }
    var sublineSize: CGFloat { width * 0.038 }
    var lineGap: CGFloat { width * 0.012 }
    var cornerRadius: CGFloat { width * 0.05 }
    /// Below the status bar and the navigation bar's title.
    var topInset: CGFloat { height * 0.075 }
    /// Above the tab bar and the home indicator.
    var bottomInset: CGFloat { height * 0.10 }
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

func save(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fail("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot write \(url.path)") }
}

/// A transparent frame of `size` with the caption in a pill at the top or
/// the bottom.
func render(_ caption: String, size: (width: Int, height: Int), atBottom: Bool) -> CGImage {
    let width = CGFloat(size.width), height = CGFloat(size.height)
    let layout = Layout(width: width, height: height)

    // Premultiplied alpha: the PNG keeps its transparency for iMovie.
    guard let context = CGContext(data: nil, width: size.width, height: size.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("Cannot create a drawing context") }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))

    let parts = caption.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let headline = attributed(parts[0], font: font("Avenir-Heavy", size: layout.headlineSize), color: Palette.title)
    let subline = parts.count > 1
        ? attributed(parts[1], font: font("Avenir-Medium", size: layout.sublineSize), color: Palette.subtitle)
        : nil
    let textWidth = width - 2 * layout.sideMargin - 2 * layout.pillPadding
    let headlineHeight = textHeight(of: headline, width: textWidth)
    let sublineHeight = subline.map { textHeight(of: $0, width: textWidth) } ?? 0
    let textBlockHeight = headlineHeight + (subline == nil ? 0 : layout.lineGap + sublineHeight)
    let pillHeight = textBlockHeight + 2 * layout.pillPadding

    // CoreGraphics counts y from the bottom.
    let pillY = atBottom ? layout.bottomInset : height - layout.topInset - pillHeight
    let pill = CGRect(x: layout.sideMargin, y: pillY, width: width - 2 * layout.sideMargin, height: pillHeight)
    let path = CGPath(roundedRect: pill, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -width * 0.01), blur: width * 0.03,
                      color: NSColor.black.withAlphaComponent(0.25).cgColor)
    context.setFillColor(Palette.pill.cgColor)
    context.addPath(path)
    context.fillPath()
    context.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    var y = pill.maxY - layout.pillPadding - headlineHeight
    let textX = pill.minX + layout.pillPadding
    headline.draw(with: CGRect(x: textX, y: y, width: textWidth, height: headlineHeight),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
    if let subline {
        y -= layout.lineGap + sublineHeight
        subline.draw(with: CGRect(x: textX, y: y, width: textWidth, height: sublineHeight),
                     options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let result = context.makeImage() else { fail("Cannot render the overlay") }
    return result
}

// MARK: - Main

var arguments = Array(CommandLine.arguments.dropFirst())
var size = (width: 886, height: 1920)
var atBottom = false
while let index = arguments.firstIndex(where: { $0.hasPrefix("--") }) {
    let option = arguments.remove(at: index)
    guard index < arguments.count else { fail("\(option) needs a value") }
    let value = arguments.remove(at: index)
    switch option {
    case "--size":
        let parts = value.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { fail("--size takes <width>x<height>") }
        size = (parts[0], parts[1])
    case "--position":
        switch value {
        case "top": atBottom = false
        case "bottom": atBottom = true
        default: fail("--position takes top or bottom")
        }
    default:
        fail("Unknown option \(option)")
    }
}
guard arguments.count == 3 else {
    fail("Usage: appstore-preview-captions.swift <preview-captions.json> <language> <target folder> [--size <w>x<h>] [--position top|bottom]")
}
let captionsURL = URL(fileURLWithPath: arguments[0])
let language = arguments[1]
let targetFolder = URL(fileURLWithPath: arguments[2])

guard let data = try? Data(contentsOf: captionsURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]]
else { fail("Cannot read \(captionsURL.path)") }
guard let captions = json[language], !captions.isEmpty else {
    fail("No captions for „\(language)“ in \(captionsURL.lastPathComponent)")
}

try? FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
for entry in captions {
    guard let file = entry["file"], let text = entry["text"], !text.isEmpty else { continue }
    let suffix = atBottom ? "-unten" : ""
    let target = targetFolder.appendingPathComponent("\(file)\(suffix).png")
    save(render(text, size: size, atBottom: atBottom), to: target)
    print(target.path)
}
