import BakePlannerCore
import SkipKit
import SwiftUI

/// The root: the dish list in a navigation stack, in the app's language.
struct ContentView: View {
    @State var library = CookLibrary()
    /// A run the last launch left under way, opened again.
    @State var resumed: CookRunState?
    @State var showsResumed = false
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
            if let state = CookRunState.load() {
                if state.isResumable, let dish = library.dish(id: state.dishID), library.plan(for: dish) != nil {
                    resumed = state
                    showsResumed = true
                } else {
                    CookRunState.clear()
                }
            }
        }
        .appSheet(isPresented: $showsResumed) {
            if let state = resumed, let dish = library.dish(id: state.dishID), let plan = library.plan(for: dish) {
                CookModeView(plan: plan, restoring: state)
            }
        }
    }
}

/// The cook's own dishes, then the examples, each with its verdict.
struct DishListView: View {
    let library: CookLibrary
    @State var showsSettings = false
    /// The dish in the editor; kept apart from the sheet's visibility.
    @State var editing = KitchenDish(name: "", tasks: [])
    @State var showsEditor = false
    @State var showsPicker = false
    @State var pickedURL: URL?
    @State var pickedName: String?
    @State var pickedType: String?
    @State var exportURL: URL?
    @State var showsExporter = false
    @State var report = ""
    @State var showsReport = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            WarmBackground().ignoresSafeArea()
            list
        }
        .navigationTitle(String(localized: "Gerichte", bundle: .module))
        .toolbar {
            // Android shows two items at the top; the rest goes in the menu.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = KitchenDish(name: "", createdAt: Date(), tasks: [])
                    showsEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text(String(localized: "Neues Gericht", bundle: .module)))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(String(localized: "Gerichte sichern", bundle: .module)) {
                        exportURL = library.exportFile(of: library.ownDishes)
                        if exportURL != nil { showsExporter = true }
                    }
                    .disabled(library.ownDishes.isEmpty)
                    Button(String(localized: "Gerichte importieren", bundle: .module)) {
                        showsPicker = true
                    }
                    Button(String(localized: "Einstellungen", bundle: .module)) {
                        showsSettings = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(Text(String(localized: "Mehr", bundle: .module)))
            }
        }
        .appSheet(isPresented: $showsSettings) {
            KitchenSettingsView(library: library)
        }
        .appSheet(isPresented: $showsEditor) {
            DishEditorView(library: library, dish: editing) { dish in
                library.save(dish)
            }
        }
        .withDocumentPicker(isPresented: $showsPicker,
                            allowedContentTypes: [.json, .data],
                            selectedDocumentURL: $pickedURL,
                            selectedFilename: $pickedName,
                            selectedFileMimeType: $pickedType)
        .onChange(of: pickedURL) { _, url in
            guard let url else { return }
            pickedURL = nil
            report = library.importFile(at: url)
            showsReport = true
        }
        // No completion: handing SkipKit's Result back from Kotlin to Swift
        // crashed the app (SIGTRAP in SkipBridge's Pair bridging, skip-kit
        // 1.1.6/1.1.7, 26.11.2026). The system's "save as" confirms itself.
        .withDocumentExporter(isPresented: $showsExporter, contentType: .data, documentURL: exportURL)
        .alert(String(localized: "Gerichte", bundle: .module), isPresented: $showsReport) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            Text(report)
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
