import BakePlannerCore
import Foundation
import Observation
import SkipFuse
import SwiftUI

/// The cook's own collections: a filter under a name, as a chip in the
/// list (the iPhone's SavedDishCollectionStore). Kept as JSON in the
/// settings file under the iPhone's key.
@Observable
@MainActor
final class SavedCollectionStore {
    static let shared = SavedCollectionStore()
    static let key = "savedDishCollections"

    private(set) var collections: [SavedKitchenDishCollection] = []

    init() {
        if let text = SettingsFile.text(Self.key), let data = text.data(using: .utf8),
           let stored = try? JSONDecoder().decode([SavedKitchenDishCollection].self, from: data) {
            collections = stored
        }
    }

    /// Saves the filter under the name; nothing for an empty name or filter.
    func add(name: String, filter: KitchenDishFilter) {
        guard let cleaned = SavedKitchenDishCollection.cleanName(name), filter.isActive else { return }
        collections.append(SavedKitchenDishCollection(name: cleaned, filter: filter))
        persist()
    }

    func remove(_ id: UUID) {
        collections.removeAll { $0.id == id }
        persist()
    }

    func collection(matching filter: KitchenDishFilter) -> SavedKitchenDishCollection? {
        collections.first { $0.filter == filter }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(collections) else { return }
        SettingsFile.set(String(decoding: data, as: UTF8.self), forKey: Self.key)
    }
}

/// The facets one by one, and saving them as a collection (the iPhone's
/// filter menu; Skip's menus show no pickers, so it is a sheet here).
struct DishFilterSheet: View {
    @Binding var filter: KitchenDishFilter
    @State var store = SavedCollectionStore.shared
    @State var name = ""
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "Dauer", bundle: .module),
                           selection: Binding(get: { filter.duration?.rawValue ?? "" },
                                              set: { filter.duration = KitchenDishFacets.Duration(rawValue: $0) })) {
                        Text(String(localized: "Alle", bundle: .module)).tag("")
                        Text(String(localized: "Bis 30 Minuten", bundle: .module)).tag(KitchenDishFacets.Duration.quick.rawValue)
                        Text(String(localized: "31 bis 45 Minuten", bundle: .module)).tag(KitchenDishFacets.Duration.medium.rawValue)
                        Text(String(localized: "46 bis 60 Minuten", bundle: .module)).tag(KitchenDishFacets.Duration.long.rawValue)
                        Text(String(localized: "Über eine Stunde", bundle: .module)).tag(KitchenDishFacets.Duration.longer.rawValue)
                    }
                    Picker(String(localized: "Geräte", bundle: .module),
                           selection: Binding(get: { filter.equipment?.rawValue ?? "" },
                                              set: { filter.equipment = KitchenDishFacets.Equipment(rawValue: $0) })) {
                        Text(String(localized: "Alle", bundle: .module)).tag("")
                        Text(String(localized: "Mit Ofen", bundle: .module)).tag(KitchenDishFacets.Equipment.oven.rawValue)
                        Text(String(localized: "Nur Herd", bundle: .module)).tag(KitchenDishFacets.Equipment.stoveOnly.rawValue)
                        Text(String(localized: "Ohne Hitze", bundle: .module)).tag(KitchenDishFacets.Equipment.noHeat.rawValue)
                    }
                    Picker(String(localized: "Herkunft", bundle: .module),
                           selection: Binding(get: { filter.origin?.rawValue ?? "" },
                                              set: { filter.origin = KitchenDishFacets.Origin(rawValue: $0) })) {
                        Text(String(localized: "Alle", bundle: .module)).tag("")
                        Text(String(localized: "Eigene", bundle: .module)).tag(KitchenDishFacets.Origin.own.rawValue)
                        Text(String(localized: "Importiert", bundle: .module)).tag(KitchenDishFacets.Origin.imported.rawValue)
                        Text(String(localized: "Beispiele", bundle: .module)).tag(KitchenDishFacets.Origin.example.rawValue)
                    }
                    Picker(String(localized: "Verlauf", bundle: .module),
                           selection: Binding(get: { filter.history?.rawValue ?? "" },
                                              set: { filter.history = KitchenDishFilter.HistoryChoice(rawValue: $0) })) {
                        Text(String(localized: "Alle", bundle: .module)).tag("")
                        Text(String(localized: "Noch nie gekocht", bundle: .module)).tag(KitchenDishFilter.HistoryChoice.never.rawValue)
                        Text(String(localized: "Lange nicht gekocht", bundle: .module)).tag(KitchenDishFilter.HistoryChoice.longAgo.rawValue)
                        Text(String(localized: "Lieblinge", bundle: .module)).tag(KitchenDishFilter.HistoryChoice.favourites.rawValue)
                    }
                    Toggle(String(localized: "Passt ins Budget", bundle: .module), isOn: $filter.fitsBudgetOnly)
                    Toggle(String(localized: "Wenig Handarbeit", bundle: .module), isOn: $filter.lowWorkOnly)
                    if filter.isActive {
                        Button(String(localized: "Filter zurücksetzen", bundle: .module)) { filter = KitchenDishFilter() }
                    }
                }
                if filter.isActive && store.collection(matching: filter) == nil {
                    Section {
                        TextField(String(localized: "Name", bundle: .module), text: $name)
                        Button(String(localized: "Sammlung sichern", bundle: .module)) {
                            store.add(name: name, filter: filter)
                            name = ""
                        }
                        .disabled(SavedKitchenDishCollection.cleanName(name) == nil)
                    } footer: {
                        Text(String(localized: "Die gewählten Filter erscheinen als eigene Sammlung in der Leiste.", bundle: .module))
                    }
                }
                if !store.collections.isEmpty {
                    Section(String(localized: "Eigene Sammlungen", bundle: .module)) {
                        ForEach(store.collections, id: \.id) { collection in
                            HStack {
                                Text(collection.name)
                                Spacer()
                                Button(String(localized: "Löschen", bundle: .module), role: .destructive) {
                                    store.remove(collection.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Filter", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Fertig", bundle: .module)) { dismiss() }
                }
            }
        }
        .tint(Palette.accent(colorScheme))
    }
}
