import BakePlannerCore
import SwiftUI

/// The plan as a timeline, as on the iPhone (PlanTimelineView there): time
/// runs down on the left, every component is a column, every step a bar
/// from its start to its end. The hands-on part is solid, the part that
/// runs on its own (pot, oven, resting) striped. Steps of one component
/// that overlap stand side by side (KitchenTimelineLayout). In the cook
/// mode a red line marks now and done steps fade. A tapped bar shows its
/// details under the chart (Skip has no popovers).
struct PlanTimelineView: View {
    let layout: KitchenTimelineLayout
    /// Minutes since the start, with seconds as a fraction; nil on the plan.
    var now: Double? = nil
    /// Steps already done, drawn faded.
    var finished: Set<String> = []
    @State var selected: KitchenPlacement?
    @Environment(\.colorScheme) var colorScheme

    private let axisWidth: CGFloat = 34
    private let headerHeight: CGFloat = 34
    private let minimumLaneWidth: CGFloat = 92
    /// A bar beside others is never narrower than this, so its words stay whole.
    private let minimumTrackWidth: CGFloat = 76
    private let laneSpacing: CGFloat = 4
    /// Fourteen points a minute, so a one-minute step still holds a line.
    private let pointsPerMinute: CGFloat = 14

    /// Each lane as wide as its most parallel stretch needs; when all fit,
    /// they share the room that is left in proportion.
    private func laneWidths(in width: CGFloat) -> [CGFloat] {
        let needed = layout.lanes.map { lane in
            max(minimumLaneWidth, CGFloat(lane.bars.map(\.tracks).max() ?? 1) * minimumTrackWidth)
        }
        let available = width - axisWidth - laneSpacing * CGFloat(needed.count)
        let total = needed.reduce(0, +)
        guard total > 0, total < available else { return needed }
        return needed.map { $0 * available / total }
    }

    private var chartHeight: CGFloat {
        headerHeight + CGFloat(max(1, layout.makespan)) * pointsPerMinute + 8
    }

