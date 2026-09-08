//
//  AdaptiveLayout.swift
//  BackPlaner
//
//  Small layout helpers that adapt to the device orientation. After the forced
//  landscape mode was removed, some rows are too wide for iPhone portrait and get
//  cut off. These helpers stack their content vertically on iPhone portrait while
//  keeping the previous horizontal layout on iPhone landscape and on iPad.
//

import SwiftUI

/// True only when running on a compact-width, regular-height layout — i.e. an
/// iPhone held in portrait. iPhone landscape reports a compact height and iPad
/// reports a regular width, so both keep the horizontal layout.
private func isPhonePortrait(_ h: UserInterfaceSizeClass?,
                             _ v: UserInterfaceSizeClass?) -> Bool {
    h == .compact && v == .regular
}

/// Lays its content out horizontally (as before) on iPhone landscape and iPad,
/// but vertically (stacked) on iPhone portrait so wide rows are not cut off.
struct PortraitAdaptiveStack<Content: View>: View {

    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment:   VerticalAlignment   = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass)   private var vSize

    var body: some View {
        if isPhonePortrait(hSize, vSize) {
            VStack(alignment: horizontalAlignment, spacing: spacing) { content() }
        } else {
            HStack(alignment: verticalAlignment, spacing: spacing) { content() }
        }
    }
}

/// Displays a date and its time together. On iPhone portrait the time is stacked
/// above the date; on iPhone landscape and iPad both appear on one line
/// ("date, time") exactly as before.
struct StackedDateTime: View {

    let date: Date
    var systemImage: String? = nil
    var font:  Font  = Theme.bodyFont(15)
    var color: Color = Theme.subtitle
    var alignment: HorizontalAlignment = .leading

    private let timeCalculation = TimeCalculation()
    private let dateFormat       = DateFormat()

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass)   private var vSize

    var body: some View {
        let time = timeCalculation.calculateTime(t: date)
        let day  = dateFormat.calculateDate(dT: date)

        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            if isPhonePortrait(hSize, vSize) {
                // Portrait: time above the date.
                VStack(alignment: alignment, spacing: 1) {
                    Text(time)
                    Text(day)
                }
            } else {
                // Landscape / iPad: single line, as before.
                Text(verbatim: "\(day), \(time)")
            }
        }
        .font(font)
        .foregroundColor(color)
    }
}
