//
//  BakeHistoryPhotoImportView.swift
//  BakePlanner (Android)
//
//  Years of bread photos become a baking history: the person picks the
//  photos, the app reads each JPEG's date and title (PhotoMetadata in the
//  package), proposes the recipe by the title, and a list lets every
//  proposal be checked, changed or left out before the bakes are written.
//  Unlike the iPhone there is no likeness to the recipe pictures here, so
//  the sheet says plainly that the recipe's name belongs in the photo's
//  title or description.
//

import BakePlannerCore
import SwiftUI

struct BakeHistoryPhotoImportView: View {
    let model: AppModel

    @State var rows: [Row] = []
    @State var picksPhotos = false
    @State var pickedURLs: [URL] = []
    @State var pickedNames: [String] = []
    @State var pickedTypes: [String] = []
    @State var isReading = false
    @State var isWriting = false
    @State var createdCount = 0
    @State var skippedCount = 0
    @State var showsOutcome = false
    @Environment(\.dismiss) var dismiss

    /// One photo on its way into the history.
    struct Row: Identifiable {
        let id = UUID()
        let data: Data
        var date: Date?
        var title: String?
        var recipeID: String?
        var proposedByTitle: Bool
        var isDuplicate: Bool
        var include: Bool
    }

    var body: some View {
        Form {
            Section {
                Button {
                    picksPhotos = true
                } label: {
                    Label(rows.isEmpty ? "Fotos auswählen" : "Weitere Fotos auswählen", systemImage: "photo.on.rectangle.angled")
                }
                if isReading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Fotos werden gelesen …")
                    }
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Aus jedem Foto liest die App das Aufnahmedatum und den Titel. Damit sie das Rezept findet, muss der Rezeptname im Titel oder in der Beschreibung des Fotos stehen – in Google Fotos unter „Info“ eintragen, dann das Bild teilen. Ohne Titel wählst Du das Rezept hier von Hand. Datum und Titel liest die App aus JPEG-Dateien; bei anderen Formaten setzt Du beides selbst.")
            }

            if !rows.isEmpty {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, at: index)
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
                        Text("\(bakesText(includedCount)) anlegen")
                    }
                    .disabled(includedCount == 0 || isWriting)
                }
            }
        }
        .navigationTitle("Backhistorie aus Fotos")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
            }
        }
        .withDocumentPicker(isPresented: $picksPhotos,
                            allowedContentTypes: [.image],
                            allowsMultipleSelection: true,
                            selectedDocumentURLs: $pickedURLs,
                            selectedFilenames: $pickedNames,
                            selectedFileMimeTypes: $pickedTypes)
        .onChange(of: pickedURLs) { _, urls in
            guard !urls.isEmpty else { return }
            pickedURLs = []
            Task { await read(urls) }
        }
        .alert("Backhistorie ergänzt", isPresented: $showsOutcome) {
            Button("OK") { dismiss() }
        } message: {
            Text("\(bakesText(createdCount)) angelegt, \(photosText(skippedCount)) übersprungen.")
        }
    }

    private var includedCount: Int {
        rows.filter { $0.include && $0.recipeID != nil && $0.date != nil && !$0.isDuplicate }.count
    }

    private func bakesText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Backvorgang", bundle: .module) : String(localized: "\(count) Backvorgänge", bundle: .module)
    }

    private func photosText(_ count: Int) -> String {
        count == 1 ? String(localized: "1 Foto", bundle: .module) : String(localized: "\(count) Fotos", bundle: .module)
    }

    // MARK: Rows

    private func rowView(_ row: Row, at index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = UIImage(data: row.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 6) {
                if let title = row.title {
                    Text(verbatim: title)
                        .font(AppFont.headline)
                }
                if row.date != nil {
                    DatePicker("Datum", selection: Binding(
                        get: { rows[index].date ?? Date() },
                        set: { chosen in update(index) { $0.date = chosen } }
                    ), displayedComponents: [.date])
                } else {
                    Button("Kein Datum im Foto – Datum wählen") {
                        update(index) { $0.date = Date() }
                    }
                    .foregroundStyle(Palette.warning(colorScheme))
                }
                Picker("Rezept", selection: Binding(
                    get: { rows[index].recipeID ?? "" },
                    set: { chosen in
                        update(index) { row in
                            row.recipeID = chosen.isEmpty ? nil : chosen
                            row.proposedByTitle = false
                            row.include = row.recipeID != nil
                        }
                    }
                )) {
                    Text("Rezept wählen").tag("")
                    ForEach(model.recipes, id: \.id) { recipe in
                        Text(verbatim: recipe.content.name).tag(recipe.id)
                    }
                }
                if row.isDuplicate {
                    Text("Schon in der Backhistorie an diesem Tag")
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.warning(colorScheme))
                } else if row.proposedByTitle {
                    Text("Nach dem Titel vorgeschlagen")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Anlegen", isOn: Binding(
                    get: { rows[index].include },
                    set: { value in update(index) { $0.include = value } }
                ))
                .disabled(row.recipeID == nil || row.date == nil || row.isDuplicate)
            }
        }
    }

    @Environment(\.colorScheme) var colorScheme

    /// Changes one row and re-checks it against the existing bakes.
    private func update(_ index: Int, _ change: (inout Row) -> Void) {
        guard rows.indices.contains(index) else { return }
        var row = rows[index]
        change(&row)
        if let recipeID = row.recipeID, let date = row.date {
            row.isDuplicate = isDuplicate(recipeID: recipeID, date: date)
            if row.isDuplicate { row.include = false }
        }
        rows[index] = row
    }

    private func isDuplicate(recipeID: String, date: Date) -> Bool {
        let name = model.recipeName(id: recipeID)
        let existing = model.bakeHistory.map { (recipeName: model.recipeName(id: $0.recipeID), date: $0.date) }
        return BakeHistoryPhotoImport.isDuplicate(recipeName: name, date: date, existing: existing)
    }

    // MARK: Reading

    private func read(_ urls: [URL]) async {
        isReading = true
        let names = model.recipes.map { $0.content.name }
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let meta = PhotoMetadata.read(data)
            var row = Row(data: data, date: meta.date, title: meta.title, recipeID: nil,
                          proposedByTitle: false, isDuplicate: false, include: false)
            if let title = meta.title, let match = BakeHistoryPhotoImport.bestMatch(title: title, recipeNames: names),
               let recipe = model.recipes.first(where: { $0.content.name == match.recipeName }) {
                row.recipeID = recipe.id
                row.proposedByTitle = true
            }
            if let recipeID = row.recipeID, let date = row.date {
                row.isDuplicate = isDuplicate(recipeID: recipeID, date: date)
            }
            row.include = row.recipeID != nil && row.date != nil && !row.isDuplicate
            rows.append(row)
        }
        isReading = false
    }

    // MARK: Writing

    private func write() {
        isWriting = true
        var created = 0
        for row in rows where row.include && !row.isDuplicate {
            guard let recipeID = row.recipeID, let date = row.date else { continue }
            if model.addBakeEntry(toRecipe: recipeID, date: date, comment: row.title ?? "",
                                  images: [PhotoShrinker.shrunk(row.data)], facts: BakeHistoryFacts()) {
                created += 1
            }
        }
        isWriting = false
        createdCount = created
        skippedCount = rows.count - created
        showsOutcome = true
    }
}
