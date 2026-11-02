import BakePlannerCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The planned steps as a project plan, the iPhone's timeline in portrait:
/// the time axis on the left, one column per plan, a bar per step as long
/// as the step lasts, markers for the sub-steps inside it, hour ticks, the
/// night collapsed to a band, the finish flagged and a red line for now.
/// `PlanTimelineScale` and `PlanTimelineLane` from the package do the
/// arithmetic; this file only places what they describe. Only the
/// taller-than-wide screen (a phone held upright) reads the plan top-down
/// with the plans as columns; a wider one (a tablet, a phone on its side)
/// left to right with a row per plan, the way a project plan is usually
/// drawn — the iPhone's two layouts.
///
/// CGFloat is not named here (Foundation and SkipFuseUI both define it on
/// Android): the package's values are read as Double and handed back with
/// `.init`.
enum ChartMetrics {
    /// The time axis on the left.
    static let axisThickness = 54.0
    /// The lane headers (picture and recipe name): the row height above the
    /// columns, the column width beside the rows.
    static let laneHeaderHeight = 48.0
    static let laneHeaderWidth = 132.0
    /// Lanes as rows are this high.
    static let laneHeight = 64.0
    /// Columns are at least this wide and at most that; fewer plans share
    /// the screen width.
    static let minimumLaneWidth = 150.0
    static let maximumLaneWidth = 440.0
    static let laneSpacing = 6.0
    /// Between two bars that run at the same time and share a column.
    static let trackSpacing = 3.0
    /// The scale: how long an idle stretch has to be before it collapses,
    /// the band it collapses to, the smallest distance between two step
    /// boundaries, and the least room between two axis labels.
    static let gapThreshold: TimeInterval = 4 * 3600
    static let gapLength = 44.0
    static let gapEdgeMinutes = 30.0
    static let gapEdgePoints = 26.0
    static let minimumInterval = 26.0
    /// A bar with a marker in its first minute: one line for the bar, one
    /// for the marker.
    static let roomForStartMarker = 40.0
    static let labelHeight = 16.0
    static let barLineHeight = 16.5
    static let minimumTickSpacing = 40.0
    /// Room before the first step for its axis label, and after the last
    /// one for the finish flag.
    static let leadingInset = 24.0
    static let trailingPadding = 36.0

    static func gapEdge(pointsPerMinute: Double) -> TimeInterval {
        TimeInterval(max(gapEdgeMinutes, gapEdgePoints / pointsPerMinute) * 60)
    }

    /// The scale for these lanes at this zoom, as the iPhone builds it.
    static func scale(for lanes: [PlanTimelineLane], pointsPerMinute: Double) -> PlanTimelineScale {
        var roomAfter: [Date: Foundation.CGFloat] = [:]
        for date in lanes.flatMap(\.startsWithMarker) {
            roomAfter[date] = .init(roomForStartMarker)
        }
        return PlanTimelineScale(boundaries: lanes.flatMap(\.boundaries),
                                 pointsPerMinute: .init(pointsPerMinute),
                                 minimumInterval: .init(minimumInterval),
                                 roomAfter: roomAfter,
                                 gapThreshold: gapThreshold,
                                 gapEdge: gapEdge(pointsPerMinute: pointsPerMinute),
                                 gapLength: .init(gapLength),
                                 minimumTickSpacing: .init(minimumTickSpacing))
    }
}

/// How many points a minute takes: S, M, L like the zoom of a project plan.
enum ChartZoom: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var pointsPerMinute: Double {
        switch self {
        case .small: 0.5
        case .medium: 1
        case .large: 2
        }
    }

    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}

/// The plan itself, drawn along the axis the screen's shape asks for.
struct PlanChartView: View {
    let lanes: [PlanTimelineLane]
    let scale: PlanTimelineScale
    let now: Date
    /// The recipe's small picture for the lane header, by recipe name.
    let recipeImage: (String) -> Data?
    /// A tap on a bar or marker, with the step's key.
    let onTap: (String) -> Void
    let onDone: (String) -> Void
    let onShift: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = Double(geo.size.width)
            let height = Double(geo.size.height)
            // Taller than wide reads the plan top-down; wider than tall,
            // left to right.
            PlanChartBody(lanes: lanes, scale: scale, now: now, recipeImage: recipeImage,
                          onTap: onTap, onDone: onDone, onShift: onShift,
                          vertical: height >= width, width: width, height: height)
        }
    }
}

