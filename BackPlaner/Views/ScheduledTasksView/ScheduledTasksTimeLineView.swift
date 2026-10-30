//
//  ScheduledTasksTimeLineView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 26.01.22.
//
//  The planned steps as a project plan: one lane per plan, a bar per step
//  as long as the step lasts, markers for the sub-steps inside it, hour
//  ticks, the night collapsed to a band, the finish as a flag and a line
//  for now. An iPhone in portrait draws the plan top-down — time axis on
//  the left, plans as columns — so reading and scrolling go the same way
//  as in the list; everything else draws it left to right with a row per
//  plan, the way a project plan is usually drawn. Both share
//  `PlanTimelineScale` and `PlanTimelineLane`; only the directions differ.
//

import BakePlannerCore
import SwiftUI
import CoreData

/// The sizes to tune once the plan has been seen on a device.
private enum TimelineMetrics {
    /// The time axis: its width when it stands on the left (portrait), its
    /// height when it lies on top.
    static let axisThickness: CGFloat = 54
    /// The lane headers (image and recipe name): the row height in
    /// portrait, the column width otherwise.
    static let laneHeaderHeight: CGFloat = 48
    static let laneHeaderWidth: CGFloat = 132
    /// Lanes as columns (portrait) are at least this wide and at most that;
    /// fewer lanes share the screen width, and on an iPad one lane does not
    /// stretch across the whole screen.
    static let minimumLaneWidth: CGFloat = 150
    static let maximumLaneWidth: CGFloat = 440
    /// Lanes as rows are this high.
    static let laneHeight: CGFloat = 64
    static let laneSpacing: CGFloat = 6
    /// Between two bars that run at the same time and share a lane.
    static let trackSpacing: CGFloat = 3
    /// The card with a step's full text, shown on hover and in the long-press preview.
    static let tooltipWidth: CGFloat = 260
    /// The scale: how long an idle stretch has to be before it collapses,
    /// the band it collapses to, the smallest distance between two step
    /// boundaries, and the least room between two axis labels.
    static let gapThreshold: TimeInterval = 4 * 3600
    static let gapLength: CGFloat = 44
    /// What stays at full scale on either side of a collapsed night: half
    /// an hour, but never less than a line of bar text, so a rest that
    /// begins shortly before the night keeps its first line visible.
    static let gapEdgeMinutes: CGFloat = 30
    static let gapEdgePoints: CGFloat = 26

    static func gapEdge(pointsPerMinute: CGFloat) -> TimeInterval {
        TimeInterval(max(gapEdgeMinutes, gapEdgePoints / pointsPerMinute) * 60)
    }
    static let minimumInterval: CGFloat = 26
    /// A bar with a marker in its first minute: one line for the bar, one
    /// for the marker.
    static let roomForStartMarker: CGFloat = 40
    /// One line of marker or finish label in a column.
    static let labelHeight: CGFloat = 16
    /// One line of bar text (Avenir at 12 points), for how many lines fit
    /// before the first marker label.
    static let barLineHeight: CGFloat = 16.5
    static let minimumTickSpacing: CGFloat = 40
    /// Room before the first step, so its axis label is not cut off by the
    /// pinned header, and after the last one, for the finish flag.
    static let leadingInset: CGFloat = 24
    static let trailingPadding: CGFloat = 36

    static func roomAfter(for lanes: [PlanTimelineLane]) -> [Date: CGFloat] {
        Dictionary(lanes.flatMap(\.startsWithMarker).map { ($0, roomForStartMarker) }, uniquingKeysWith: max)
    }
}

