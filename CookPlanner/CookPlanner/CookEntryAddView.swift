//
//  CookEntryAddView.swift
//  CookPlanner
//
//  A dish cooked without the stopwatch, entered afterwards: which dish,
//  when, the stars, a note and a photo. It joins the history like a
//  stopwatch record, only without the steps' times.
//

import BakePlannerCore
import PhotosUI
import SwiftUI

struct CookEntryAddView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(DishLibrary.self) private var library
    @State private var dishID = ""
    @State private var date = Date.now
    @State private var rating = 0
    @State private var note = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?

    /// The own dishes, then the examples.
    private var dishes: [KitchenDish] { library.dishes + KitchenSampleDishes.all }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Gericht", selection: $dishID) {
                        Text("Bitte wählen").tag("")
                        ForEach(dishes) { dish in
                            Text(verbatim: dish.name).tag(dish.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    DatePicker("Gekocht am", selection: $date, in: ...Date.now)
                }
                Section("Wie war’s?") {
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { stars in
                            Button {
                                rating = rating == stars ? 0 : stars
                            } label: {
                                Image(systemName: stars <= rating ? "star.fill" : "star")
                                    .font(.title3)
                                    .foregroundColor(Theme.accentText)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("\(stars) Sterne"))
                        }
                    }
                    TextField("Notiz, z. B. „beim nächsten Mal weniger Salz“", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photo == nil ? "Foto wählen" : "Anderes Foto", systemImage: "photo")
                    }
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .navigationTitle("Gekocht eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(dishID.isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photo = CookRunLog.downsampled(data)
                        // The photo's own date is the likelier day.
                        if let taken = PhotoMetadata.read(data).date, taken <= .now { date = taken }
                    }
                }
            }
        }
    }

    private func save() {
        guard let dish = dishes.first(where: { $0.id == dishID }) else { return }
        let entry = KitchenCookRun.manualEntry(dishID: dish.id, dishName: dish.name, date: date,
                                               rating: rating > 0 ? rating : nil, note: note)
        CookRunLog.shared.add(entry)
        if let photo { CookRunLog.shared.setPhoto(photo, for: entry.id) }
        dismiss()
    }
}