/// Every element is placed with `place`: `position` and `length` run with
/// time, `crossOffset` and `crossLength` across it — so the vertical and
/// the horizontal layout are the same code with the two directions swapped.
struct PlanChartBody: View {
    let lanes: [PlanTimelineLane]
    let scale: PlanTimelineScale
    let now: Date
    let recipeImage: (String) -> Data?
    let onTap: (String) -> Void
    let onDone: (String) -> Void
    let onShift: (String) -> Void
    /// Time runs down (lanes as columns) or to the right (lanes as rows).
    let vertical: Bool
    let width: Double
    let height: Double
    @Environment(\.colorScheme) var colorScheme

    private var contentLength: Double {
        Double(scale.length) + ChartMetrics.leadingInset + ChartMetrics.trailingPadding
    }

    var body: some View {
        if vertical {
            columns
        } else {
            rows
        }
    }

    // MARK: Vertical: axis on the left, lanes as columns

    private var columns: some View {
        let laneWidth = laneWidth(in: width)
        let count = Double(lanes.count)
        let contentWidth = ChartMetrics.axisThickness + count * laneWidth
            + ChartMetrics.laneSpacing * (count - 1) + 8

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                // The headers stay put while the plan scrolls down.
                HStack(spacing: ChartMetrics.laneSpacing) {
                    Color.clear.frame(width: ChartMetrics.axisThickness)
                    ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                        laneHeader(lane)
                            .frame(width: laneWidth, alignment: .leading)
                    }
                }
                .frame(width: contentWidth, height: ChartMetrics.laneHeaderHeight, alignment: .leading)
                ScrollView(.vertical) {
                    chart(crossExtent: contentWidth, laneCross: laneWidth)
                        .frame(width: contentWidth, height: contentLength, alignment: .topLeading)
                }
                .frame(width: contentWidth, height: max(0, height - ChartMetrics.laneHeaderHeight))
            }
            .frame(width: max(contentWidth, width), alignment: .leading)
        }
    }

    private func laneWidth(in width: Double) -> Double {
        let count = Double(lanes.count)
        let available = width - ChartMetrics.axisThickness - ChartMetrics.laneSpacing * (count - 1) - 8
        return min(ChartMetrics.maximumLaneWidth, max(ChartMetrics.minimumLaneWidth, available / count))
    }

    // MARK: Horizontal: axis on top, lanes as rows

    private var rows: some View {
        let count = Double(lanes.count)
        let contentHeight = ChartMetrics.axisThickness + count * ChartMetrics.laneHeight
            + ChartMetrics.laneSpacing * (count - 1) + 8

        return ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                // The headers stay put while the plan scrolls sideways.
                VStack(alignment: .leading, spacing: ChartMetrics.laneSpacing) {
                    Color.clear.frame(height: ChartMetrics.axisThickness)
                    ForEach(Array(lanes.enumerated()), id: \.offset) { _, lane in
                        laneHeader(lane)
                            .frame(height: ChartMetrics.laneHeight, alignment: .leading)
                    }
                }
                .frame(width: ChartMetrics.laneHeaderWidth, height: contentHeight, alignment: .topLeading)
                ScrollView(.horizontal) {
                    chart(crossExtent: contentHeight, laneCross: ChartMetrics.laneHeight)
                        .frame(width: contentLength, height: contentHeight, alignment: .topLeading)
                }
                .frame(width: max(0, width - ChartMetrics.laneHeaderWidth), height: contentHeight)
            }
            .frame(height: max(contentHeight, height), alignment: .top)
        }
    }

    // MARK: The drawing, shared

    /// Ticks, lanes, the collapsed night, the now line and the axis labels.
    /// `crossExtent` is the content's size across time, `laneCross` one
    /// lane's.
    private func chart(crossExtent: Double, laneCross: Double) -> some View {
        ZStack(alignment: .topLeading) {
            tickLines(crossOffset: ChartMetrics.axisThickness,
                      crossLength: crossExtent - ChartMetrics.axisThickness)
            ForEach(Array(lanes.enumerated()), id: \.offset) { index, lane in
                laneContent(lane,
                            crossOffset: ChartMetrics.axisThickness
                                + Double(index) * (laneCross + ChartMetrics.laneSpacing),
                            crossLength: laneCross)
            }
            // The collapsed night lies over the bars it shortens.
            gapBands(crossLength: crossExtent)
            nowLine(crossLength: crossExtent)
            axisLabels()
        }
    }

    private func point(of date: Date) -> Double {
        Double(scale.position(of: date))
    }

    // MARK: Placement

    /// Places a view: along the time axis at `position` for `length`, across
    /// it at `crossOffset` for `crossLength`.
    private func place<Content: View>(_ content: Content, position: Double, length: Double,
                                      crossOffset: Double, crossLength: Double) -> some View {
        let position = position + ChartMetrics.leadingInset
        return content
            .frame(width: vertical ? crossLength : length, height: vertical ? length : crossLength)
            .offset(x: vertical ? crossOffset : position, y: vertical ? position : crossOffset)
    }

    // MARK: Axis

    private func gapBands(crossLength: Double) -> some View {
        ForEach(Array(scale.gaps.enumerated()), id: \.offset) { _, gap in
            place(gapBand(gap), position: Double(gap.position), length: Double(gap.length),
                  crossOffset: 0, crossLength: crossLength)
        }
    }

    /// The collapsed night: striped, with what it skips written across it
    /// (along the band when it stands, turned when it lies).
    private func gapBand(_ gap: PlanTimelineScale.Gap) -> some View {
        let hours = Int((gap.end.timeIntervalSince(gap.start) / 3600).rounded())
        let label = Text(verbatim: "\(PlanText.time(gap.start)) – \(PlanText.time(gap.end)) · \(hours) h")
            .font(AppFont.size(11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
        return ZStack {
            StripedBackground()
            if vertical {
                label
            } else {
                label.rotationEffect(.degrees(-90))
            }
        }
    }

    private func tickLines(crossOffset: Double, crossLength: Double) -> some View {
        ForEach(Array(scale.ticks.enumerated()), id: \.offset) { _, tick in
            place(Rectangle().fill(Color.secondary.opacity(0.22)),
                  position: Double(tick.position), length: 1, crossOffset: crossOffset, crossLength: crossLength)
        }
    }

    /// The time at every tick, with the day on the first tick of a day. A
    /// tick right at the now line gives way to its "Jetzt".
    private func axisLabels() -> some View {
        let nowPoint = now >= scale.start && now <= scale.end ? point(of: now) : -Double.infinity
        let margin = vertical ? 18.0 : 36.0
        return ForEach(Array(scale.ticks.filter { abs(Double($0.position) - nowPoint) >= margin }.enumerated()), id: \.offset) { _, tick in
            place(VStack(alignment: vertical ? .trailing : .center, spacing: 0) {
                      if tick.startsDay {
                          Text(verbatim: PlanText.day(tick.date))
                              .font(AppFont.size(10, weight: .semibold))
                      }
                      Text(verbatim: PlanText.time(tick.date))
                          .font(AppFont.size(11))
                  }
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .trailing : .center)
                  .padding(.trailing, vertical ? 6 : 0),
                  position: Double(tick.position) - (vertical ? 15 : 32), length: vertical ? 30 : 64,
                  crossOffset: 0, crossLength: ChartMetrics.axisThickness)
        }
    }

    /// The red line of the present moment, with "Jetzt" on the axis.
    @ViewBuilder private func nowLine(crossLength: Double) -> some View {
        if now >= scale.start, now <= scale.end {
            let position = point(of: now)
            place(Rectangle().fill(Color.red), position: position - 1, length: 2,
                  crossOffset: 0, crossLength: crossLength)
            place(Text("Jetzt")
                      .font(AppFont.size(10, weight: .semibold))
                      .foregroundStyle(Color.red)
                      .lineLimit(1)
                      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .trailing : .bottomLeading)
                      .padding(.trailing, vertical ? 6 : 0),
                  position: position + 2, length: vertical ? 14 : 40,
                  crossOffset: 0, crossLength: ChartMetrics.axisThickness)
        }
    }

    // MARK: Lanes

    private func laneHeader(_ lane: PlanTimelineLane) -> some View {
        HStack(spacing: 6) {
            RowThumbnail(data: recipeImage(lane.recipeName), edge: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: lane.recipeName)
                    .font(AppFont.size(14, weight: .semibold))
                    .lineLimit(1)
                Text(verbatim: "\(PlanText.dateTime(lane.start)) – \(PlanText.time(lane.end))")
                    .font(AppFont.size(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private func laneContent(_ lane: PlanTimelineLane, crossOffset: Double, crossLength: Double) -> some View {
        // The lane's own surface, from its first step to the finish.
        place(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45)),
              position: point(of: lane.start),
              length: max(Double(scale.length(from: lane.start, to: lane.end)), ChartMetrics.minimumInterval),
              crossOffset: crossOffset, crossLength: crossLength)

        ForEach(Array(lane.bars.enumerated()), id: \.offset) { _, bar in
            let position = point(of: bar.start)
            let length = max(Double(scale.length(from: bar.start, to: bar.end)), ChartMetrics.minimumInterval)
            // Bars that run at the same time share the lane side by side.
            let trackLength = (crossLength - ChartMetrics.trackSpacing * Double(bar.trackCount - 1)) / Double(bar.trackCount)
            let barCross = crossOffset + Double(bar.track) * (trackLength + ChartMetrics.trackSpacing)
            // The marker labels are stacked: each at its marker's line, but
            // never over the bar's first line nor over the label before it.
            // The bar's text may run down to the first of them.
            let markers = bar.markers.sorted { $0.date < $1.date }
            let markerLabels = stackedLabelPositions(markers.map { point(of: $0.date) }, floor: position + 20)
            let textLength = markerLabels.first.map { $0 - position } ?? length

            place(barView(bar, length: length, textLength: textLength),
                  position: position, length: length, crossOffset: barCross, crossLength: trackLength)

            ForEach(Array(zip(markers, markerLabels).enumerated()), id: \.offset) { _, pair in
                markerViews(pair.0, labelPosition: pair.1, crossOffset: barCross, crossLength: trackLength)
            }
        }

        // Loose markers and the finish share the lane's labels the same way.
        let loose = lane.markers.sorted { $0.date < $1.date }
        let loosePositions = loose.map { point(of: $0.date) } + [lane.finish].compactMap { $0 }.map { point(of: $0) }
        let looseLabels = stackedLabelPositions(loosePositions, floor: 0)

        ForEach(Array(zip(loose, looseLabels).enumerated()), id: \.offset) { _, pair in
            markerViews(pair.0, labelPosition: pair.1, crossOffset: crossOffset, crossLength: crossLength)
        }

        if let finish = lane.finish, let labelPosition = looseLabels.last {
            finishFlag(finish, labelPosition: labelPosition, crossOffset: crossOffset, crossLength: crossLength)
        }
    }

    /// Where a column of labels goes: each at its own position, but no
    /// higher than `floor` and never over the label before it. In a row
    /// the labels keep their positions; they sit in the lane's lower band
    /// and cannot stack.
    private func stackedLabelPositions(_ positions: [Double], floor: Double) -> [Double] {
        guard vertical else { return positions }
        var result: [Double] = []
        for position in positions {
            let previousEnd = result.last.map { $0 + ChartMetrics.labelHeight } ?? -Double.infinity
            result.append(max(position, floor, previousEnd))
        }
        return result
    }

    /// A step as a bar: its colour says what kind of step it is, the text
    /// its time and instruction. Tapping opens the detail; a long press
    /// offers done and shift, as the list's row does. A short bar in a row
    /// has room for its time at most.
    private func barView(_ bar: PlanTimelineBar, length: Double, textLength: Double) -> some View {
        let lines = vertical ? max(1, Int((textLength - 6) / ChartMetrics.barLineHeight)) : 2
        let showsTime = vertical || length >= 44
        let showsText = vertical || length >= 90
        let text = showsText ? "\(PlanText.time(bar.start))  \(bar.entry.instruction)" : PlanText.time(bar.start)
        return stepButton(bar.entry) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(bar.kind.fill(colorScheme))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5))
                if showsTime {
                    Text(verbatim: text)
                        .font(AppFont.size(12))
                        .foregroundStyle(Color.primary)
                        .lineLimit(lines)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// A sub-step inside its parent's bar, or a step without a duration: a
    /// line across the lane with the time and text beside it. In a column
    /// the text follows the time; in a row the lower band only has room for
    /// the time — the instruction is in the detail.
    @ViewBuilder private func markerViews(_ marker: PlanTimelineMarker, labelPosition: Double,
                                          crossOffset: Double, crossLength: Double) -> some View {
        let position = point(of: marker.date)
        place(Rectangle().fill(Palette.accent(colorScheme).opacity(0.8)),
              position: position - 1, length: 2, crossOffset: crossOffset, crossLength: crossLength)
        if vertical {
            place(stepButton(marker.entry) {
                      Text(verbatim: "\(PlanText.time(marker.date))  \(marker.entry.instruction)")
                          .font(AppFont.size(11))
                          .foregroundStyle(Color.primary)
                          .lineLimit(1)
                          .padding(.horizontal, 5)
                          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                  },
                  position: labelPosition + 2, length: ChartMetrics.labelHeight - 1,
                  crossOffset: crossOffset, crossLength: crossLength)
        } else if crossLength >= 40 {
            // In a row the label sits in the lower third, under the bar's
            // text — when the row is not shared and still has a lower third.
            place(stepButton(marker.entry) {
                      Text(verbatim: PlanText.time(marker.date))
                          .font(AppFont.size(10))
                          .foregroundStyle(Color.primary)
                          .lineLimit(1)
                          .padding(.horizontal, 5)
                          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                  },
                  position: position + 1, length: 44,
                  crossOffset: crossOffset + crossLength - 18, crossLength: 16)
        }
    }

    /// "Backvorgang ist beendet": flagged at the plan's end. SkipUI has no
    /// checkered flag symbol, so a tick stands in.
    @ViewBuilder private func finishFlag(_ finish: Date, labelPosition: Double, crossOffset: Double, crossLength: Double) -> some View {
        let position = point(of: finish)
        place(Rectangle().fill(Palette.accent(colorScheme)),
              position: position - 1, length: 2, crossOffset: crossOffset, crossLength: crossLength)
        let label = HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
            Text(verbatim: PlanText.time(finish))
        }
        .font(AppFont.size(11, weight: .semibold))
        .foregroundStyle(Palette.accent(colorScheme))
        .lineLimit(1)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        if vertical {
            place(label, position: labelPosition + 2, length: ChartMetrics.labelHeight,
                  crossOffset: crossOffset, crossLength: crossLength)
        } else {
            place(label, position: position + 2, length: 80, crossOffset: crossOffset, crossLength: 18)
        }
    }

    /// Opens the step's detail on a tap; a long press offers done and shift.
    private func stepButton<Content: View>(_ entry: PlanTimelineEntry, @ViewBuilder label: () -> Content) -> some View {
        let key = entry.id.base as? String ?? ""
        return Button {
            onTap(key)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onDone(key)
            } label: {
                Label("Erledigt", systemImage: "checkmark")
            }
            Button {
                onShift(key)
            } label: {
                Label("Verschieben", systemImage: "calendar")
            }
        }
    }
}

