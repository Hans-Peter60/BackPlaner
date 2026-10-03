//
//  BakeryBackdropView.swift
//  BackPlaner
//
//  A soft-focus photograph of a bakery (a baker kneading bread dough) that
//  fills the whole screen behind the content. The photo lives in the asset
//  catalog as `BakeryBackdrop` (landscape, 1536 × 1024; an optional
//  dark-appearance variant can be added in the same image set). If the slot
//  is empty the view draws nothing and the plain gradient from
//  `Theme.background` shows as before.
//
//  The blur is applied once with Core Image and cached, not per frame with
//  `.blur(radius:)`, so the 28 screens that use `warmBackground` do not each
//  pay for a live Gaussian filter on a full-screen layer.
//
//  Purely decorative: hidden from VoiceOver and never hit-testable.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct BakeryBackdrop: View {

    @Environment(\.colorScheme) private var colorScheme
    @State private var loaded: UIImage?

    /// The point of the photo that must stay in view when the screen's aspect
    /// ratio forces a crop. The photo is landscape and the baker stands at
    /// about two thirds of its width; a centred crop on an iPhone would show
    /// the stand mixer and cut him off.
    static let focalPoint = UnitPoint(x: 0.68, y: 0.5)

    /// Opacity of the `systemBackground` veil over the photo. White in light
    /// mode, black in dark mode.
    ///
    /// Measured on 03.10.2026 against the iPhone crop of the supplied photo
    /// (worst 5 % of the background, WCAG contrast of free-standing text):
    ///
    ///   light 0.25 → title 5.6, subtitle 3.9, accentText 3.8 (median 4.8)
    ///   light 0.45 → title 6.9, subtitle 4.7, accentText 4.6
    ///   dark  0.40 → title 8.7, subtitle 5.6, accentText 4.4
    ///   dark  0.50 → title 10.2, subtitle 6.6, accentText 5.1
    ///
    /// 0.45 was chosen over the lighter 0.25 after comparing both: it is the
    /// lowest value at which subtitle/accentText clear 4.5:1 in the darkest
    /// 5 % of the picture, at the price of the photo reading as a pale wash.
    /// Dark mode has its own, dimly lit photo in the asset's dark slot; with
    /// it 0.50 is the lowest value that clears 4.5 for all three text colours
    /// (the bright light-mode photo under a black veil had needed 0.75).
    static let lightOverlayOpacity: Double = 0.45
    static let darkOverlayOpacity: Double = 0.50

    var body: some View {
        // Every screen creates its own BakeryBackdrop, so the first thing to
        // try is the shared cache: after the very first screen the photo is
        // already prepared and must appear immediately, not fade in again on
        // each navigation push.
        let image = loaded ?? BakeryBackdropImageStore.shared.cached(for: colorScheme)

        GeometryReader { geo in
            if let image {
                let placement = Self.placement(of: image.size, in: geo.size)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: placement.width, height: placement.height)
                    .offset(x: placement.minX, y: placement.minY)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
                    .overlay(overlay)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: colorScheme) {
            guard BakeryBackdropImageStore.shared.cached(for: colorScheme) == nil else { return }
            let prepared = await BakeryBackdropImageStore.shared.prepareInBackground(for: colorScheme)
            withAnimation(.easeOut(duration: 0.35)) { loaded = prepared }
        }
    }

    private var overlay: some View {
        Color(.systemBackground)
            .opacity(colorScheme == .dark ? Self.darkOverlayOpacity : Self.lightOverlayOpacity)
    }

    /// Aspect-fill rectangle for the photo inside `container`, shifted so the
    /// focal point is as close to the container's centre as the crop allows.
    static func placement(of imageSize: CGSize, in container: CGSize) -> CGRect {
        let scale = max(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let x = container.width / 2 - focalPoint.x * size.width
        let y = container.height / 2 - focalPoint.y * size.height
        return CGRect(
            x: min(0, max(container.width - size.width, x)),
            y: min(0, max(container.height - size.height, y)),
            width: size.width,
            height: size.height)
    }
}

// MARK: - Image preparation

/// Loads the backdrop photo for a colour scheme, softens it once and keeps the
/// result for the lifetime of the app.
final class BakeryBackdropImageStore: Sendable {

    static let shared = BakeryBackdropImageStore()

    /// Name of the image set in Assets.xcassets.
    static let assetName = "BakeryBackdrop"

    /// Blur radius as a fraction of the photo's shorter side, so the softness
    /// is the same whatever resolution the photo has (≈ 6 px for 1024 px).
    /// The supplied picture is already gently soft, so this stays modest.
    static let blurFraction: Double = 0.006

    private let lock = NSLock()
    nonisolated(unsafe) private var cache: [ColorScheme: UIImage] = [:]
    nonisolated(unsafe) private var assetIsMissing = false

    /// The prepared photo if it has been made already; never does any work.
    func cached(for scheme: ColorScheme) -> UIImage? {
        lock.withLock { cache[scheme] }
    }

    /// Loads and softens the photo. This takes a noticeable fraction of a
    /// second for a large image, so outside of previews call
    /// `prepareInBackground` instead.
    @discardableResult
    func prepare(for scheme: ColorScheme) -> UIImage? {
        if let cached = cached(for: scheme) { return cached }
        if lock.withLock({ assetIsMissing }) { return nil }

        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        guard let source = UIImage(named: Self.assetName, in: .main, compatibleWith: traits) else {
            lock.withLock { assetIsMissing = true }
            return nil
        }
        let prepared = Self.soften(source) ?? source
        lock.withLock { cache[scheme] = prepared }
        return prepared
    }

    func prepareInBackground(for scheme: ColorScheme) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { self.prepare(for: scheme) }.value
    }

    private static func soften(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }

        let blur = CIFilter.gaussianBlur()
        // Clamping first stops the edges from fading to transparent.
        blur.inputImage = input.clampedToExtent()
        blur.radius = Float(min(input.extent.width, input.extent.height) * blurFraction)
        guard let output = blur.outputImage?.cropped(to: input.extent) else { return nil }

        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Previews

#Preview("Hell") {
    // Prepared up front so the canvas shows the photo in its first frame.
    let _ = BakeryBackdropImageStore.shared.prepare(for: .light)
    BackdropPreviewContent()
}

#Preview("Dunkel") {
    let _ = BakeryBackdropImageStore.shared.prepare(for: .dark)
    BackdropPreviewContent()
        .preferredColorScheme(.dark)
}

/// Sample screen so the photo can be judged behind real cards and free text.
/// All strings are verbatim so the preview does not seed the string catalog.
private struct BackdropPreviewContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ScreenHeader(brand: "BackPlaner")
            ForEach(["Meine Rezepte", "Backplan", "Einkaufsliste"], id: \.self) { title in
                HStack {
                    IconBadge(systemImage: "book")
                    Text(verbatim: title)
                        .font(Theme.bodyFont(17))
                        .foregroundColor(Theme.cardTitle)
                    Spacer()
                }
                .cardStyle()
            }
            Spacer()
            Text(verbatim: "Text direkt auf dem Hintergrund")
                .font(Theme.bodyFont(15))
                .foregroundColor(Theme.subtitle)
            Text(verbatim: "Akzenttext auf dem Hintergrund")
                .font(Theme.bodyFont(15))
                .foregroundColor(Theme.accentText)
        }
        .padding()
        .warmBackground()
    }
}
