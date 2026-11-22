//
//  CookHistoryView.swift
//  CookPlanner
//
//  Everything cooked, the way BakePlanner keeps its baking history: four
//  views — the list by month, a gallery of the photos, the hit list by
//  stars, the statistics — a search by dish and a lowest star rating. The
//  stopwatch records land here by themselves; "+" enters a dish cooked
//  without the stopwatch, or turns old photos into entries. A row opens
//  its record.
//

import BakePlannerCore
import Charts
import SwiftUI

enum CookHistoryLayout: String, CaseIterable, Identifiable {
    case list, gallery, hitList, statistics
    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .list: "Liste"
        case .gallery: "Galerie"
        case .hitList: "Hit-Liste"
        case .statistics: "Statistik"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .gallery: "square.grid.2x2"
        case .hitList: "trophy"
        case .statistics: "chart.bar.xaxis"
        }
    }
}

struct CookHistoryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var runLog = CookRunLog.shared
    @State private var shownRun: KitchenCookRun?
    @AppStorage("history.layout") private var layout = CookHistoryLayout.list
    @State private var searchText = ""
    @AppStorage("history.minimumRating") private var minimumRating = 0
    @State private var addingEntry = false
    @State private var importingPhotos = false

    /// The records the search and the stars leave, newest first.
    private var shownRuns: [KitchenCookRun] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        return runLog.runs.filter { run in
            (needle.isEmpty || run.dishName.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
                && (minimumRating == 0 || (run.rating ?? 0) >= minimumRating)
        }
    }

    /// The records by month, newest month first.
    private var months: [(month: Date, runs: [KitchenCookRun])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: shownRuns) {
            calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt
        }
        return grouped.keys.sorted(by: >).map { month in
            (month, grouped[month, default: []].sorted { $0.startedAt > $1.startedAt })
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Darstellung", selection: $layout) {
                    ForEach(CookHistoryLayout.allCases) { layout in
                        Image(systemName: layout.systemImage).accessibilityLabel(Text(layout.title)).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                Group {
                    if runLog.runs.isEmpty {
                        ContentUnavailableView {
                            Label("Noch nichts gekocht", systemImage: "stopwatch")
                        } description: {
                            Text("Wer im Kochmodus die Uhr startet und am Ende das Protokoll sichert, findet das Gericht hier – mit Sternen, Notiz und Foto. Ohne Stoppuhr Gekochtes trägst Du mit „+“ ein.")
                        } actions: {
                            Button("Gekocht eintragen") { addingEntry = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accentBottom)
                        }
                    } else if shownRuns.isEmpty {
                        ContentUnavailableView("Keine passenden Einträge", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Passe die Suche oder die Sterne an."))
                    } else {
                        switch layout {
                        case .list: list
                        case .gallery: gallery
                        case .hitList: hitList
                        case .statistics: statistics
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .searchable(text: $searchText, prompt: Text("Gericht suchen"))
            .navigationTitle(Text(layout.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Picker("Mindestbewertung", selection: $minimumRating) {
                            Text("Alle").tag(0)
                            ForEach(1...5, id: \.self) { stars in
                                Text("Ab \(stars) Sternen").tag(stars)
                            }
                        }
                    } label: {
                        Image(systemName: minimumRating > 0 ? "line.3.horizontal.decrease.circle.fill"
                                                            : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Gekocht eintragen", systemImage: "square.and.pencil") { addingEntry = true }
                        Button("Aus Fotos übernehmen", systemImage: "photo.stack") { importingPhotos = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Hinzufügen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $shownRun) { run in
                CookRunView(runID: run.id)
            }
            .sheet(isPresented: $addingEntry) {
                CookEntryAddView()
            }
            .sheet(isPresented: $importingPhotos) {
                CookPhotoImportView()
            }
        }
    }

    // MARK: List

    private var list: some View {
        List {
            ForEach(months, id: \.month) { group in
                Section {
                    ForEach(group.runs) { run in
                        Button {
                            shownRun = run
                        } label: {
                            row(run)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                runLog.delete(id: run.id)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(verbatim: group.month.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
    }

    private func row(_ run: KitchenCookRun) -> some View {
        HStack(spacing: 12) {
            RunThumbnail(run: run, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: run.dishName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(verbatim: run.startedAt.formatted(date: .abbreviated, time: .omitted))
                    if !run.isManualEntry {
                        Text(verbatim: KitchenCookRun.clockText(run.totalSeconds))
                            .monospacedDigit()
                    }
                    if let rating = run.rating {
                        StarsText(rating: rating)
                    }
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                if let note = run.note, !note.isEmpty {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: Gallery

    private var gallery: some View {
        let withPhotos = shownRuns.filter { $0.photoFileName != nil }
        return ScrollView {
            if withPhotos.isEmpty {
                ContentUnavailableView("Noch keine Fotos", systemImage: "photo",
                                       description: Text("Ein Foto hängst Du im Eintrag unter „Wie war’s?“ an."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                    ForEach(withPhotos) { run in
                        Button {
                            shownRun = run
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RunThumbnail(run: run, size: 110)
                                    .frame(maxWidth: .infinity)
                                Text(verbatim: run.dishName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .padding(4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.6)],
                                                               startPoint: .top, endPoint: .bottom))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: Hit list

    private var hitList: some View {
        let statistics = KitchenCookStatistics(runs: shownRuns)
        return List {
            if statistics.hitList.isEmpty {
                Text("Vergib im Eintrag Sterne, dann steht hier, was am besten ankam.")
                    .foregroundColor(.secondary)
            }
            ForEach(Array(statistics.hitList.enumerated()), id: \.element.id) { index, dish in
                HStack(spacing: 12) {
                    Text(verbatim: "\(index + 1).")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundColor(index < 3 ? Theme.accentText : .secondary)
                        .frame(width: 34, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: dish.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            if let average = dish.averageRating {
                                StarsText(rating: Int(average.rounded()))
                                Text(verbatim: average.formatted(.number.precision(.fractionLength(1))))
                            }
                            Text("\(dish.count)× gekocht")
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Statistics

    private var statistics: some View {
        let statistics = KitchenCookStatistics(runs: shownRuns)
        return List {
            Section {
                LabeledContent("Gekocht", value: "\(statistics.total)")
                LabeledContent("Verschiedene Gerichte", value: "\(statistics.dishCount)")
                if let average = statistics.averageRating {
                    LabeledContent("Sterne im Schnitt",
                                   value: average.formatted(.number.precision(.fractionLength(1))))
                }
                if let over = statistics.averageMinutesOverPlan {
                    LabeledContent("Gegen den Plan") {
                        Text(over >= 0.5 ? "\(Int(over.rounded())) Min. langsamer"
                             : over <= -0.5 ? "\(Int((-over).rounded())) Min. schneller" : "wie geplant")
                            .foregroundColor(over >= 0.5 ? Theme.warning : Theme.good)
                    }
                }
            } footer: {
                if statistics.timedRuns == 1 {
                    Text("„Gegen den Plan“ aus einem vollständigen Durchgang mit der Stoppuhr.")
                } else if statistics.timedRuns > 1 {
                    Text("„Gegen den Plan“ aus \(statistics.timedRuns) vollständigen Durchgängen mit der Stoppuhr.")
                }
            }
            Section("Die letzten zwölf Monate") {
                Chart(statistics.months) { month in
                    BarMark(x: .value("Monat", month.month, unit: .month), y: .value("Gekocht", month.count))
                        .foregroundStyle(Theme.accentText)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 160)
                .padding(.vertical, 6)
            }
            Section("Am häufigsten gekocht") {
                ForEach(statistics.mostCooked.prefix(5)) { dish in
                    LabeledContent {
                        Text("\(dish.count)×")
                    } label: {
                        Text(verbatim: dish.name)
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

/// The record's photo as a small square, or a fork and knife without one.
struct RunThumbnail: View {
    let run: KitchenCookRun
    let size: CGFloat

    var body: some View {
        Group {
            if let image = CookRunLog.shared.thumbnail(of: run) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(Theme.subtitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.subtitle.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 6))
        .accessibilityHidden(true)
    }
}

/// "★★★★☆" for a rating, read out as "4 von 5 Sternen".
struct StarsText: View {
    let rating: Int

    var body: some View {
        Text(verbatim: String(repeating: "★", count: max(0, min(5, rating)))
             + String(repeating: "☆", count: max(0, 5 - rating)))
            .font(.caption)
            .foregroundColor(Theme.accentText)
            .accessibilityLabel(Text("\(rating) von 5 Sternen"))
    }
}
