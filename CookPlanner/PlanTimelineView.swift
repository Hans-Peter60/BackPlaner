//
//  PlanTimelineView.swift
//  CookPlanner
//
//  The plan as a timeline, the way BakePlanner draws a bake on the iPhone:
//  time runs down on the left, every component is a column, and every step
//  is a bar from its start to its end. The hands-on part is solid, the
//  part that runs on its own (pot, oven, resting) hatched, so it shows at
//  a glance what runs in parallel and where the hands are needed. Steps of
//  one component that overlap stand side by side (KitchenTimelineLayout).
//  In the cook mode a red line marks now and done steps fade.
//

import BakePlannerCore
import SwiftUI

struct PlanTimelineView: View {

    let layout: KitchenTimelineLayout
    /// Minutes since the start, with seconds as a fraction; nil on the plan.
    var now: Double? = nil
    /// Steps already done, drawn faded.
    var finished: Set<String> = []

    @State private var width: CGFloat = 320
    @State private var selected: KitchenPlacement?
    /// Debug screenshots open one step's details at once.
    var initiallySelected: String? = nil

    private let axisWidth: CGFloat = 34
    private let headerHeight: CGFloat = 34
    private let minimumLaneWidth: CGFloat = 92
    /// A bar beside others is never narrower than this, so its words stay whole.
    private let minimumTrackWidth: CGFloat = 76
    private let laneSpacing: CGFloat = 4

    /// Fourteen points a minute, so a one-minute step still holds a line
    /// of small text.
    private let pointsPerMinute: CGFloat = 14

    /// Each lane as wide as its most parallel stretch needs; when all fit,
    /// they share the room that is left in proportion.
    private var laneWidths: [CGFloat] {
        let needed = layout.lanes.map { lane in
            max(minimumLaneWidth, CGFloat(lane.bars.map(\.tracks).max() ?? 1) * minimumTrackWidth)
        }
        let available = width - axisWidth - laneSpacing * CGFloat(needed.count)
        let total = needed.reduce(0, +)
        guard total > 0, total < available else { return needed }
        return needed.map { $0 * available / total }
    }

    private var laneOffsets: [CGFloat] {
        var x = axisWidth
        return laneWidths.map { width in
            defer { x += width + laneSpacing }
            return x
        }
    }

    private var chartWidth: CGFloat {
        axisWidth + laneWidths.reduce(0) { $0 + $1 + laneSpacing }
    }

    private var chartHeight: CGFloat {
        headerHeight + CGFloat(max(1, layout.makespan)) * pointsPerMinute + 8
    }

