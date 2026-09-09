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

/// Scales a hand-tuned point size with the user's preferred text size, the way
/// `@ScaledMetric` does — but usable outside a `View`, which is what the
/// `GridItem` column widths need.
///
/// The data tables in this app are laid out with fixed-width columns sized for
/// the default text size. Left alone they clip their contents as soon as the
/// text grows, so every one of those widths is passed through here.
func scaledLayoutValue(_ value: CGFloat) -> CGFloat {
    UIFontMetrics(forTextStyle: .body).scaledValue(for: value)
}

/// The width of one data-table column.
///
/// Normally a fixed width, scaled with the text size. At the accessibility sizes
/// it becomes flexible instead: a `LazyVGrid` of fixed columns has a hard minimum
/// width, and once the scaled columns add up to more than the display the grid
/// forces its whole ancestry wider than the screen — which is what pushed the
/// recipe screens off both edges. Flexible columns let the table shrink to fit
/// and wrap its text rather than dragging the page sideways.
func scaledColumnSize(_ width: CGFloat) -> GridItem.Size {
    let scaled = scaledLayoutValue(width)
    guard UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory else {
        return .fixed(scaled)
    }
    return .flexible(minimum: min(width, 28), maximum: scaled)
}

/// Lets a too-wide data table be scrolled sideways once the text no longer fits,
/// instead of clipping it at both screen edges.
///
/// Below the accessibility text sizes this is a no-op, so the dense recipe grids
/// keep exactly the layout they have today; only at the sizes where they would
/// otherwise be unreadable do they become horizontally scrollable.
private struct WideTextScroll: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView(.horizontal) { content }
                // Without this the scroll view reports its content's ideal width
                // as its own, which propagates up and stretches the whole screen
                // sideways instead of keeping the overflow inside the table.
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }
}

extension View {
    /// See ``WideTextScroll`` — apply to fixed-column data tables.
    func scrollsSidewaysAtLargeText() -> some View { modifier(WideTextScroll()) }
}

/// The 0,5 / 1,0 / 1,5 / 2,0 serving-size selector shown on all four recipe
/// screens.
///
/// It is a segmented control at normal text sizes, but a segmented control has a
/// hard minimum width — four segments of accessibility-size digits come to about
/// 450 pt, wider than an iPhone screen. Because that minimum cannot be
/// negotiated down, it used to stretch the whole screen's content and push it
/// off both edges. At accessibility sizes it therefore becomes a menu picker,
/// which stays compact whatever the text size.
struct ServingSizePicker: View {

    @Binding var selection: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                picker.pickerStyle(.menu)
            } else {
                picker.pickerStyle(.segmented)
                    .frame(maxWidth: 160)
            }
        }
        .font(Theme.bodyFont(15))
        .accessibilityLabel("Portionsgröße")
    }

    private var picker: some View {
        Picker("", selection: $selection) {
            Text(0.5, format: .number.precision(.fractionLength(1))).tag(1)
            Text(1.0, format: .number.precision(.fractionLength(1))).tag(2)
            Text(1.5, format: .number.precision(.fractionLength(1))).tag(3)
            Text(2.0, format: .number.precision(.fractionLength(1))).tag(4)
        }
    }
}

/// Lays its content out horizontally (as before) on iPhone landscape and iPad,
/// but vertically (stacked) on iPhone portrait so wide rows are not cut off.
///
/// It also stacks at the accessibility text sizes regardless of device: at those
/// sizes even an iPad row of controls outgrows the screen width.
struct PortraitAdaptiveStack<Content: View>: View {

    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment:   VerticalAlignment   = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass)   private var vSize
    @Environment(\.dynamicTypeSize)     private var dynamicTypeSize

    var body: some View {
        if isPhonePortrait(hSize, vSize) || dynamicTypeSize.isAccessibilitySize {
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
    @Environment(\.dynamicTypeSize)     private var dynamicTypeSize

    var body: some View {
        let time = timeCalculation.calculateTime(t: date)
        let day  = dateFormat.calculateDate(dT: date)

        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            if isPhonePortrait(hSize, vSize) || dynamicTypeSize.isAccessibilitySize {
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
        // Date and time belong together — in portrait they are two Text views
        // that VoiceOver would otherwise read as two unrelated elements.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(day), \(time)"))
    }
}
