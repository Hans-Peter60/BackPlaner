//
//  CookPhotoImportView.swift
//  CookPlanner
//
//  Old photos of finished dishes become history, the way BakePlanner turns
//  bread photos into bakes: pick the photos, the app reads each one's date
//  and title and proposes the dish whose name the title contains; every
//  photo can get another dish, another day, or be left out, before the
//  entries are written.
//

import BakePlannerCore
import PhotosUI
import SwiftUI

struct CookPhotoImportView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(DishLibrary.self) private var library
    @State private var items: [PhotosPickerItem] = []
    @State private var proposals: [Proposal] = []
    @State private var isReading = false

    struct Proposal: Identifiable {
        let id = UUID()
        let image: UIImage
        var date: Date
        /// The dish to enter it for; empty leaves the photo out.
        var dishID: String
    }

    private var dishes: [KitchenDish] { library.dishes + KitchenSampleDishes.all }
    private var chosen: [Proposal] { proposals.filter { !$0.dishID.isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $items, maxSelectionCount: 30, matching: .images) {
                        Label(proposals.isEmpty ? "Fotos auswählen" : "Andere Fotos auswählen",
                              systemImage: "photo.on.rectangle")
                    }
                    if isReading {
                        HStack {
                            ProgressView()
                            Text("Fotos werden gelesen …")
                        }
                    }
                } footer: {
                    Text("Datum und Titel kommen aus den Fotos. Steht der Name eines Gerichts im Titel, ist es schon gewählt; sonst wählst Du es je Foto. Ohne Gericht bleibt ein Foto draußen.")
                }
                ForEach($proposals) { $proposal in
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(uiImage: proposal.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) {
                                Picker("Gericht", selection: $proposal.dishID) {
                                    Text("Nicht übernehmen").tag("")
                                    ForEach(dishes) { dish in
                                        Text(verbatim: dish.name).tag(dish.id)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                DatePicker("Gekocht am", selection: $proposal.date, in: ...Date.now,
                                           displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Aus Fotos übernehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Übernehmen" : "\(chosen.count) übernehmen") { save() }
                        .disabled(chosen.isEmpty)
                }
            }
            .onChange(of: items) { _, items in read(items) }
        }
    }

    private func read(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isReading = true
        Task {
            var read: [Proposal] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = CookRunLog.downsampled(data) else { continue }
                let metadata = PhotoMetadata.read(data)
                read.append(Proposal(image: image, date: min(metadata.date ?? .now, .now),
                                     dishID: proposedDish(for: metadata.title)?.id ?? ""))
            }
            proposals = read.sorted { $0.date < $1.date }
            isReading = false
        }
    }

    /// The dish whose name the photo's title contains, the longest name first.
    private func proposedDish(for title: String?) -> KitchenDish? {
        guard let title, !title.isEmpty else { return nil }
        return dishes.sorted { $0.name.count > $1.name.count }.first { dish in
            title.range(of: dish.name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || dish.name.range(of: title, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func save() {
        for proposal in chosen {
            guard let dish = dishes.first(where: { $0.id == proposal.dishID }) else { continue }
            let entry = KitchenCookRun.manualEntry(dishID: dish.id, dishName: dish.name, date: proposal.date)
            CookRunLog.shared.add(entry)
            CookRunLog.shared.setPhoto(proposal.image, for: entry.id)
        }
        dismiss()
    }
}