    private func y(_ minute: Double) -> CGFloat {
        headerHeight + CGFloat(minute) * pointsPerMinute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: chartWidth > width) {
                chart
                    .frame(width: chartWidth, height: chartHeight, alignment: .topLeading)
            }
            .scrollDisabled(chartWidth <= width)
            legend
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task {
            guard let id = initiallySelected else { return }
            try? await Task.sleep(for: .seconds(1))
            selected = layout.lanes.flatMap(\.bars).first { $0.id == id }?.placement
        }
    }

    private var chart: some View {
        ZStack(alignment: .topLeading) {
            // Minute lines and labels.
            ForEach(layout.ticks(every: 5), id: \.self) { minute in
                Rectangle()
                    .fill(Theme.subtitle.opacity(minute % 15 == 0 ? 0.28 : 0.12))
                    .frame(width: chartWidth - axisWidth, height: 1)
                    .offset(x: axisWidth, y: y(Double(minute)))
                Text(verbatim: "\(minute)′")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(Theme.subtitle)
                    .frame(width: axisWidth - 6, alignment: .trailing)
                    .offset(y: y(Double(minute)) - 7)
            }
            let widths = laneWidths
            let offsets = laneOffsets
            ForEach(Array(layout.lanes.enumerated()), id: \.element.id) { index, lane in
                let x = offsets[index]
                let laneWidth = widths[index]
                laneHeader(lane, color: Self.color(for: index))
                    .frame(width: laneWidth, height: headerHeight - 4)
                    .offset(x: x)
                ForEach(lane.bars) { bar in
                    barView(bar, laneWidth: laneWidth, color: Self.color(for: index))
                        .offset(x: x + CGFloat(bar.track) * laneWidth / CGFloat(bar.tracks),
                                y: y(Double(bar.placement.start)))
                }
            }
            if let now, now >= 0 {
                HStack(spacing: 0) {
                    Circle().fill(Theme.danger).frame(width: 7, height: 7)
                    Rectangle().fill(Theme.danger).frame(height: 2)
                }
                .frame(width: chartWidth - axisWidth + 4)
                .offset(x: axisWidth - 4, y: y(min(now, Double(layout.makespan))) - 3.5)
                .accessibilityLabel(Text("Jetzt"))
            }
        }
    }

    private func laneHeader(_ lane: KitchenTimelineLayout.Lane, color: Color) -> some View {
        Text(verbatim: lane.component.isEmpty ? String(localized: "Ohne Komponente") : lane.component)
            .font(Theme.bodyFont(12).weight(.semibold))
            .foregroundColor(Theme.cardTitle)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
    }

    private func barView(_ bar: KitchenTimelineLayout.Bar, laneWidth: CGFloat, color: Color) -> some View {
        let placement = bar.placement
        let width = laneWidth / CGFloat(bar.tracks) - 2
        let handsHeight = CGFloat(placement.handsEnd - placement.start) * pointsPerMinute
        let aloneHeight = CGFloat(placement.end - placement.handsEnd) * pointsPerMinute
        let height = max(6, handsHeight + aloneHeight - 2)
        let done = finished.contains(placement.id)
        return Button {
            selected = placement
        } label: {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if handsHeight > 0 {
                        Rectangle().fill(color.opacity(0.55))
                            .frame(height: handsHeight)
                    }
                    if aloneHeight > 0 {
                        Hatch(color: color)
                            .frame(height: max(0, aloneHeight - 2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: 1))
                VStack(alignment: .leading, spacing: 0) {
                    // Dark on the light solid and on the stripes alike.
                    Text(verbatim: placement.task.name)
                        .font(.system(size: height < 16 ? 10 : 11, weight: .semibold))
                        .lineLimit(max(1, Int(height / 13)))
                        .foregroundColor(Theme.cardTitle)
                    if height >= 30 {
                        HStack(spacing: 3) {
                            if let symbol = placement.task.stationSymbol {
                                Image(systemName: symbol)
                            }
                            Text(verbatim: "\(placement.start)–\(placement.end)′")
                        }
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Theme.cardTitle.opacity(0.8))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, height < 16 ? 0 : 2)
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .opacity(done ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { selected?.id == placement.id },
                                      set: { if !$0 { selected = nil } })) {
            StepDetail(placement: placement)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(Text(verbatim: "\(placement.task.name), \(placement.start)–\(placement.end)"))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.accentText.opacity(0.55)).frame(width: 16, height: 10)
                Text("Hände")
            }
            HStack(spacing: 5) {
                Hatch(color: Theme.accentText)
                    .frame(width: 16, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Text("läuft allein")
            }
            Spacer()
            Text("Tippen für Details")
        }
        .font(Theme.bodyFont(12))
        .foregroundColor(Theme.subtitle)
    }

    /// The components' colours, in turn.
    /// The components' colours, in turn; the printed plan uses the same.
    static let palette: [(red: Double, green: Double, blue: Double)] = [
        (0.80, 0.42, 0.16), (0.24, 0.52, 0.40), (0.30, 0.44, 0.70),
        (0.66, 0.30, 0.45), (0.55, 0.48, 0.20), (0.42, 0.36, 0.62),
    ]

    static func color(for index: Int) -> Color {
        let rgb = palette[index % palette.count]
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Diagonal stripes on a light ground: time that runs on its own.
private struct Hatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.14)))
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(color.opacity(0.45)), lineWidth: 1.5)
        }
    }
}

/// What a tapped bar says in full.
private struct StepDetail: View {
    let placement: KitchenPlacement

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: placement.task.name)
                .font(Theme.bodyFont(15).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !placement.task.component.isEmpty {
                Text(verbatim: placement.task.component)
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
            }
            Text("Minute \(placement.start) bis \(placement.end)")
                .font(Theme.bodyFont(13).monospacedDigit())
            if placement.task.handsMinutes > 0 {
                Label("\(placement.task.handsMinutes) Min. Hände", systemImage: "hand.raised.fill")
                    .font(Theme.bodyFont(13))
            }
            if placement.task.unattendedMinutes > 0 {
                Label("\(placement.task.unattendedMinutes) Min. allein", systemImage: placement.task.stationSymbol ?? "hourglass")
                    .font(Theme.bodyFont(13))
            }
            if let temperature = placement.task.ovenTemperature {
                Text("Ofen \(temperature) °C")
                    .font(Theme.bodyFont(13))
            }
        }
        .padding()
        // A fixed width and the height the text needs: a popover sizes to
        // its content, and with a flexible width the lines were cut off.
        .frame(width: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
