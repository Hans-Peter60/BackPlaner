import BakePlannerCore
import SkipKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Every bake of every recipe, newest first — or summed up per recipe as
/// the hit list, most baked first. Tapping an entry changes it, swiping
/// removes it.
struct BakeHistoryView: View {
    let model: AppModel
    @State var showsHitList = false
    @State var editedEntry: StoredBakeHistory?
    @State var editsEntry = false
    /// The entry waiting for the user to confirm its removal. Kept apart
    /// from the dialog's visibility: Android closes the dialog before it
    /// runs the chosen button.
    @State var entryToDelete: StoredBakeHistory?
    @State var confirmsDeletion = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if model.shownBakeHistory.isEmpty {
                VStack(spacing: 12) {
                    Text("Noch keine Backhistorie")
                        .font(.title2)
                        .foregroundStyle(Palette.accent(colorScheme))
                    Text("Öffne ein Rezept und tippe auf „Backvorgang eintragen“.")
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    Picker("Darstellung", selection: $showsHitList) {
                        Text("Liste").tag(false)
                        Text("Hit-Liste").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if showsHitList {
                        ForEach(hitList, id: \.id) { summary in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: summary.name)
                                    .font(.headline)
                                Text("\(summary.count)× gebacken · zuletzt \(BakeHistoryText.date(summary.lastDate))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        ForEach(model.shownBakeHistory, id: \.id) { entry in
                            Button {
                                editedEntry = model.bakeEntry(id: entry.id)
                                editsEntry = editedEntry != nil
                            } label: {
                                BakeHistoryRow(entry: entry, recipeName: model.recipeName(id: entry.recipeID))
                                    .foregroundStyle(Color.primary)
                            }
                        }
                        .onDelete { offsets in
                            entryToDelete = offsets.first.map { model.shownBakeHistory[$0] }
                            confirmsDeletion = entryToDelete != nil
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Backhistorie")
        .sheet(isPresented: $editsEntry) {
            if let entry = editedEntry {
                NavigationStack {
                    BakeEntryEditor(model: model, recipeID: entry.recipeID, original: entry)
                }
            }
        }
        .alert("Backvorgang löschen?", isPresented: $confirmsDeletion) {
            Button("Löschen", role: .destructive) {
                if let entry = entryToDelete {
                    model.deleteBakeEntry(id: entry.id)
                }
                entryToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            if let entry = entryToDelete {
                Text(verbatim: model.recipeName(id: entry.recipeID) + " · " + BakeHistoryText.date(entry.date))
            }
        }
    }

    /// The recipes, most baked first, as the iPhone's hit list has them.
    private var hitList: [BakeHistoryTally.Recipe] {
        let ratings = Dictionary(model.recipes.map { ($0.id, $0.content.rating) }, uniquingKeysWith: { first, _ in first })
        return BakeHistoryTally.recipes(from: model.shownBakeHistory.map { entry in
            BakeHistoryTally.Entry(recipeID: entry.recipeID, recipeName: model.recipeName(id: entry.recipeID),
                                   rating: ratings[entry.recipeID] ?? 0, date: entry.date, photos: [])
        })
    }
}

/// One entry: date (and recipe, in the history of all recipes), the facts
/// in one line, and the comment — as the iPhone's recipe screen shows it.
struct BakeHistoryRow: View {
    let entry: StoredBakeHistory
    /// The recipe's name, or nil where the recipe goes without saying.
    let recipeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let recipeName {
                Text(verbatim: recipeName)
                    .font(.headline)
            }
            HStack(spacing: 8) {
                Text(verbatim: BakeHistoryText.date(entry.date))
                    .bold()
                if entry.date > Date() {
                    Text("geplant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            let summary = entry.facts.summaryLine()
            if !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !BakeHistoryFacts.isPlaceholderComment(entry.comment) {
                Text(verbatim: entry.comment)
            } else if summary.isEmpty && entry.date <= Date() {
                Text("Noch nichts notiert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The bakes of one recipe in its detail screen, with the button that
/// records a new one.
struct RecipeBakeHistorySection: View {
    let model: AppModel
    let recipeID: String
    @State var editedEntry: StoredBakeHistory?
    @State var editsEntry = false
    @State var addsEntry = false
    @Environment(\.colorScheme) var colorScheme

    private var entries: [StoredBakeHistory] {
        model.bakeHistory.filter { $0.recipeID == recipeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                addsEntry = true
            } label: {
                Label("Backvorgang eintragen", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .tint(Palette.accent(colorScheme))

            if !entries.isEmpty {
                Text("Bisherige Backvorgänge")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(Palette.accent(colorScheme))
                ForEach(entries, id: \.id) { entry in
                    Button {
                        editedEntry = model.bakeEntry(id: entry.id)
                        editsEntry = editedEntry != nil
                    } label: {
                        BakeHistoryRow(entry: entry, recipeName: nil)
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .sheet(isPresented: $addsEntry) {
            NavigationStack {
                BakeEntryEditor(model: model, recipeID: recipeID, original: nil)
            }
        }
        .sheet(isPresented: $editsEntry) {
            if let entry = editedEntry {
                NavigationStack {
                    BakeEntryEditor(model: model, recipeID: recipeID, original: entry)
                }
            }
        }
    }
}

/// Records a bake, or changes one: when, a comment, the measurements and
/// the result as on the iPhone, and photos.
struct BakeEntryEditor: View {
    let model: AppModel
    let recipeID: String
    /// The entry as it was, or nil for a new one.
    let original: StoredBakeHistory?
    @State var date: Date
    @State var comment: String
    @State var images: [Data]
    // The numbers are edited as text and read on saving, so "22," on the
    // way to "22,5" is never rejected.
    @State var roomText: String
    @State var doughText: String
    @State var bulkText: String
    @State var finalText: String
    @State var flour: String
    @State var outcome: String
    @State var picksImage = false
    @State var pickedImageURL: URL?
    @State var pickedImageName: String?
    @State var pickedImageType: String?
    @State var confirmsDeletion = false
    @Environment(\.dismiss) var dismiss

    init(model: AppModel, recipeID: String, original: StoredBakeHistory?) {
        self.model = model
        self.recipeID = recipeID
        self.original = original
        let facts = original?.facts ?? BakeHistoryFacts()
        _date = State(initialValue: original?.date ?? Date())
        _comment = State(initialValue: original.map { BakeHistoryFacts.isPlaceholderComment($0.comment) ? "" : $0.comment } ?? "")
        _images = State(initialValue: original?.images ?? [])
        _roomText = State(initialValue: BakeHistoryFacts.temperatureInput(facts.roomTemperature))
        _doughText = State(initialValue: BakeHistoryFacts.temperatureInput(facts.doughTemperature))
        _bulkText = State(initialValue: BakeHistoryFacts.minutesInput(facts.bulkProofMinutes))
        _finalText = State(initialValue: BakeHistoryFacts.minutesInput(facts.finalProofMinutes))
        _flour = State(initialValue: facts.flour)
        _outcome = State(initialValue: facts.outcome)
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Backdatum", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Kommentar", text: $comment, axis: .vertical)
            }

            Section {
                numberRow("Raumtemperatur", text: $roomText, unit: "°C")
                numberRow("Teigtemperatur", text: $doughText, unit: "°C")
                numberRow("Stockgare", text: $bulkText, unit: "min")
                numberRow("Stückgare", text: $finalText, unit: "min")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mehl")
                    TextField("z. B. Weizen 550, Dinkel 630", text: $flour)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Krume / Ofentrieb")
                    TextField("Stichworte, durch Komma getrennt", text: $outcome)
                    keywordRow("Krume", keywords: BakeHistoryFacts.OutcomeKeyword.crumb)
                    keywordRow("Ofentrieb", keywords: BakeHistoryFacts.OutcomeKeyword.ovenSpring)
                }
            } header: {
                Text("Messwerte und Ergebnis")
            }

            Section {
                ForEach(Array(images.enumerated()), id: \.offset) { index, data in
                    HStack {
                        photo(data)
                        Spacer()
                        Button("Bild entfernen", role: .destructive) {
                            images.remove(at: index)
                        }
                    }
                }
                Button("Bild hinzufügen") {
                    picksImage = true
                }
            } header: {
                Text("Fotos")
            }

            if original != nil {
                Section {
                    Button("Löschen", role: .destructive) {
                        confirmsDeletion = true
                    }
                }
            }
        }
        .navigationTitle("Backanmerkungen- / hinweise")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    save()
                }
            }
        }
        .withDocumentPicker(isPresented: $picksImage,
                            allowedContentTypes: [.image],
                            selectedDocumentURL: $pickedImageURL,
                            selectedFilename: $pickedImageName,
                            selectedFileMimeType: $pickedImageType)
        .onChange(of: pickedImageURL) { _, url in
            guard let url else { return }
            pickedImageURL = nil
            // A file that is no picture adds nothing.
            if let data = RecipeDetailView.pictureData(at: url) {
                images.append(data)
            }
        }
        .alert("Backvorgang löschen?", isPresented: $confirmsDeletion) {
            Button("Löschen", role: .destructive) {
                if let original {
                    model.deleteBakeEntry(id: original.id)
                }
                dismiss()
            }
            Button("Abbrechen", role: .cancel) { }
        }
    }

    private var facts: BakeHistoryFacts {
        BakeHistoryFacts(roomTemperature: BakeHistoryFacts.parseTemperature(roomText),
                         doughTemperature: BakeHistoryFacts.parseTemperature(doughText),
                         bulkProofMinutes: BakeHistoryFacts.parseMinutes(bulkText),
                         finalProofMinutes: BakeHistoryFacts.parseMinutes(finalText),
                         flour: flour,
                         outcome: outcome)
    }

    private func save() {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if var entry = original {
            // A placeholder left untouched stays the placeholder.
            if !(text.isEmpty && BakeHistoryFacts.isPlaceholderComment(entry.comment)) {
                entry.comment = text
            }
            entry.date = date
            entry.images = images
            entry.facts = facts
            model.updateBakeEntry(entry)
        } else {
            model.addBakeEntry(toRecipe: recipeID, date: date, comment: text, images: images, facts: facts)
        }
        dismiss()
    }

    private func numberRow(_ title: LocalizedStringKey, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(verbatim: unit)
                .foregroundStyle(.secondary)
        }
    }

    /// The words offered under the outcome field; a tap puts one in or
    /// takes it out again, as on the iPhone.
    private func keywordRow(_ title: LocalizedStringKey, keywords: [BakeHistoryFacts.OutcomeKeyword]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keywords, id: \.text) { keyword in
                        let selected = BakeHistoryFacts.contains(keyword.text, in: outcome)
                        Button {
                            outcome = BakeHistoryFacts.toggling(keyword.text, in: outcome)
                        } label: {
                            Text(verbatim: (selected ? "✓ " : "") + keyword.text)
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func photo(_ data: Data) -> some View {
        #if canImport(UIKit) || os(Android)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #endif
    }
}

/// How dates of the bake history read, as on the iPhone.
enum BakeHistoryText {
    static func date(_ date: Date) -> String {
        DateFormat().calculateDate(dT: date)
    }
}