/// How many points a minute takes.
private enum TimelineZoom: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: Self { self }

    var pointsPerMinute: CGFloat {
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

struct ScheduledTasksTimeLineView: View {

    @Environment(\.managedObjectContext) private var managedObjectContext
    /// Handed on to the bake mode, which looks up public recipes through it.
    @EnvironmentObject var model: RecipeModel

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    private var allNextSteps: FetchedResults<NextStep>

    @State private var showingBakeMode = false
    @State private var zoom = TimelineZoom.medium
    @State private var shiftSelection: ScheduledStepShiftSelection?
    @State private var showingShiftError = false
    @State private var shiftErrorMessage = ""
    @State private var doneHaptic = false

    /// Automatically-queued steps more than `RecurringBakePlanner.visibilityLeadTime`
    /// away are left out, so a periodic plan doesn't sit on the timeline for days.
    private var nextSteps: [NextStep] { allNextSteps.filter { $0.isVisible() } }

    private var lanes: [PlanTimelineLane] {
        PlanTimelineLane.lanes(from: nextSteps.map { step in
            PlanTimelineEntry(id: step.objectID, recipeName: step.recipeName, planID: step.planID,
                              instruction: step.instruction, step: step.step,
                              date: step.date, duration: step.duration)
        })
    }

    var body: some View {
        Group {
            let lanes = self.lanes
            if lanes.isEmpty {
                ContentUnavailableView(
                    "Keine geplanten Schritte",
                    systemImage: "calendar",
                    description: Text("Setze Erinnerungen in der Backanleitung eines Rezepts.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let scale = PlanTimelineScale(boundaries: lanes.flatMap(\.boundaries),
                                              pointsPerMinute: zoom.pointsPerMinute,
                                              minimumInterval: TimelineMetrics.minimumInterval,
                                              roomAfter: TimelineMetrics.roomAfter(for: lanes),
                                              gapThreshold: TimelineMetrics.gapThreshold,
                                              gapEdge: TimelineMetrics.gapEdge(pointsPerMinute: zoom.pointsPerMinute),
                                              gapLength: TimelineMetrics.gapLength,
                                              minimumTickSpacing: TimelineMetrics.minimumTickSpacing)
                VStack(spacing: 0) {
                    controls
                    // Taller than wide — an iPhone or iPad held upright, the
                    // Duo's inner display — reads the plan top-down; wider
                    // than tall, left to right.
                    GeometryReader { geo in
                        PlanTimelineChart(lanes: lanes, scale: scale,
                                          axis: geo.size.height >= geo.size.width ? .vertical : .horizontal,
                                          recipeImage: fetchRecipeImage(name:),
                                          onDone: markDone(stepID:),
                                          onShift: beginShifting(stepID:))
                    }
                }
                // The same kitchen view the list offers, as a round Liquid Glass
                // button floating over the plan. The timeline has no filter,
                // so the bake mode shows every planned step.
                .safeAreaBar(edge: .bottom, alignment: .trailing) {
                    Button {
                        showingBakeMode = true
                    } label: {
                        Image(systemName: "oven.fill")
                            .font(.title2.weight(.semibold))
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accentTop)
                    .accessibilityLabel("Backmodus starten")
                    .accessibilityIdentifier("timeline.bakeMode")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .warmBackground()
        .navigationTitle("Geplante nächste Schritte")
        .navigationDestination(for: NSManagedObjectID.self) { stepID in
            ScheduledTaskDetailView(stepID: stepID)
        }
        .fullScreenCover(isPresented: $showingBakeMode) {
            BakeModeView(planFilter: nil)
                .environment(\.managedObjectContext, managedObjectContext)
                .environmentObject(model)
        }
        .sheet(item: $shiftSelection) { selection in
            ScheduledStepShiftSheet(
                recipeName: selection.recipeName,
                instruction: selection.instruction,
                date: selection.date
            ) { minutes, includeFollowing in
                shiftSelection = nil
                performShift(stepID: selection.id, byMinutes: minutes, includeFollowing: includeFollowing)
            }
            .presentationDetents([.large])
        }
        .alert("Verschieben nicht möglich", isPresented: $showingShiftError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shiftErrorMessage)
        }
        .sensoryFeedback(.success, trigger: doneHaptic)
    }

    /// The scale, S/M/L like the zoom of a project plan.
    private var controls: some View {
        HStack {
            legend
            Spacer()
            Picker("Zoom", selection: $zoom) {
                ForEach(TimelineZoom.allCases) { zoom in
                    Text(verbatim: zoom.title).tag(zoom)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// What the colours mean, in the order a bake runs.
    private var legend: some View {
        HStack(spacing: 8) {
            ForEach([PlanTimelineKind.mix, .rest, .shape, .bake], id: \.self) { kind in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(kind.fill).frame(width: 10, height: 10)
                    Text(kind.title)
                }
            }
        }
        .font(Theme.bodyFont(11))
        .foregroundColor(Theme.subtitle)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Actions

    private func step(with stepID: NSManagedObjectID) -> NextStep? {
        allNextSteps.first { $0.objectID == stepID }
    }

    /// Done and deleted are the same removal: the step leaves the plan
    /// together with its reminder.
    private func markDone(stepID: NSManagedObjectID) {
        guard let step = step(with: stepID) else { return }
        NotificationActions.cancelPendingNotification(for: step)
        managedObjectContext.delete(step)
        do {
            try managedObjectContext.save()
            doneHaptic.toggle()
        } catch {
            managedObjectContext.rollback()
            AppLog.persistence.error("Could not delete next step")
        }
    }

    private func beginShifting(stepID: NSManagedObjectID) {
        guard let step = step(with: stepID) else { return }
        shiftSelection = ScheduledStepShiftSelection(
            id: step.objectID,
            recipeName: step.recipeName,
            instruction: step.instruction,
            date: step.date
        )
    }

    private func performShift(stepID: NSManagedObjectID, byMinutes minutes: Int, includeFollowing: Bool) {
        guard let step = step(with: stepID) else {
            shiftErrorMessage = String(localized: "Der ausgewählte Schritt wurde nicht gefunden.")
            showingShiftError = true
            return
        }
        NotificationActions.shiftScheduledStep(step, byMinutes: minutes, includeFollowing: includeFollowing) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    shiftErrorMessage = error.localizedDescription
                    showingShiftError = true
                }
            }
        }
    }

    func fetchRecipeImage(name: String) -> Data? {
        recipes.first { $0.name.contains(name) }?.image
    }
}

// MARK: - Chart

/// The plan itself, drawn along `axis`. Every element is placed with
/// `place(_:position:length:crossOffset:crossLength:)`: `position` and
/// `length` run with time, `crossOffset` and `crossLength` across it — so
/// the vertical and the horizontal layout are the same code with the two
/// directions swapped.
private struct PlanTimelineChart: View {

    let lanes: [PlanTimelineLane]
    let scale: PlanTimelineScale
    let axis: Axis
    let recipeImage: (String) -> Data?
    let onDone: (NSManagedObjectID) -> Void
    let onShift: (NSManagedObjectID) -> Void

    @Environment(\.locale) private var locale

    /// The step under the pointer, with where its bar or marker is drawn,
    /// so the card with its full text can be laid over the plan there.
    @State private var hovered: TooltipAnchor?

    var body: some View {
        GeometryReader { geo in
            // Re-evaluated once a minute so the "now" line keeps moving.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                switch axis {
                case .vertical:   vertical(in: geo.size, now: context.date)
                case .horizontal: horizontal(in: geo.size, now: context.date)
                }
            }
        }
    }

    // MARK: Vertical: axis on the left, lanes as columns

    private func laneWidth(in size: CGSize) -> CGFloat {
        let count = CGFloat(lanes.count)
        let available = size.width - TimelineMetrics.axisThickness - TimelineMetrics.laneSpacing * (count - 1) - 8
        return min(TimelineMetrics.maximumLaneWidth, max(TimelineMetrics.minimumLaneWidth, available / count))
    }

    private func vertical(in size: CGSize, now: Date) -> some View {
        let laneWidth = laneWidth(in: size)
        let contentWidth = TimelineMetrics.axisThickness + CGFloat(lanes.count) * laneWidth
            + TimelineMetrics.laneSpacing * CGFloat(lanes.count - 1) + 8
        let contentLength = scale.length + TimelineMetrics.leadingInset + TimelineMetrics.trailingPadding

        return ScrollView(.horizontal, showsIndicators: false) {
            ScrollView(.vertical) {
                // Narrower than the screen (one lane on an iPad), the plan
                // stands centred; wider, it starts at the left and scrolls.
                LazyVStack(alignment: contentWidth < size.width ? .center : .leading, spacing: 0,
                           pinnedViews: [.sectionHeaders]) {
                    Section {
                        ZStack(alignment: .topLeading) {
                            tickLines(crossOffset: TimelineMetrics.axisThickness,
                                      crossLength: contentWidth - TimelineMetrics.axisThickness)
                            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                                laneContent(lane,
                                            crossOffset: TimelineMetrics.axisThickness
                                                + CGFloat(index) * (laneWidth + TimelineMetrics.laneSpacing),
                                            crossLength: laneWidth)
                            }
                            // The collapsed night lies over the bars it shortens.
                            gapBands(crossLength: contentWidth)
                            nowLine(now: now, crossLength: contentWidth)
                            axisLabels()
                            tooltip(contentCross: contentWidth, contentLength: contentLength)
                        }
                        .frame(width: contentWidth, height: contentLength, alignment: .topLeading)
                    } header: {
                        HStack(spacing: TimelineMetrics.laneSpacing) {
                            Color.clear.frame(width: TimelineMetrics.axisThickness)
                            ForEach(lanes) { lane in
                                laneHeader(lane)
                                    .frame(width: laneWidth, alignment: .leading)
                            }
                        }
                        .frame(width: contentWidth, height: TimelineMetrics.laneHeaderHeight, alignment: .leading)
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .frame(width: max(contentWidth, size.width), height: size.height)
        }
    }

    // MARK: Horizontal: axis on top, lanes as rows

    private func horizontal(in size: CGSize, now: Date) -> some View {
        let contentHeight = TimelineMetrics.axisThickness + CGFloat(lanes.count) * TimelineMetrics.laneHeight
            + TimelineMetrics.laneSpacing * CGFloat(lanes.count - 1) + 8
        let contentLength = scale.length + TimelineMetrics.leadingInset + TimelineMetrics.trailingPadding

        return ScrollView(.vertical) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ZStack(alignment: .topLeading) {
                            tickLines(crossOffset: TimelineMetrics.axisThickness,
                                      crossLength: contentHeight - TimelineMetrics.axisThickness)
                            ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                                laneContent(lane,
                                            crossOffset: TimelineMetrics.axisThickness
                                                + CGFloat(index) * (TimelineMetrics.laneHeight + TimelineMetrics.laneSpacing),
                                            crossLength: TimelineMetrics.laneHeight)
                            }
                            gapBands(crossLength: contentHeight)
                            nowLine(now: now, crossLength: contentHeight)
                            axisLabels()
                            tooltip(contentCross: contentHeight, contentLength: contentLength)
                        }
                        .frame(width: contentLength, height: contentHeight, alignment: .topLeading)
                    } header: {
                        VStack(alignment: .leading, spacing: TimelineMetrics.laneSpacing) {
                            Color.clear.frame(height: TimelineMetrics.axisThickness)
                            ForEach(lanes) { lane in
                                laneHeader(lane)
                                    .frame(height: TimelineMetrics.laneHeight, alignment: .leading)
                            }
                        }
                        .frame(width: TimelineMetrics.laneHeaderWidth, height: contentHeight, alignment: .topLeading)
                        .background(.ultraThinMaterial)
                    }
                }
            }
        }
    }

    // MARK: Placement

    /// Places a view: along the time axis at `position` for `length`, across
    /// it at `crossOffset` for `crossLength`.
    private func place<Content: View>(_ content: Content, position: CGFloat, length: CGFloat,
                                      crossOffset: CGFloat, crossLength: CGFloat) -> some View {
        let vertical = axis == .vertical
        let position = position + TimelineMetrics.leadingInset
        return content
            .frame(width: vertical ? crossLength : length, height: vertical ? length : crossLength)
            .offset(x: vertical ? crossOffset : position, y: vertical ? position : crossOffset)
    }

    // MARK: Axis

    @ViewBuilder private func gapBands(crossLength: CGFloat) -> some View {
        ForEach(Array(scale.gaps.enumerated()), id: \.offset) { _, gap in
            place(gapBand(gap), position: gap.position, length: gap.length, crossOffset: 0, crossLength: crossLength)
        }
    }

    /// The collapsed night: hatched, with what it skips written across it.
    private func gapBand(_ gap: PlanTimelineScale.Gap) -> some View {
        let from = gap.start.formatted(.dateTime.hour().minute().locale(locale))
        let to = gap.end.formatted(.dateTime.hour().minute().locale(locale))
        let hours = Duration.seconds(gap.end.timeIntervalSince(gap.start))
            .formatted(.units(allowed: [.hours], width: .narrow).locale(locale))
        let label = Text(verbatim: "\(from) – \(to) · \(hours)")
            .font(Theme.bodyFont(11))
            .foregroundColor(Theme.subtitle)
            .lineLimit(1)
            .fixedSize()
        return ZStack {
            HatchedBackground()
            if axis == .vertical {
                label
            } else {
                label.rotationEffect(.degrees(-90))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(from) – \(to) · \(hours)"))
    }

    @ViewBuilder private func tickLines(crossOffset: CGFloat, crossLength: CGFloat) -> some View {
        ForEach(Array(scale.ticks.enumerated()), id: \.offset) { _, tick in
            place(Rectangle().fill(Theme.subtitle.opacity(0.22)),
                  position: tick.position, length: 1, crossOffset: crossOffset, crossLength: crossLength)
        }
    }

    /// The time at every tick, with the weekday on the first tick of a day.
    @ViewBuilder private func axisLabels() -> some View {
        ForEach(Array(scale.ticks.enumerated()), id: \.offset) { _, tick in
            let label = VStack(alignment: axis == .vertical ? .trailing : .center, spacing: 0) {
                if tick.startsDay {
                    Text(tick.date, format: .dateTime.weekday(.abbreviated).day())
                        .font(Theme.brandFont(10))
                }
                Text(tick.date, format: .dateTime.hour().minute())
                    .font(Theme.bodyFont(11))
            }
            .foregroundColor(Theme.subtitle)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: axis == .vertical ? .trailing : .center)
            .padding(.trailing, axis == .vertical ? 6 : 0)
            .accessibilityElement(children: .combine)

            if axis == .vertical {
                place(label, position: tick.position - 15, length: 30,
                      crossOffset: 0, crossLength: TimelineMetrics.axisThickness)
            } else {
                place(label, position: tick.position - 32, length: 64,
                      crossOffset: 0, crossLength: TimelineMetrics.axisThickness)
            }
        }
    }

    /// The red line of the present moment, with "Jetzt" on the axis.
    @ViewBuilder private func nowLine(now: Date, crossLength: CGFloat) -> some View {
        if now >= scale.start, now <= scale.end {
            let position = scale.position(of: now)
            place(Rectangle().fill(Theme.danger), position: position - 1, length: 2,
                  crossOffset: 0, crossLength: crossLength)
            place(Text("Jetzt")
                    .font(Theme.brandFont(10))
                    .foregroundColor(Theme.danger)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: axis == .vertical ? .trailing : .bottom)
                    .padding(.trailing, axis == .vertical ? 6 : 0),
                  position: position + 2, length: 14,
                  crossOffset: 0, crossLength: TimelineMetrics.axisThickness)
        }
    }

    // MARK: Lanes

    private func laneHeader(_ lane: PlanTimelineLane) -> some View {
        HStack(spacing: 6) {
            Group {
                if let data = recipeImage(lane.recipeName), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Theme.subtitle)
                }
            }
            .frame(width: 30, height: 30)
            .clipped()
            .cornerRadius(6)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(lane.recipeName)
                    .font(Theme.brandFont(14))
                    .foregroundColor(Theme.cardTitle)
                    .lineLimit(1)
                Text("\(lane.start, format: .dateTime.weekday(.abbreviated).hour().minute()) – \(lane.end, format: .dateTime.hour().minute())")
                    .font(Theme.bodyFont(11))
                    .foregroundColor(Theme.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func laneContent(_ lane: PlanTimelineLane, crossOffset: CGFloat, crossLength: CGFloat) -> some View {
        // The lane's own surface, from its first step to the finish.
        place(RoundedRectangle(cornerRadius: 8).fill(Theme.card.opacity(0.5)),
              position: scale.position(of: lane.start),
              length: max(scale.length(from: lane.start, to: lane.end), TimelineMetrics.minimumInterval),
              crossOffset: crossOffset, crossLength: crossLength)

        ForEach(lane.bars) { bar in
            let position = scale.position(of: bar.start)
            let length = max(scale.length(from: bar.start, to: bar.end), TimelineMetrics.minimumInterval)
            // Bars that run at the same time share the lane side by side.
            let trackLength = (crossLength - TimelineMetrics.trackSpacing * CGFloat(bar.trackCount - 1)) / CGFloat(bar.trackCount)
            let barCross = crossOffset + CGFloat(bar.track) * (trackLength + TimelineMetrics.trackSpacing)
            // The marker labels are stacked: each sits at its marker's line,
            // but never over the bar's first line (a marker at the bar's
            // very start — the turn-down as the loaf goes in) nor over the
            // label before it. The bar's text may run down to the first of
            // them, not beyond.
            let markers = bar.markers.sorted { $0.date < $1.date }
            let markerLabels = stackedLabelPositions(markers.map { scale.position(of: $0.date) }, floor: position + 20)
            let textLength = markerLabels.first.map { $0 - position } ?? length
            let anchor = TooltipAnchor(entry: bar.entry, kind: bar.kind, recipeName: lane.recipeName,
                                       position: position, crossOffset: barCross)

            place(barView(bar, anchor: anchor, length: length, textLength: textLength),
                  position: position, length: length, crossOffset: barCross, crossLength: trackLength)

            ForEach(Array(zip(markers, markerLabels)), id: \.0.id) { marker, labelPosition in
                markerViews(marker, recipeName: lane.recipeName, labelPosition: labelPosition,
                            crossOffset: barCross, crossLength: trackLength)
            }
        }

        // Loose markers and the finish share the lane's labels the same way:
        // "Kühl lagern" at 17:20 and the finish at 17:20 one under the other.
        let loose = lane.markers.sorted { $0.date < $1.date }
        let loosePositions = loose.map { scale.position(of: $0.date) } + [lane.finish].compactMap { $0 }.map { scale.position(of: $0) }
        let looseLabels = stackedLabelPositions(loosePositions, floor: 0)

        ForEach(Array(zip(loose, looseLabels)), id: \.0.id) { marker, labelPosition in
            markerViews(marker, recipeName: lane.recipeName, labelPosition: labelPosition,
                        crossOffset: crossOffset, crossLength: crossLength)
        }

        if let finish = lane.finish, let labelPosition = looseLabels.last {
            finishFlag(finish, labelPosition: labelPosition, crossOffset: crossOffset, crossLength: crossLength)
        }
    }

    /// Where a row of labels goes: each at its own position, but no higher
    /// than `floor` and never over the label before it. In a row (time
    /// running sideways) the labels keep their positions; they sit in the
    /// lane's lower band and cannot stack.
    private func stackedLabelPositions(_ positions: [CGFloat], floor: CGFloat) -> [CGFloat] {
        guard axis == .vertical else { return positions }
        var result: [CGFloat] = []
        for position in positions {
            let previousEnd = result.last.map { $0 + TimelineMetrics.labelHeight } ?? -CGFloat.infinity
            result.append(max(position, floor, previousEnd))
        }
        return result
    }

    /// A step as a bar: its colour says what kind of step it is, the text
    /// its time and instruction. Tapping opens the detail; a long press
    /// offers done and shift, as the list's card does.
    private func barView(_ bar: PlanTimelineBar, anchor: TooltipAnchor, length: CGFloat, textLength: CGFloat) -> some View {
        let lines = axis == .vertical ? max(1, Int((textLength - 6) / TimelineMetrics.barLineHeight)) : 2
        // A short bar in a row has room for its time at most.
        let showsTime = axis == .vertical || length >= 44
        let showsText = axis == .vertical || length >= 90
        let time = Text(bar.start, format: .dateTime.hour().minute()).font(Theme.brandFont(12))
        let text = showsText
            ? Text("\(time) \(Text(bar.entry.instruction).font(Theme.bodyFont(12)))")
            : time
        let label = ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(bar.kind.fill)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.subtitle.opacity(0.25), lineWidth: 0.5))
            if showsTime {
                text
                .foregroundColor(Theme.cardTitle)
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(anchor.recipeName), \(bar.start.formatted(.dateTime.hour().minute().locale(locale))), \(bar.entry.instruction), \(Rational.displayHoursMinutes(bar.entry.duration))"))

        return stepLink(anchor, label: hoverable(label, anchor: anchor))
    }

    /// A sub-step inside its parent's bar, or a step without a duration: a
    /// line across the lane with the time and text beside it.
    @ViewBuilder private func markerViews(_ marker: PlanTimelineMarker, recipeName: String, labelPosition: CGFloat,
                                          crossOffset: CGFloat, crossLength: CGFloat) -> some View {
        let position = scale.position(of: marker.date)
        let anchor = TooltipAnchor(entry: marker.entry, kind: marker.kind, recipeName: recipeName,
                                   position: position, crossOffset: crossOffset)
        place(Rectangle().fill(Theme.accentText.opacity(0.8)),
              position: position - 1, length: 2, crossOffset: crossOffset, crossLength: crossLength)

        let time = Text(marker.date, format: .dateTime.hour().minute()).font(Theme.brandFont(axis == .vertical ? 11 : 10))
        // In a column the text follows the time; in a row the lower band
        // only has room for the time — the instruction is in the detail.
        let label = (axis == .vertical
                     ? Text("\(time) \(Text(marker.entry.instruction).font(Theme.bodyFont(11)))")
                     : time)
            .foregroundColor(Theme.cardTitle)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(recipeName), \(marker.date.formatted(.dateTime.hour().minute().locale(locale))), \(marker.entry.instruction)"))

        if axis == .vertical {
            place(stepLink(anchor, label: hoverable(label, anchor: anchor)),
                  position: labelPosition + 2, length: TimelineMetrics.labelHeight - 1,
                  crossOffset: crossOffset, crossLength: crossLength)
        } else if crossLength >= 40 {
            // In a row the label sits in the lower third, under the bar's
            // text — when the row is not shared and still has a lower third.
            place(stepLink(anchor, label: hoverable(label, anchor: anchor)),
                  position: position + 1, length: 44,
                  crossOffset: crossOffset + crossLength - 18, crossLength: 16)
        }
    }

    /// "Backvorgang ist beendet": a checkered flag at the plan's end.
    @ViewBuilder private func finishFlag(_ finish: Date, labelPosition: CGFloat, crossOffset: CGFloat, crossLength: CGFloat) -> some View {
        let position = scale.position(of: finish)
        place(Rectangle().fill(Theme.accentText),
              position: position - 1, length: 2, crossOffset: crossOffset, crossLength: crossLength)
        let label = HStack(spacing: 3) {
            Image(systemName: "flag.checkered")
            Text(finish, format: .dateTime.hour().minute())
        }
        .font(Theme.brandFont(11))
        .foregroundColor(Theme.accentText)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        if axis == .vertical {
            place(label, position: labelPosition + 2, length: TimelineMetrics.labelHeight,
                  crossOffset: crossOffset, crossLength: crossLength)
        } else {
            place(label, position: position + 2, length: 80, crossOffset: crossOffset, crossLength: 18)
        }
    }

    /// Opens the step's detail on a tap; a long press shows the step's full
    /// text and offers done and shift.
    @ViewBuilder private func stepLink<Content: View>(_ anchor: TooltipAnchor, label: Content) -> some View {
        if let stepID = anchor.entry.id.base as? NSManagedObjectID {
            NavigationLink(value: stepID) {
                label
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    onDone(stepID)
                } label: {
                    Label("Erledigt", systemImage: "checkmark")
                }
                Button {
                    onShift(stepID)
                } label: {
                    Label("Verschieben", systemImage: "clock.arrow.circlepath")
                }
            } preview: {
                stepCard(anchor)
                    .frame(width: TimelineMetrics.tooltipWidth + 20)
                    .padding(10)
            }
        } else {
            label
        }
    }

    // MARK: Full text on hover

    /// Remembers the step under the pointer (an iPad with a trackpad or
    /// mouse); touch has the long-press preview instead.
    private func hoverable<Content: View>(_ content: Content, anchor: TooltipAnchor) -> some View {
        content.onHover { inside in
            if inside {
                hovered = anchor
            } else if hovered == anchor {
                hovered = nil
            }
        }
    }

    /// The card with the hovered step's full text, laid over the plan at
    /// the step's bar and kept inside the content. It takes no pointer
    /// events itself, or it would hide the bar from the pointer that
    /// summoned it and flicker.
    @ViewBuilder private func tooltip(contentCross: CGFloat, contentLength: CGFloat) -> some View {
        if let anchor = hovered {
            let width = min(TimelineMetrics.tooltipWidth, contentCross, contentLength)
            let card = stepCard(anchor)
                .frame(width: width, alignment: .topLeading)
                .allowsHitTesting(false)
            if axis == .vertical {
                card.offset(x: min(anchor.crossOffset, max(0, contentCross - width)),
                            y: anchor.position + TimelineMetrics.leadingInset)
            } else {
                card.offset(x: min(anchor.position + TimelineMetrics.leadingInset, max(0, contentLength - width)),
                            y: anchor.crossOffset)
            }
        }
    }

    /// Recipe, time span and the full instruction of one step.
    private func stepCard(_ anchor: TooltipAnchor) -> some View {
        let entry = anchor.entry
        let timeFormat = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        let span = entry.duration > 0
            ? "\(entry.date.formatted(timeFormat)) – \(entry.end.formatted(timeFormat)) · \(Rational.displayHoursMinutes(entry.duration))"
            : entry.date.formatted(timeFormat)
        return VStack(alignment: .leading, spacing: 4) {
            Text(anchor.recipeName)
                .font(Theme.brandFont(12))
                .foregroundColor(Theme.subtitle)
            Text(verbatim: span)
                .font(Theme.brandFont(13))
                .foregroundColor(Theme.cardTitle)
            Text(entry.instruction)
                .font(Theme.bodyFont(13))
                .foregroundColor(Theme.cardTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(anchor.kind.fill, lineWidth: 2))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

/// A step and where it is drawn, for the card with its full text.
private struct TooltipAnchor: Equatable {
    let entry: PlanTimelineEntry
    let kind: PlanTimelineKind
    let recipeName: String
    let position: CGFloat
    let crossOffset: CGFloat
}

// MARK: - Appearance

private extension PlanTimelineKind {
    /// Light tints that keep `Theme.cardTitle` readable on them, in both
    /// appearances.
    var fill: Color {
        switch self {
        case .mix:   Theme.dynamic(light: Color(red: 0.80, green: 0.90, blue: 0.78), dark: Color(red: 0.22, green: 0.38, blue: 0.24))
        case .rest:  Theme.dynamic(light: Color(red: 0.88, green: 0.85, blue: 0.80), dark: Color(red: 0.33, green: 0.30, blue: 0.27))
        case .fold:  Theme.dynamic(light: Color(red: 0.76, green: 0.88, blue: 0.88), dark: Color(red: 0.18, green: 0.36, blue: 0.38))
        case .shape: Theme.dynamic(light: Color(red: 0.86, green: 0.82, blue: 0.92), dark: Color(red: 0.34, green: 0.28, blue: 0.44))
        case .oven:  Theme.dynamic(light: Color(red: 0.80, green: 0.86, blue: 0.96), dark: Color(red: 0.20, green: 0.30, blue: 0.48))
        case .bake:  Theme.dynamic(light: Color(red: 0.98, green: 0.88, blue: 0.66), dark: Color(red: 0.52, green: 0.36, blue: 0.12))
        case .other: Theme.dynamic(light: Color(red: 0.92, green: 0.90, blue: 0.86), dark: Color(red: 0.30, green: 0.27, blue: 0.24))
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

// MARK: - Previews

/// A rye bread mixed the evening before with an overnight rest, and a
/// baguette planned alongside: the plan on an iPhone in portrait and as a
/// project plan in landscape, without a store behind it.
private enum TimelinePreviewData {
    static var lanes: [PlanTimelineLane] {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 21, minute: 5, second: 0, of: Date()) ?? Date()
        func at(_ minutes: Int) -> Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
        func entry(_ step: Double, _ text: String, at minute: Int, _ duration: Int,
                   recipe: String = "Roggenbrot") -> PlanTimelineEntry {
            PlanTimelineEntry(id: "\(recipe)-\(step)", recipeName: recipe, planID: nil,
                              instruction: text, step: step, date: at(minute), duration: duration)
        }
        let rye = [
            entry(1, "Zutaten von Sauerteig abwiegen", at: -10, 10),
            entry(2, "Sauerteig bereiten, bei Raumtemperatur reifen lassen", at: 0, 720),
            entry(2.1, "Brühstück herstellen und abgedeckt quellen lassen", at: 5, 15),
            entry(3, "Hauptteig kneten", at: 720, 15),
            entry(4, "Bei Raumtemperatur reifen lassen", at: 735, 90),
            entry(4.1, "Teig dehnen und falten (nach 30 Minuten).", at: 765, 60),
            entry(4.2, "Teig dehnen und falten (nach 60 Minuten).", at: 795, 30),
            entry(5, "Teig rundwirken und in den Gärkorb legen", at: 825, 10),
            entry(6, "Oberfläche mit Mehl einstreichen. Ohne Abdeckung bei Raumtemperatur reifen lassen", at: 835, 60),
            entry(6.9, "Backofen anstellen (250 °C)", at: 880, 15),
            entry(7, "Bei 250 Grad fallend auf 220 Grad mit Dampf backen", at: 895, 20),
            entry(7.1, "Backofen auf 220 °C zurückdrehen", at: 895, 0),
            entry(8, "Dampf ablassen", at: 915, 40),
            entry(99, "Backvorgang ist beendet", at: 955, 0),
        ]
        let baguette = [
            entry(1, "Poolish ansetzen", at: 60, 10, recipe: "Baguette"),
            entry(2, "Poolish reifen lassen", at: 70, 660, recipe: "Baguette"),
            entry(3, "Hauptteig kneten", at: 730, 20, recipe: "Baguette"),
            entry(4, "Stockgare", at: 750, 120, recipe: "Baguette"),
            entry(5, "Formen und Stückgare", at: 870, 45, recipe: "Baguette"),
            entry(6, "Bei 250 °C mit Dampf backen", at: 915, 25, recipe: "Baguette"),
            entry(7, "Auf einem Gitter auskühlen lassen", at: 940, 0, recipe: "Baguette"),
            entry(99, "Backvorgang ist beendet", at: 940, 0, recipe: "Baguette"),
        ]
        return PlanTimelineLane.lanes(from: rye + baguette)
    }

    static func scale(pointsPerMinute: CGFloat) -> PlanTimelineScale {
        PlanTimelineScale(boundaries: lanes.flatMap(\.boundaries), pointsPerMinute: pointsPerMinute,
                          minimumInterval: TimelineMetrics.minimumInterval,
                          roomAfter: TimelineMetrics.roomAfter(for: lanes),
                          gapThreshold: TimelineMetrics.gapThreshold,
                          gapEdge: TimelineMetrics.gapEdge(pointsPerMinute: pointsPerMinute),
                          gapLength: TimelineMetrics.gapLength,
                          minimumTickSpacing: TimelineMetrics.minimumTickSpacing)
    }
}

#Preview("Hochformat", traits: .portrait) {
    PlanTimelineChart(lanes: TimelinePreviewData.lanes,
                      scale: TimelinePreviewData.scale(pointsPerMinute: 1),
                      axis: .vertical,
                      recipeImage: { _ in nil },
                      onDone: { _ in },
                      onShift: { _ in })
        .warmBackground()
}

#Preview("Hochformat, Maßstab S", traits: .portrait) {
    PlanTimelineChart(lanes: TimelinePreviewData.lanes,
                      scale: TimelinePreviewData.scale(pointsPerMinute: 0.5),
                      axis: .vertical,
                      recipeImage: { _ in nil },
                      onDone: { _ in },
                      onShift: { _ in })
        .warmBackground()
}

#Preview("Querformat", traits: .landscapeLeft) {
    PlanTimelineChart(lanes: TimelinePreviewData.lanes,
                      scale: TimelinePreviewData.scale(pointsPerMinute: 1),
                      axis: .horizontal,
                      recipeImage: { _ in nil },
                      onDone: { _ in },
                      onShift: { _ in })
        .warmBackground()
}

/// Diagonal stripes over a faint fill, the mark of a collapsed stretch.
private struct HatchedBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.backgroundTop.opacity(0.85)))
            var stripes = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 10
            }
            context.stroke(stripes, with: .color(Theme.subtitle.opacity(0.3)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