    private func y(_ minute: Double) -> CGFloat {
        headerHeight + CGFloat(minute) * pointsPerMinute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let widths = laneWidths(in: proxy.size.width)
                let chartWidth = axisWidth + widths.reduce(0) { $0 + $1 + laneSpacing }
                ScrollView(.horizontal, showsIndicators: chartWidth > proxy.size.width) {
                    chart(widths: widths, chartWidth: chartWidth)
                        .frame(width: chartWidth, height: chartHeight, alignment: .topLeading)
                }
            }
            .frame(height: chartHeight)
            legend
            if let selected {
                detail(selected)
            }
        }
    }

    private func chart(widths: [CGFloat], chartWidth: CGFloat) -> some View {
        var offsets: [CGFloat] = []
        var x = axisWidth
        for width in widths {
            offsets.append(x)
            x += width + laneSpacing
        }
        return ZStack(alignment: .topLeading) {
            // Minute lines and labels.
            ForEach(layout.ticks(every: 5), id: \.self) { minute in
                Rectangle()
                    .fill(Palette.subtitle(colorScheme).opacity(minute % 15 == 0 ? 0.28 : 0.12))
                    .frame(width: chartWidth - axisWidth, height: 1)
                    .offset(x: axisWidth, y: y(Double(minute)))
                Text(verbatim: "\(minute)′")
                    .font(.caption2)
                    .foregroundStyle(Palette.subtitle(colorScheme))
                    .frame(width: axisWidth - 6, alignment: .trailing)
                    .offset(y: y(Double(minute)) - 8)
            }
            ForEach(Array(layout.lanes.enumerated()), id: \.element.id) { index, lane in
                let color = Self.color(for: index)
                laneHeader(lane, color: color)
                    .frame(width: widths[index], height: headerHeight - 4)
                    .offset(x: offsets[index])
                ForEach(lane.bars) { bar in
                    barView(bar, laneWidth: widths[index], color: color)
                        .offset(x: offsets[index] + CGFloat(bar.track) * widths[index] / CGFloat(bar.tracks),
                                y: y(Double(bar.placement.start)))
                }
            }
            if let now, now >= 0 {
                HStack(spacing: 0) {
                    Circle().fill(Palette.danger(colorScheme)).frame(width: 7, height: 7)
                    Rectangle().fill(Palette.danger(colorScheme)).frame(height: 2)
                }
                .frame(width: chartWidth - axisWidth + 4)
                .offset(x: axisWidth - 4, y: y(min(now, Double(layout.makespan))) - 3.5)
                .accessibilityLabel(Text(String(localized: "Jetzt", bundle: .module)))
            }
        }
    }

    private func laneHeader(_ lane: KitchenTimelineLayout.Lane, color: Color) -> some View {
        Text(lane.component.isEmpty ? String(localized: "Ohne Komponente", bundle: .module) : lane.component)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.title(colorScheme))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.18)))
    }

    private func barView(_ bar: KitchenTimelineLayout.Bar, laneWidth: CGFloat, color: Color) -> some View {
        let placement = bar.placement
        let width = laneWidth / CGFloat(bar.tracks) - 2
        let handsHeight = CGFloat(placement.handsEnd - placement.start) * pointsPerMinute
        let aloneHeight = CGFloat(placement.end - placement.handsEnd) * pointsPerMinute
        let height = max(6, handsHeight + aloneHeight - 2)
        let done = finished.contains(placement.id)
        let isSelected = selected?.id == placement.id
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                if handsHeight > 0 {
                    Rectangle().fill(color.opacity(0.55))
                        .frame(height: min(handsHeight, height))
                }
                if aloneHeight > 0 {
                    ZStack {
                        Rectangle().fill(color.opacity(0.14))
                        Stripes().stroke(color.opacity(0.45), lineWidth: 1.5)
                    }
                    .frame(height: max(0, height - handsHeight))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: isSelected ? 2.5 : 1))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: placement.task.name)
                    .font(.system(size: height < 16 ? 10 : 11, weight: .semibold))
                    .lineLimit(max(1, Int(height / 14)))
                    .foregroundStyle(Palette.title(colorScheme))
                if height >= 32 {
                    Text(verbatim: "\(placement.start)–\(placement.end)′")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.title(colorScheme).opacity(0.8))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, height < 16 ? 0 : 2)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .opacity(done ? 0.35 : 1)
        .onTapGesture {
            selected = isSelected ? nil : placement
        }
        .accessibilityLabel(Text(verbatim: "\(placement.task.name), \(placement.start)–\(placement.end)"))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.accentText(colorScheme).opacity(0.55))
                    .frame(width: 16, height: 10)
                Text(String(localized: "Hände", bundle: .module))
            }
            HStack(spacing: 5) {
                ZStack {
                    Rectangle().fill(Palette.accentText(colorScheme).opacity(0.14))
                    Stripes().stroke(Palette.accentText(colorScheme).opacity(0.45), lineWidth: 1.5)
                }
                .frame(width: 16, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                Text(String(localized: "läuft allein", bundle: .module))
            }
            Spacer()
            Text(String(localized: "Tippen für Details", bundle: .module))
        }
        .font(.caption)
        .foregroundStyle(Palette.subtitle(colorScheme))
    }

    /// What a tapped bar says in full.
    private func detail(_ placement: KitchenPlacement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(placement.task.name)
                .font(.subheadline)
                .fontWeight(.semibold)
            if !placement.task.component.isEmpty {
                Text(placement.task.component)
                    .font(.caption)
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
            Text(String(localized: "Minute \(placement.start) bis \(placement.end)", bundle: .module))
                .font(.caption)
            if placement.task.handsMinutes > 0 {
                Text(String(localized: "\(placement.task.handsMinutes) Min. Hände", bundle: .module))
                    .font(.caption)
            }
            if placement.task.unattendedMinutes > 0 {
                Text(String(localized: "\(placement.task.unattendedMinutes) Min. allein", bundle: .module))
                    .font(.caption)
            }
            if let temperature = placement.task.ovenTemperature {
                Text(String(localized: "Ofen \(temperature) °C", bundle: .module))
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.accentText(colorScheme).opacity(0.08)))
        .onTapGesture { selected = nil }
    }

    /// The components' colours, in turn; the iPhone and the printed plan
    /// use the same.
    static let palette: [(red: Double, green: Double, blue: Double)] = [
        (0.80, 0.42, 0.16), (0.24, 0.52, 0.40), (0.30, 0.44, 0.70),
        (0.66, 0.30, 0.45), (0.55, 0.48, 0.20), (0.42, 0.36, 0.62),
    ]

    static func color(for index: Int) -> Color {
        let rgb = palette[index % palette.count]
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Diagonal stripes: time that runs on its own.
struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 7
        }
        return path
    }
}

/// The cook mode's timeline: where the run stands, with the red line at
/// now. Opened as a sheet from "Zeitachse"; it shows the moment it opened.
struct CookTimelineSheet: View {
    let layout: KitchenTimelineLayout
    let now: Double?
    let finished: Set<String>
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                PlanTimelineView(layout: layout, now: now, finished: finished)
                    .padding(16)
            }
            .navigationTitle(String(localized: "Zeitachse", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Fertig", bundle: .module)) { dismiss() }
                }
            }
        }
        .tint(Palette.accent(colorScheme))
    }
}
