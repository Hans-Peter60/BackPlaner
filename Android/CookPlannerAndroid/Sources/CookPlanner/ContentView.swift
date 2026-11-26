import BakePlannerCore
import SwiftUI

/// The root: the dish list in a navigation stack, in the app's language.
struct ContentView: View {
    @State var library = CookLibrary()
    @Environment(\.locale) var locale
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            DishListView(library: library)
        }
        .tint(Palette.accent(colorScheme))
        // Skip looks every text up in the environment's locale; the
        // package takes the same language (AppSettings.locale).
        .environment(\.locale, AppSettings.appLocale(forDevice: locale))
        .compactTextFields()
        .onChange(of: locale) { _, newLocale in
            let appLocale = AppSettings.appLocale(forDevice: newLocale)
            AppSettings.systemLocale = { appLocale }
        }
        .task {
            let appLocale = AppSettings.appLocale(forDevice: locale)
            AppSettings.systemLocale = { appLocale }
            library.load()
        }
    }
}

/// The cook's own dishes, then the examples, each with its verdict.
struct DishListView: View {
    let library: CookLibrary
    @State var showsSettings = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            WarmBackground().ignoresSafeArea()
            list
        }
        .navigationTitle(String(localized: "Gerichte", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Text(String(localized: "Einstellungen", bundle: .module)))
            }
        }
        .appSheet(isPresented: $showsSettings) {
            KitchenSettingsView(library: library)
        }
    }

    private var list: some View {
        List {
            Section {
                Text(String(localized: "Ein Gericht, eine Person, \(library.budget) Minuten", bundle: .module))
                    .font(.footnote)
                    .foregroundStyle(Palette.subtitle(colorScheme))
            }
            if !library.ownDishes.isEmpty {
                Section(String(localized: "Meine Gerichte", bundle: .module)) {
                    ForEach(library.ownDishes, id: \.id) { dish in
                        NavigationLink {
                            DishPlanView(library: library, dishID: dish.id)
                        } label: {
                            DishRow(library: library, dish: dish)
                        }
                    }
                }
            }
            Section(String(localized: "Beispiele", bundle: .module)) {
                ForEach(library.samples, id: \.id) { dish in
                    NavigationLink {
                        DishPlanView(library: library, dishID: dish.id)
                    } label: {
                        DishRow(library: library, dish: dish)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// A dish in the list: its name, its components and how it fares.
struct DishRow: View {
    let library: CookLibrary
    let dish: KitchenDish
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dish.name)
                .font(.headline)
                .foregroundStyle(Palette.title(colorScheme))
            if !dish.components.isEmpty {
                Text(dish.components.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Palette.subtitle(colorScheme))
                    .lineLimit(2)
            }
            if let plan = library.plan(for: dish) {
                Text(plan.verdict)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(plan.fits ? Palette.good(colorScheme) : Palette.danger(colorScheme))
            } else if let failure = library.failure(for: dish) {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(Palette.danger(colorScheme))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Budget and kitchen, as on the iPhone.
struct KitchenSettingsView: View {
    let library: CookLibrary
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Zeitbudget", bundle: .module)) {
                    Stepper(String(localized: "\(library.budget) Minuten", bundle: .module),
                            value: Binding(get: { library.budget }, set: { library.budget = $0 }),
                            in: 10...180, step: 5)
                }
                Section(String(localized: "Küche", bundle: .module)) {
                    Stepper(String(localized: "Platten: \(library.burners)", bundle: .module),
                            value: Binding(get: { library.burners }, set: { library.burners = $0 }),
                            in: 1...8)
                    Stepper(String(localized: "Öfen: \(library.ovens)", bundle: .module),
                            value: Binding(get: { library.ovens }, set: { library.ovens = $0 }),
                            in: 0...3)
                    Text(String(localized: "Die Öfen sind vorgeheizt, wenn die Uhr startet.", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Einstellungen", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Fertig", bundle: .module)) { dismiss() }
                }
            }
        }
    }
}
