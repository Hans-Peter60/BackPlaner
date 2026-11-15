//
//  BakeHistoryPhotoImportView.swift
//  BackPlaner
//
//  Years of bread photos become a baking history: the person picks the
//  photos, the app reads each one's date and title, proposes the recipe
//  by the title or by the picture's likeness to the recipe pictures, and
//  a list lets every proposal be checked, changed or left out before the
//  bakes are written. A BakePlanner Pro feature.
//

import BakePlannerCore
import CoreData
import PhotosUI
import SwiftUI

struct BakeHistoryPhotoImportView: View {

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var rows: [Row] = []
    @State private var isReading = false
    @State private var readCount = 0
    @State private var isWriting = false
    @State private var outcome: (created: Int, skipped: Int)?

    private let locale = AppSettings.locale

    /// One photo on its way into the history.
    struct Row: Identifiable {
        enum Source { case title, likeness, none }

        let id = UUID()
        let data: Data
        let thumbnail: UIImage?
        var date: Date?
        var title: String?
        /// The recipe chosen for it, by name; nil for none yet.
        var recipeName: String?
        var source: Source
        var confidence: Double
        var isDuplicate: Bool
        var include: Bool
    }

    var body: some View {
        NavigationStack {
            ProLockedScreen(.historyImport) {
                content
            }
            .navigationTitle("Backhistorie aus Fotos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    private var content: some View {
        List {
            Section {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: 200, matching: .images) {
                    Label(rows.isEmpty ? "Fotos auswählen" : "Weitere Fotos auswählen", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityIdentifier("historyImport.pick")
                .onChange(of: pickedItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await read(items) }
                }
                if isReading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("\(readCount) von \(pickedItems.count) Fotos gelesen …")
                    }
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.subtitle)
                }
            } footer: {
                Text("Aus jedem Foto liest die App das Aufnahmedatum und, wenn vorhanden, den Titel. Das Rezept schlägt sie nach dem Titel vor, sonst nach der Ähnlichkeit mit Deinen Rezeptbildern – alles auf dem Gerät. Prüfe die Vorschläge unten, dann legt „Backvorgänge anlegen“ die Einträge an.")
            }

            if !rows.isEmpty {
                Section {
                    ForEach($rows) { $row in
                        rowView($row)
                    }
                    .onDelete { offsets in rows.remove(atOffsets: offsets) }
                } header: {
                    Text(photosText(rows.count))
                } footer: {
                    Text("Ohne Rezept oder ohne Datum wird ein Foto nicht angelegt. Ein Rezept, das am selben Tag schon einen Eintrag hat, wird übersprungen.")
                }

                Section {
                    Button {
                        write()
                    } label: {
                        HStack {
                            if isWriting { ProgressView().padding(.trailing, 6) }
                            Text("\(bakesText(includedRows.count)) anlegen")
                        }
                    }
                    .disabled(includedRows.isEmpty || isWriting)
                    .accessibilityIdentifier("historyImport.write")
                }
            }
        }
        .alert("Backhistorie ergänzt", isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })) {
            Button("OK") { dismiss() }
        } message: {
            if let outcome {
                Text("\(bakesText(outcome.created)) angelegt, \(photosText(outcome.skipped)) übersprungen.")
            }
        }
    }

    private var includedRows: [Row] {
        rows.filter { $0.include && $0.recipeName != nil && $0.date != nil && !$0.isDuplicate }
    }

    private var recipeNames: [String] { recipes.map(\.name) }

    /// "1 Backvorgang" / "3 Backvorgänge" — the catalog has no plural rules
    /// shared with Android, so the singular is its own text.
    private func bakesText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Backvorgang") : String(localized: "\(count) Backvorgänge")
    }

    private func photosText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Foto") : String(localized: "\(count) Fotos")
    }

    // MARK: Rows

    private func rowView(_ row: Binding<Row>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let thumbnail = row.wrappedValue.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                if let title = row.wrappedValue.title {
                    Text(title)
                        .font(Theme.brandFont(15))
                        .foregroundColor(Theme.cardTitle)
                        .lineLimit(2)
                }

                // The date: the photo's, or one to choose when it had none.
                if row.wrappedValue.date != nil {
                    DatePicker("Datum", selection: Binding(
                        get: { row.wrappedValue.date ?? Date() },
                        set: { row.wrappedValue.date = $0; refreshDuplicate(row) }
                    ), in: ...Date(), displayedComponents: .date)
                    .environment(\.locale, locale)
                    .font(Theme.bodyFont(14))
                } else {
                    Button {
                        row.wrappedValue.date = Date()
                    } label: {
                        Label("Kein Datum im Foto – Datum wählen", systemImage: "calendar.badge.exclamationmark")
                    }
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.warning)
                }

                // The recipe: a menu of the own recipes with the proposal.
                Menu {
                    ForEach(recipeNames, id: \.self) { name in
                        Button(name) {
                            row.wrappedValue.recipeName = name
                            row.wrappedValue.source = .none
                            row.wrappedValue.include = true
                            refreshDuplicate(row)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book")
                        Text(row.wrappedValue.recipeName ?? String(localized: "Rezept wählen"))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                    }
                    .font(Theme.bodyFont(14))
                    .foregroundColor(row.wrappedValue.recipeName == nil ? Theme.warning : Theme.accentText)
                }

                if let hint = hint(for: row.wrappedValue) {
                    Text(hint)
                        .font(Theme.bodyFont(12))
                        .foregroundColor(row.wrappedValue.isDuplicate ? Theme.warning : Theme.subtitle)
                }
            }

            Spacer(minLength: 0)
            Toggle("", isOn: row.include)
                .labelsHidden()
                .disabled(row.wrappedValue.recipeName == nil || row.wrappedValue.date == nil || row.wrappedValue.isDuplicate)
        }
        .padding(.vertical, 4)
    }

    private func hint(for row: Row) -> String? {
        if row.isDuplicate { return String(localized: "Schon in der Backhistorie an diesem Tag") }
        switch row.source {
        case .title: return String(localized: "Nach dem Titel vorgeschlagen")
        case .likeness:
            return row.confidence >= 0.75
                ? String(localized: "Sieht aus wie das Rezeptbild")
                : String(localized: "Ähnelt dem Rezeptbild – bitte prüfen")
        case .none: return nil
        }
    }

    // MARK: Reading

    private func read(_ items: [PhotosPickerItem]) async {
        isReading = true
        readCount = 0
        defer { isReading = false; pickedItems = [] }

        let names = recipeNames
        let existing = existingBakes()
        // The recipe pictures' prints, once; only recipes with a picture.
        let prints = BakeHistoryPhotoReader.recipePrints(recipes.compactMap { recipe in
            recipe.image.isEmpty ? nil : (name: recipe.name, image: recipe.image)
        })
        var askedForLibrary = false

        for item in items {
            readCount += 1
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            var facts = BakeHistoryPhotoReader.facts(of: data)
            if facts.date == nil, let identifier = item.itemIdentifier {
                if !askedForLibrary {
                    askedForLibrary = true
                    _ = await BakeHistoryPhotoReader.requestLibraryAccess()
                }
                facts.date = BakeHistoryPhotoReader.libraryDate(forAssetIdentifier: identifier)
            }

            var row = Row(data: data,
                          thumbnail: RecipeThumbnails.downsampled(data, maxPixelSize: 160),
                          date: facts.date, title: facts.title,
                          recipeName: nil, source: .none, confidence: 0, isDuplicate: false, include: false)
            if let title = facts.title, let match = BakeHistoryPhotoImport.bestMatch(title: title, recipeNames: names) {
                row.recipeName = match.recipeName
                row.source = .title
                row.confidence = match.score
            } else if !prints.isEmpty, let photoPrint = BakeHistoryPhotoReader.featurePrint(of: data),
                      let closest = BakeHistoryPhotoReader.closest(photoPrint, among: prints),
                      closest.distance < BakeHistoryPhotoReader.likenessLimit {
                row.recipeName = closest.recipeName
                row.source = .likeness
                row.confidence = closest.distance < BakeHistoryPhotoReader.strongLikeness ? 1 : 0.5
            }
            if let name = row.recipeName, let date = row.date {
                row.isDuplicate = BakeHistoryPhotoImport.isDuplicate(recipeName: name, date: date, existing: existing)
            }
            row.include = row.recipeName != nil && row.date != nil && !row.isDuplicate
            rows.append(row)
        }
    }

    private func existingBakes() -> [(recipeName: String, date: Date)] {
        recipes.flatMap { recipe in recipe.bakeHistoriesArray.map { (recipeName: recipe.name, date: $0.date) } }
    }

    private func refreshDuplicate(_ row: Binding<Row>) {
        guard let name = row.wrappedValue.recipeName, let date = row.wrappedValue.date else { return }
        row.wrappedValue.isDuplicate = BakeHistoryPhotoImport.isDuplicate(recipeName: name, date: date, existing: existingBakes())
        if row.wrappedValue.isDuplicate { row.wrappedValue.include = false }
    }

    // MARK: Writing

    /// One bake per included row: the photo shrunk as the backup shrinks
    /// pictures, the title as the comment, the recipe marked as baked.
    private func write() {
        isWriting = true
        var created = 0
        for row in includedRows {
            guard let name = row.recipeName, let date = row.date,
                  let recipe = recipes.first(where: { $0.name == name }) else { continue }
            let bake = BakeHistory(context: viewContext)
            bake.id = UUID()
            bake.date = date
            bake.comment = row.title ?? ""
            bake.images = [BackupPhoto.shrunk(row.data, longestEdge: 1600, quality: 0.8)]
            recipe.bakeHistoryFlag = true
            recipe.addToBakeHistories(bake)
            created += 1
        }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            AppLog.persistence.error("Baking history from photos could not be saved: \(error.localizedDescription)")
            created = 0
        }
        isWriting = false
        // The rows stay until the alert's OK closes the sheet: emptying the
        // list under the toggles' bindings while the alert shows crashed.
        outcome = (created: created, skipped: rows.count - created)
    }
}
