import BakePlannerCore
import SkipKit
import SwiftUI

/// The four ways "Gekocht" shows the records, as on the iPhone.
enum CookHistoryLayout: String, CaseIterable {
    case list, gallery, hitList, statistics

    var title: String {
        switch self {
        case .list: return String(localized: "Liste", bundle: .module)
        case .gallery: return String(localized: "Galerie", bundle: .module)
        case .hitList: return String(localized: "Hit-Liste", bundle: .module)
        case .statistics: return String(localized: "Statistik", bundle: .module)
        }
    }
}

/// "Gekocht": every cook on the stopwatch and every one entered by hand
/// (the iPhone's CookHistoryView): the list by month, a gallery of the
/// photos, the hit list by stars, the statistics; a search by dish and a
/// lowest star rating.
struct CookHistoryView: View {
    let library: CookLibrary
    @State var log = CookRunLog.shared
    @State var addsEntry = false
    @State var showsYearbook = false
    @State var searchText = ""
    @State var layout = CookHistoryLayout(rawValue: SettingsFile.text("history.layout") ?? "") ?? .list
    @State var minimumRating = SettingsFile.integer("history.minimumRating", default: 0)
    @Environment(\.colorScheme) var colorScheme

    /// The records the search and the stars leave, newest first.
    private var shownRuns: [KitchenCookRun] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        return log.runs.filter { run in
            (needle.isEmpty || run.dishName.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
                && (minimumRating == 0 || (run.rating ?? 0) >= minimumRating)
        }
    }

