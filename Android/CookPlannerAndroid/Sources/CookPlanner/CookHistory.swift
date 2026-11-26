import BakePlannerCore
import SkipKit
import SwiftUI

/// "Gekocht": every cook on the stopwatch and every one entered by hand,
/// by month, newest first (the iPhone's CookHistoryView, list layout).
struct CookHistoryView: View {
    let library: CookLibrary
    @State var log = CookRunLog.shared
    @State var addsEntry = false
    @Environment(\.colorScheme) var colorScheme

    /// The records by month, newest first.
    private var months: [RunMonth] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var groups: [Date: [KitchenCookRun]] = [:]
        for run in log.runs {
            let parts = calendar.dateComponents([.year, .month], from: run.startedAt)
            let month = calendar.date(from: parts) ?? run.startedAt
            groups[month, default: []].append(run)
        }
        return groups.keys.sorted(by: >).map { RunMonth(month: $0, runs: groups[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            WarmBackground().ignoresSafeArea()
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
                List {
                    ForEach(months, id: \.id) { group in
                        Section(group.month.formatted(.dateTime.month(.wide).year().locale(AppSettings.locale))) {
                            ForEach(group.runs, id: \.id) { run in
                                NavigationLink {
                                    CookRunDetailView(runID: run.id)
                                } label: {
                                    RunRow(run: run)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(String(localized: "Gekocht", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addsEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text(String(localized: "Gekocht eintragen", bundle: .module)))
            }
        }
        .appSheet(isPresented: $addsEntry) {
            CookEntryAddView(library: library)
        }
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
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Form {
            if let run = log.run(id: runID) {
                Section(String(localized: "Wie war’s?", bundle: .module)) {
                    if let data = log.photoData(of: run), let image = UIImage(data: data) {
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
