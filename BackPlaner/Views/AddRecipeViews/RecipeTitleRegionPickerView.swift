//
//  RecipeTitleRegionPickerView.swift
//  BackPlaner
//
//  Lets the user point at the recipe's name on the photographed page.
//

import SwiftUI
import UIKit

/// Shows the photographed pages with every recognized line marked, so the user
/// can tap the one that is the recipe's name.
///
/// Which line is the title cannot be settled from the text alone: a logo, a
/// browser's print header and a column caption all look like headings, and the
/// same recipe photographed a little wider reads differently. Rather than
/// guessing harder, the page is shown as it was photographed and the choice is
/// handed over.
struct RecipeTitleRegionPickerView: View {

    let pageImages: [UIImage]
    let regions: [RecipeTextRegion]

    @State private var chosenText: String
    @State private var page: Int
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1

    private let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        pageImages: [UIImage],
        regions: [RecipeTextRegion],
        currentTitle: String,
        onChoose: @escaping (String) -> Void
    ) {
        self.pageImages = pageImages
        self.regions = regions
        self.onChoose = onChoose
        _chosenText = State(initialValue: currentTitle)
        // Open on the page the current name was read from.
        let match = regions.first { $0.text == currentTitle } ?? regions.first
        _page = State(initialValue: match?.page ?? 0)
    }

    /// The pages that actually carry recognized text, in order.
    private var pagesWithText: [Int] {
        Array(Set(regions.map(\.page))).sorted().filter { pageImages.indices.contains($0) }
    }

    private var regionsOnPage: [RecipeTextRegion] {
        regions.filter { $0.page == page }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructions
                if pagesWithText.count > 1 { pageSelector }
                if pageImages.indices.contains(page) {
                    pageView(pageImages[page])
                } else {
                    ContentUnavailableView(
                        "Seite nicht verfügbar",
                        systemImage: "photo",
                        description: Text("Tippe den Namen unten ein.")
                    )
                }
                chosenName
            }
            .warmBackground()
            .navigationTitle("Name wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        onChoose(chosenText.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(chosenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var instructions: some View {
        Text("Tippe die Zeile an, die der Rezeptname sein soll. Steht der Name nicht auf der Seite, kannst du ihn unten eintippen.")
            .font(.footnote)
            // .secondary is only 2.9:1 on the warm background.
            .foregroundStyle(Theme.subtitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 10)
    }

    private var pageSelector: some View {
        Picker("Seite", selection: $page) {
            ForEach(pagesWithText, id: \.self) { index in
                Text("Seite \(index + 1)").tag(index)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .onChange(of: page) { _, _ in
            zoom = 1
            committedZoom = 1
        }
    }

    private func pageView(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let fitted = fittedSize(of: image, in: proxy.size)
            let drawn = CGSize(width: fitted.width * zoom, height: fitted.height * zoom)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: drawn.width, height: drawn.height)
                        .accessibilityHidden(true)

                    ForEach(regionsOnPage) { region in
                        let frame = viewFrame(of: region, in: drawn)
                        marker(for: region)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
                .frame(
                    width: max(drawn.width, proxy.size.width),
                    height: max(drawn.height, proxy.size.height),
                    alignment: .topLeading
                )
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { zoom = (committedZoom * $0.magnification).clamped(to: 1...6) }
                    .onEnded { _ in committedZoom = zoom }
            )
        }
    }

    private func marker(for region: RecipeTextRegion) -> some View {
        let isChosen = region.text == chosenText

        return Button {
            chosenText = region.text
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    isChosen ? Theme.accentText : Theme.subtitle.opacity(0.7),
                    lineWidth: isChosen ? 3 : 1
                )
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accentText.opacity(isChosen ? 0.28 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(region.text)
        .accessibilityHint("Als Rezeptnamen übernehmen")
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private var chosenName: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rezeptname")
                .font(.caption)
                .foregroundStyle(Theme.subtitle)
            TextField("Rezeptname", text: $chosenText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Rezeptname")
        }
        .padding()
    }

    /// The image drawn to fit the available space, which is what the normalized
    /// rectangles have to be measured against.
    private func fittedSize(of image: UIImage, in available: CGSize) -> CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0,
              available.width > 0, available.height > 0 else {
            return available
        }
        let scale = min(available.width / size.width, available.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Vision measures from the bottom-left corner and SwiftUI from the
    /// top-left, so the rectangle is flipped on the way in.
    private func viewFrame(of region: RecipeTextRegion, in size: CGSize) -> CGRect {
        let box = region.boundingBox
        return CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