    /// The records by month, newest first.
    private var months: [RunMonth] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var groups: [Date: [KitchenCookRun]] = [:]
        for run in shownRuns {
            let parts = calendar.dateComponents([.year, .month], from: run.startedAt)
            let month = calendar.date(from: parts) ?? run.startedAt
            groups[month, default: []].append(run)
        }
        return groups.keys.sorted(by: >).map { RunMonth(month: $0, runs: groups[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            // Not under the safe area: the search field sits there, and the
            // warm ground would cover it (as in the dish list).
            WarmBackground()
            if log.runs.isEmpty {
                VStack(spacing: 10) {
                    Text(String(localized: "Noch nichts gekocht", bundle: .module))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.title(colorScheme))
                    Text(String(localized: "Wer im Kochmodus die Uhr startet und am Ende das Protokoll sichert, findet das Gericht hier – mit Sternen, Notiz und Foto. Ohne Stoppuhr Gekochtes trägst Du mit „+“ ein.", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                VStack(spacing: 0) {
                    Picker(String(localized: "Darstellung", bundle: .module), selection: $layout) {
                        ForEach(CookHistoryLayout.allCases, id: \.self) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .onChange(of: layout) { _, layout in
                        SettingsFile.set(layout.rawValue, forKey: "history.layout")
                    }
                    if shownRuns.isEmpty {
                        VStack(spacing: 8) {
                            Text(String(localized: "Keine passenden Einträge", bundle: .module))
                                .font(.headline)
                            Text(String(localized: "Passe die Suche oder die Sterne an.", bundle: .module))
                                .font(.subheadline)
                                .foregroundStyle(Palette.subtitle(colorScheme))
                        }
                        .padding(24)
                        .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        switch layout {
                        case .list: list
                        case .gallery: gallery
                        case .hitList: hitList
                        case .statistics: CookStatisticsView(runs: shownRuns)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "Gericht suchen", bundle: .module))
        .navigationTitle(String(localized: "Gekocht", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Skip's menus show no pickers: a button per choice, the
                // chosen one marked.
                Menu {
                    Button((minimumRating == 0 ? "✓ " : "") + String(localized: "Alle", bundle: .module)) {
                        setMinimumRating(0)
                    }
                    ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                        Button((minimumRating == stars ? "✓ " : "") + String(localized: "Ab \(stars) Sternen", bundle: .module)) {
                            setMinimumRating(stars)
                        }
                    }
                } label: {
                    Text(minimumRating == 0 ? "☆" : "★ \(minimumRating)+")
                        .foregroundStyle(Palette.accentText(colorScheme))
                }
                .accessibilityLabel(Text(String(localized: "Mindestbewertung", bundle: .module)))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(String(localized: "Gekocht eintragen", bundle: .module)) { addsEntry = true }
                    Button(String(localized: "Kochjahr-Buch", bundle: .module)) { showsYearbook = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text(String(localized: "Hinzufügen", bundle: .module)))
            }
        }
        .appSheet(isPresented: $showsYearbook) {
            CookYearbookSheet()
        }
        .appSheet(isPresented: $addsEntry) {
            CookEntryAddView(library: library)
        }
    }

    private func setMinimumRating(_ stars: Int) {
        minimumRating = stars
        SettingsFile.set(stars, forKey: "history.minimumRating")
    }

    private var list: some View {
        List {
            ForEach(months, id: \.id) { group in
                Section(group.month.formatted(.dateTime.month(.wide).year().locale(AppSettings.locale))) {
                    ForEach(group.runs, id: \.id) { run in
                        NavigationLink {
                            CookRunDetailView(runID: run.id)
                        } label: {
                            HStack(spacing: 12) {
                                RunThumbnail(run: run, size: 56)
                                RunRow(run: run)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// The records with a photo, as tiles with the dish's name.
    private var gallery: some View {
        let withPhotos = shownRuns.filter { $0.photoFileName != nil }
        return ScrollView {
            if withPhotos.isEmpty {
                VStack(spacing: 8) {
                    Text(String(localized: "Noch keine Fotos", bundle: .module))
                        .font(.headline)
                    Text(String(localized: "Ein Foto hängst Du im Eintrag unter „Wie war’s?“ an.", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                    ForEach(withPhotos, id: \.id) { run in
                        NavigationLink {
                            CookRunDetailView(runID: run.id)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                RunThumbnail(run: run, size: 110)
                                Text(run.dishName)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.white)
                                    .lineLimit(2)
                                    .padding(4)
                                    .frame(width: 110, alignment: .leading)
                                    .background(Color.black.opacity(0.45))
                            }
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    /// The dishes by their stars, best first.
    private var hitList: some View {
        let statistics = KitchenCookStatistics(runs: shownRuns)
        return List {
            if statistics.hitList.isEmpty {
                Text(String(localized: "Vergib im Eintrag Sterne, dann steht hier, was am besten ankam.", bundle: .module))
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
            ForEach(Array(statistics.hitList.enumerated()), id: \.element.id) { index, dish in
                HStack(spacing: 12) {
                    Text(verbatim: "\(index + 1).")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(index < 3 ? Palette.accentText(colorScheme) : Palette.subtitle(colorScheme))
                        .frame(width: 34, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dish.name)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            if let average = dish.averageRating {
                                Text(starsText(Int(average.rounded())))
                                    .foregroundStyle(Palette.accentText(colorScheme))
                                Text(average.formatted(.number.precision(.fractionLength(1)).locale(AppSettings.locale)))
                            }
                            Text(String(localized: "\(dish.count)× gekocht", bundle: .module))
                        }
                        .font(.footnote)
                        .foregroundStyle(Palette.subtitle(colorScheme))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// A record's photo as a square, or a plain tile without one. Small
/// copies are kept per file, so a gallery does not decode every photo
/// at full size on each redraw.
struct RunThumbnail: View {
    let run: KitchenCookRun
    let size: CGFloat
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let image = RunThumbnails.image(for: run) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size > 80 ? 14 : 10))
        } else {
            RoundedRectangle(cornerRadius: size > 80 ? 14 : 10)
                .fill(Palette.accentText(colorScheme).opacity(0.12))
                .frame(width: size, height: size)
                .overlay(Text(verbatim: "🍳").font(.system(size: size * 0.4)))
        }
    }
}

@MainActor
enum RunThumbnails {
    private static var cache: [String: UIImage] = [:]

    static func image(for run: KitchenCookRun) -> UIImage? {
        guard let name = run.photoFileName else { return nil }
        if let image = cache[name] { return image }
        guard let data = CookRunLog.shared.photoData(of: run),
              let small = PhotoShrinker.thumbnail(data, edge: 320),
              let image = UIImage(data: small) else { return nil }
        // Bounded: a long history must not keep every thumbnail forever.
        if cache.count >= 200 { cache.removeAll() }
        cache[name] = image
        return image
    }
}

struct RunMonth {
    let month: Date
    let runs: [KitchenCookRun]
    var id: String { "\(Int(month.timeIntervalSince1970))" }
}

/// "★★★★☆": the rating in characters, which every font has (Skip draws
/// no outline star symbol).
func starsText(_ rating: Int) -> String {
    String(repeating: "★", count: max(0, min(5, rating))) + String(repeating: "☆", count: max(0, 5 - min(5, rating)))
}

struct RunRow: View {
    let run: KitchenCookRun
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(run.dishName)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.title(colorScheme))
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(run.startedAt.formatted(.dateTime.day().month(.abbreviated).year().locale(AppSettings.locale)))
                if !run.isManualEntry {
                    Text(run.relaxed == true ? String(localized: "Entspannt", bundle: .module) : KitchenCookRun.clockText(run.totalSeconds))
                }
                if let rating = run.rating {
                    Text(starsText(rating))
                        .foregroundStyle(Palette.accentText(colorScheme))
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.subtitle(colorScheme))
            if let note = run.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.subtitle(colorScheme))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One record: how it was (stars, note), what the stopwatch said, the
/// steps with their times against the plan.
struct CookRunDetailView: View {
    let runID: String
    @State var log = CookRunLog.shared
    @State var note = ""
    @State var confirmsDeletion = false
    @State var takesPhoto = false
    @State var picksPhoto = false
    @State var pickedURL: URL?
    @State var pickedName: String?
    @State var pickedType: String?
    /// The record's photo, decoded once per file (not on every keystroke
    /// of the note) and no larger than the screen needs.
    @State var photo: UIImage?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Form {
            if let run = log.run(id: runID) {
                Section(String(localized: "Wie war’s?", bundle: .module)) {
                    if let image = photo {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack(spacing: 4) {
                        ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                            Button {
                                setRating(run.rating == stars ? nil : stars)
                            } label: {
                                Text(stars <= (run.rating ?? 0) ? "★" : "☆")
                                    .font(.title)
                                    .foregroundStyle(Palette.accentText(colorScheme))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(String(localized: "\(stars) Sterne", bundle: .module)))
                        }
                    }
                    TextField(String(localized: "Notiz, z. B. „beim nächsten Mal weniger Salz“", bundle: .module),
                              text: $note, axis: .vertical)
                        .onSubmit { saveNote() }
                    Button(String(localized: "Foto aufnehmen", bundle: .module)) { takesPhoto = true }
                    Button(String(localized: "Foto auswählen", bundle: .module)) { picksPhoto = true }
                    if run.photoFileName != nil {
                        Button(String(localized: "Foto entfernen", bundle: .module), role: .destructive) {
                            log.setPhoto(nil, of: runID)
                        }
                    }
                }
                if run.isManualEntry {
                    Section {
                        Text(String(localized: "Ohne Stoppuhr eingetragen.", bundle: .module))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    stopwatchSections(run)
                }
                Section {
                    Button(String(localized: "Eintrag löschen", bundle: .module), role: .destructive) {
                        confirmsDeletion = true
                    }
                }
            }
        }
        .navigationTitle(log.run(id: runID)?.dishName ?? "")
        .cameraPicker(isPresented: $takesPhoto) { data in
            log.setPhoto(data, of: runID)
        }
        // A photo from the gallery through the document picker: SkipKit's
        // media picker hands Android's content:// address on, which Swift
        // cannot read; the document picker gives a copy (BakePlanner).
        .withDocumentPicker(isPresented: $picksPhoto, allowedContentTypes: [.image],
                            selectedDocumentURL: $pickedURL, selectedFilename: $pickedName,
                            selectedFileMimeType: $pickedType)
        .onChange(of: pickedURL) { _, url in
            guard let url else { return }
            pickedURL = nil
            if let raw = try? Data(contentsOf: url), let data = PhotoShrinker.pickedPhoto(raw) {
                log.setPhoto(data, of: runID)
            }
        }
        .onAppear { note = log.run(id: runID)?.note ?? "" }
        .task(id: log.run(id: runID)?.photoFileName) {
            guard let run = log.run(id: runID), let data = log.photoData(of: run) else {
                photo = nil
                return
            }
            let small = await Task.detached { PhotoShrinker.thumbnail(data, edge: 1200) }.value
            photo = small.flatMap { UIImage(data: $0) }
        }
        .onDisappear { saveNote() }
        .alert(String(localized: "Eintrag löschen?", bundle: .module), isPresented: $confirmsDeletion) {
            Button(String(localized: "Löschen", bundle: .module), role: .destructive) {
                log.delete(id: runID)
                dismiss()
            }
            Button(String(localized: "Abbrechen", bundle: .module), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func stopwatchSections(_ run: KitchenCookRun) -> some View {
        Section {
            LabeledContent(String(localized: "Gebraucht", bundle: .module)) {
                Text(run.relaxed == true ? String(localized: "Entspannt", bundle: .module) : KitchenCookRun.clockText(run.totalSeconds))
            }
            LabeledContent(String(localized: "Geplant", bundle: .module)) {
                Text(String(localized: "\(run.plannedMinutes) Min.", bundle: .module))
            }
            if run.relaxed != true {
                LabeledContent(String(localized: "Unterschied", bundle: .module)) {
                    Text(KitchenCookRun.differenceText(run.totalSeconds - run.plannedMinutes * 60))
                }
            }
            if let total = run.totalSteps, run.steps.count < total {
                Text(String(localized: "Vorzeitig beendet: \(run.steps.count) von \(total) Schritten erledigt.", bundle: .module))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            ForEach(Array(run.steps.enumerated()), id: \.offset) { _, step in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(step.name)
                        Spacer()
                        Text(KitchenCookRun.differenceText(step.differenceSeconds))
                            .font(.footnote)
                            .foregroundStyle(Palette.accentText(colorScheme))
                    }
                    Text(String(localized: "erledigt \(KitchenCookRun.clockText(step.doneSecond) /*%@*/) · gebraucht \(KitchenCookRun.clockText(step.actualSeconds) /*%@*/) · geplant \(step.plannedMinutes) Min.", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(String(localized: "Schritte", bundle: .module))
        }
    }

    private func setRating(_ stars: Int?) {
        guard var run = log.run(id: runID) else { return }
        run.rating = stars
        log.update(run)
    }

    private func saveNote() {
        guard var run = log.run(id: runID) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        guard run.note != value else { return }
        run.note = value
        log.update(run)
    }
}

/// A dish cooked without the stopwatch, entered afterwards.
struct CookEntryAddView: View {
    let library: CookLibrary
    @State var dishID = ""
    @State var date = Date()
    @State var rating = 0
    @State var note = ""
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var choices: [KitchenDish] { library.ownDishes + library.samples }

    var body: some View {
        NavigationStack {
            Form {
                // The heading above, not beside: a long dish name squeezed a
                // label beside it to one letter a line.
                Section(String(localized: "Gericht", bundle: .module)) {
                    Picker(String(localized: "Gericht", bundle: .module), selection: $dishID) {
                        ForEach(choices, id: \.id) { dish in
                            Text(dish.name).tag(dish.id)
                        }
                    }
                    .labelsHidden()
                }
                Section {
                    DatePicker(String(localized: "Gekocht am", bundle: .module), selection: $date,
                               displayedComponents: [.date])
                }
                Section(String(localized: "Wie war’s?", bundle: .module)) {
                    HStack(spacing: 4) {
                        ForEach([1, 2, 3, 4, 5], id: \.self) { stars in
                            Button {
                                rating = rating == stars ? 0 : stars
                            } label: {
                                Text(stars <= rating ? "★" : "☆")
                                    .font(.title)
                                    .foregroundStyle(Palette.accentText(colorScheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField(String(localized: "Notiz, z. B. „beim nächsten Mal weniger Salz“", bundle: .module),
                              text: $note, axis: .vertical)
                }
            }
            .navigationTitle(String(localized: "Gekocht eintragen", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern", bundle: .module)) { save() }
                        .disabled(dishID.isEmpty)
                }
            }
            .onAppear {
                if dishID.isEmpty { dishID = choices.first?.id ?? "" }
            }
        }
    }

    private func save() {
        guard let dish = choices.first(where: { $0.id == dishID }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = KitchenCookRun.manualEntry(dishID: dish.id, dishName: dish.name, date: date,
                                               rating: rating == 0 ? nil : rating,
                                               note: trimmed.isEmpty ? nil : trimmed)
        CookRunLog.shared.add(entry)
        dismiss()
    }
}
