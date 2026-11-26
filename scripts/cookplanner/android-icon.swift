#!/usr/bin/env swift
//
// android-icon.swift
//
// CookPlanner's Android launcher icon from the iPhone's app icon
// (CookPlanner/CookPlanner/Assets.xcassets/AppIcon.appiconset/icon.png), as
// BakePlanner's Android icon was made: an adaptive icon with the picture at
// 80 % of the canvas (so the pan stays inside the launcher's mask) on a
// black background, the icon's own edge colour; the legacy square icon for
// older launchers; and the 512 × 512 store icon for Google Play. No
// monochrome layer: the picture has no flat silhouette.
//
//   swift scripts/cookplanner/android-icon.swift
//

import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("CookPlanner/CookPlanner/Assets.xcassets/AppIcon.appiconset/icon.png")
let res = root.appendingPathComponent("Android/CookPlannerAndroid/Android/app/src/main/res")

guard let image = NSImage(contentsOf: source),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot read \(source.path)\n".data(using: .utf8)!)
    exit(1)
}

/// `side` × `side` pixels: black ground, the icon at `share` of the side,
/// centred; `transparent` leaves the ground clear (the adaptive foreground).
func render(side: Int, share: CGFloat, transparent: Bool = false) -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: transparent ? CGImageAlphaInfo.premultipliedLast.rawValue
                                                    : CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    if !transparent {
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    let drawn = CGFloat(side) * share
    let origin = (CGFloat(side) - drawn) / 2
    context.draw(cgImage, in: CGRect(x: origin, y: origin, width: drawn, height: drawn))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

// Launcher sizes per density: legacy 48 dp, adaptive layers 108 dp.
let densities: [(String, CGFloat)] = [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]
for (name, scale) in densities {
    let folder = res.appendingPathComponent("mipmap-\(name)")
    write(render(side: Int(48 * scale), share: 1), to: folder.appendingPathComponent("ic_launcher.png"))
    write(render(side: Int(108 * scale), share: 0.8, transparent: true), to: folder.appendingPathComponent("ic_launcher_foreground.png"))
    write(render(side: Int(108 * scale), share: 0), to: folder.appendingPathComponent("ic_launcher_background.png"))
    try? FileManager.default.removeItem(at: folder.appendingPathComponent("ic_launcher_monochrome.png"))
}
write(render(side: 512, share: 1), to: root.appendingPathComponent("docs/cookplanner/appstore/android/play-icon-512.png"))
print("written")
