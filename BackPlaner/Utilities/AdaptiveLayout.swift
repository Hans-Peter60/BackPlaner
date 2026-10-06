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

    /// Half steps (2 = the recipe as stored); `nil` when a target dough
    /// weight overrides the picker, so no segment is highlighted.
    @Binding var selection: Int?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(selection: Binding<Int?>) {
        _selection = selection
    }

    init(selection: Binding<Int>) {
        _selection = Binding(
            get: { Optional(selection.wrappedValue) },
            set: { if let value = $0 { selection.wrappedValue = value } }
        )
    }

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
            Text(0.5, format: .number.precision(.fractionLength(1))).tag(Optional(1))
            Text(1.0, format: .number.precision(.fractionLength(1))).tag(Optional(2))
            Text(1.5, format: .number.precision(.fractionLength(1))).tag(Optional(3))
            Text(2.0, format: .number.precision(.fractionLength(1))).tag(Optional(4))
        }
    }
}

/// The scale a recipe is shown at, from either of two inputs.
enum ServingScale {

    /// A target dough weight wins over the picker; without one the picker's
    /// half steps apply (2 = 1.0).
    static func factor(servingSize: Int, targetWeight: Int?, baseWeight: Double) -> Double {
        if let targetWeight, targetWeight > 0, baseWeight > 0 {
            return Double(targetWeight) / baseWeight
        }
        return Double(servingSize) / 2
    }
}

/// Portion factor or target dough weight — two ways to the same scale.
///
/// Bakers think in "1,200 g Teigeinlage" or "zwölf Brötchen", not in 0.5 to
/// 2.0. Typing a weight into the field scales every amount to it and clears
/// the picker's selection; choosing a factor again clears the weight.
struct ServingScaleControl: View {

    @Binding var selectedServingSize: Int
    @Binding var targetWeight: Int?
    /// The recipe's total weight at factor 1.0.
    let baseWeight: Double

    @State private var weightText = ""
    @FocusState private var weightFieldFocused: Bool

    // 76 pt holds "1.332" at the default size; at the large sizes the
    // field kept that width and showed its digits visibly smaller than
    // the label next to it.
    @ScaledMetric(relativeTo: .body) private var weightFieldWidth: CGFloat = 76

    private var scale: Double {
        ServingScale.factor(servingSize: selectedServingSize, targetWeight: targetWeight, baseWeight: baseWeight)
    }

    /// `nil` while a weight is typed in, so no factor segment is lit.
    private var pickerSelection: Binding<Int?> {
        Binding(
            get: { targetWeight == nil ? selectedServingSize : nil },
            set: { value in
                guard let value else { return }
                selectedServingSize = value
                targetWeight = nil
                weightText = ""
            }
        )
    }

    var body: some View {
        PortraitAdaptiveStack(spacing: 12) {
            PortraitAdaptiveStack(spacing: 6) {
                Text("Portionsgröße")
                    .font(Theme.bodyFont(15))
                    .fixedSize(horizontal: false, vertical: true)
                ServingSizePicker(selection: pickerSelection)
            }

            HStack(spacing: 6) {
                Text("Teiggewicht")
                    .font(Theme.bodyFont(15))
                TextField(
                    "\(Int((baseWeight * scale).rounded()))",
                    text: $weightText
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: weightFieldWidth)
                .focused($weightFieldFocused)
                .font(Theme.bodyFont(15))
                .accessibilityLabel("Teiggewicht in Gramm")
                .onChange(of: weightText) { _, text in
                    let digits = text.filter(\.isNumber)
                    if digits != text { weightText = digits }
                    let value = Int(digits) ?? 0
                    targetWeight = value > 0 ? value : nil
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fertig") { weightFieldFocused = false }
                    }
                }
                Text(verbatim: "g")
                    .font(Theme.bodyFont(15))
            }
        }
    }
}

/// A form picker that stays readable at every text size.
///
/// In a `Form` a picker is a menu: label on the left, chosen value on the
/// right, and once the text is large the value is truncated in the middle
/// ("Nur auf…m Gerät"). At the accessibility sizes the picker becomes a
/// navigation link instead, whose row gives label and value a line each.
struct LargeTextPickerStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.pickerStyle(.navigationLink)
        } else {
            content.pickerStyle(.menu)
        }
    }
}

/// One line of a recipe's "Verarbeitungsschritte" table, already formatted.
struct InstructionStepRow: Identifiable {
    let id: Int
    /// "1.2" — the step number as shown.
    let step: String
    let instruction: String
    /// "10h 00m".
    let duration: String
}

/// The processing steps of a recipe at the accessibility text sizes.
///
/// The two detail screens show the steps as a three-column table. At those
/// sizes the columns no longer fit side by side: the description shrank to a
/// 162 pt column that broke words in half ("Weizensau / erteig") and the
/// duration column was pushed off the right edge of the screen. Here each
/// step is a block instead — number and duration on one line, the
/// description in full width underneath — which is how a table reads once
/// the text is this large.
struct InstructionStepsStackedView: View {

    let rows: [InstructionStepRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Schritt \(row.step)")
                            .bold()
                        Spacer(minLength: 8)
                        Text(row.duration)
                            .foregroundColor(Theme.subtitle)
                    }
                    Text(row.instruction)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // One step, one VoiceOver element: "Schritt 1.2, 10h 00m,
                // Kartoffeln abkochen" rather than three loose texts.
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