/// Diagonal stripes over a faint fill, the mark of a collapsed stretch.
/// SkipUI's Canvas draws nothing on Android, so the stripes are a gradient
/// with hard stops.
struct StripedBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let stripe = Color.secondary.opacity(0.18)
        let clear = Color.clear
        var stops: [Gradient.Stop] = []
        let count = 24
        for index in 0..<count {
            let from = Double(index) / Double(count)
            let to = Double(index + 1) / Double(count)
            let middle = (from + to) / 2
            stops.append(Gradient.Stop(color: clear, location: from))
            stops.append(Gradient.Stop(color: clear, location: middle))
            stops.append(Gradient.Stop(color: stripe, location: middle))
            stops.append(Gradient.Stop(color: stripe, location: to))
        }
        return ZStack {
            Rectangle().fill(Palette.backgroundTop(colorScheme).opacity(0.85))
            LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

extension PlanTimelineKind {
    /// Light tints that keep the primary text readable on them, in both
    /// appearances — the iPhone's colours.
    func fill(_ scheme: ColorScheme) -> Color {
        switch self {
        case .mix:   scheme == .dark ? Color(red: 0.22, green: 0.38, blue: 0.24) : Color(red: 0.80, green: 0.90, blue: 0.78)
        case .rest:  scheme == .dark ? Color(red: 0.33, green: 0.30, blue: 0.27) : Color(red: 0.88, green: 0.85, blue: 0.80)
        case .fold:  scheme == .dark ? Color(red: 0.18, green: 0.36, blue: 0.38) : Color(red: 0.76, green: 0.88, blue: 0.88)
        case .shape: scheme == .dark ? Color(red: 0.34, green: 0.28, blue: 0.44) : Color(red: 0.86, green: 0.82, blue: 0.92)
        case .oven:  scheme == .dark ? Color(red: 0.20, green: 0.30, blue: 0.48) : Color(red: 0.80, green: 0.86, blue: 0.96)
        case .bake:  scheme == .dark ? Color(red: 0.52, green: 0.36, blue: 0.12) : Color(red: 0.98, green: 0.88, blue: 0.66)
        case .other: scheme == .dark ? Color(red: 0.30, green: 0.27, blue: 0.24) : Color(red: 0.92, green: 0.90, blue: 0.86)
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .mix:   "Mischen"
        case .rest:  "Ruhen"
        case .fold:  "Falten"
        case .shape: "Formen"
        case .oven:  "Ofen"
        case .bake:  "Backen"
        case .other: "Sonstiges"
        }
    }
}

/// What the colours mean, in the order a bake runs, and the zoom.
struct ChartControls: View {
    @Binding var zoom: ChartZoom
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach([PlanTimelineKind.mix, .rest, .shape, .bake], id: \.self) { kind in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(kind.fill(colorScheme)).frame(width: 10, height: 10)
                        Text(kind.title)
                    }
                }
            }
            .font(AppFont.size(11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer()
            Picker("Zoom", selection: $zoom) {
                ForEach(ChartZoom.allCases) { zoom in
                    Text(verbatim: zoom.title).tag(zoom)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
