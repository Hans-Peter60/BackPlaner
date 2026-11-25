//
//  DishListView.swift
//  CookPlanner
//
//  The cook's own dishes and the examples, each with its verdict for the
//  current budget and kitchen. Own dishes can be edited and removed; an
//  example can be taken as a template.
//

import BakePlannerCore
import SwiftUI
import UniformTypeIdentifiers

struct DishListView: View {

    @Environment(DishLibrary.self) private var library
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens
    @State private var showsSettings = false
    /// The tab bar's selection: a file or a page handed to the app brings
    /// the dish list forward.
    var selectedTab: Binding<CookTab>? = nil
    /// The search and the facets, as in BakePlanner's recipe list.
    @State private var searchText = ""
    @State private var filter = KitchenDishFilter()
    @State private var savedCollections = SavedDishCollectionStore()
    @State private var runLog = CookRunLog.shared
    /// "Sammlung sichern" and "Umbenennen" ask for a name.
    @State private var namingCollection = false
    @State private var renaming: SavedKitchenDishCollection?
    @State private var collectionName = ""
    /// The dish being edited in the sheet: a new one, a copy of an
    /// example, or one of the cook's own.
    @State private var editing: KitchenDish?
    @State private var importing = false
    @State private var importingPhotos = false
    @State private var importingWeb = false
    /// A page address handed in by the share extension or a link to the app.
    @State private var webImportAddress: URL?
    @State private var webImportStartsAutomatically = false
    @Environment(\.scenePhase) private var scenePhase
    /// The dish the import handed over, opened in the editor once the
    /// import sheet is gone.
    @State private var pendingImport: KitchenDish?
    /// What reading a .cookplanner file opened from outside came to.
    @State private var fileImportReport: String?

    private func plan(for dish: KitchenDish) -> DishPlan? {
        DishPlan(dish: dish, budget: budget, burners: burners, ovens: ovens)
    }

    private var isFiltering: Bool {
        filter.isActive || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether the dish passes the search and the facets; the facets are
    /// read from its plan with the current kitchen.
    private func passes(_ dish: KitchenDish) -> Bool {
        guard KitchenDishFilter.matches(dish, searchText: searchText) else { return false }
        guard filter.isActive else { return true }
        guard let plan = plan(for: dish) else { return false }
        return filter.matches(KitchenDishFacets(dish: dish, schedule: plan.schedule),
                              history: KitchenDishFilter.History(dishID: dish.id, runs: runLog.runs))
    }

    private var shownOwnDishes: [KitchenDish] { library.dishes.filter(passes) }
    private var shownExamples: [KitchenDish] { KitchenSampleDishes.all.filter(passes) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let warning = library.storageWarning {
                        Label { Text(warning) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    Text("Ein Gericht, eine Person, \(budget) Minuten")
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.subtitle)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    collectionChips
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                }
                if isFiltering && shownOwnDishes.isEmpty && shownExamples.isEmpty {
                    ContentUnavailableView("Keine passenden Gerichte", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Passe die Suche oder die Filter an."))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !shownOwnDishes.isEmpty {
                    Section {
                        ForEach(shownOwnDishes) { dish in
                            row(dish)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        library.delete(id: dish.id)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        editing = dish
                                    } label: {
                                        Label("Bearbeiten", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        library.delete(id: dish.id)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        sectionTitle("Meine Gerichte")
                    }
                }
                if !shownExamples.isEmpty {
                Section {
                    ForEach(shownExamples) { dish in
                        row(dish)
                            .contextMenu {
                                Button {
                                    editing = dish.duplicate()
                                } label: {
                                    Label("Als Vorlage übernehmen", systemImage: "doc.on.doc")
                                }
                            }
                    }
                } header: {
                    sectionTitle("Beispiele")
                }
                }
            }
            // Always shown: with a tab bar iOS would hide it until the list is pulled down.
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Gericht, Komponente oder Zutat"))
            .listStyle(.plain)
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle("Gerichte")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editing = KitchenDish(name: "", createdAt: .now, tasks: [])
                        } label: {
                            Label("Neues Gericht", systemImage: "square.and.pencil")
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("Aus Text importieren", systemImage: "text.viewfinder")
                        }
                        Button {
                            importingPhotos = true
                        } label: {
                            Label("Aus Fotos importieren", systemImage: "camera")
                        }
                        Button {
                            importingWeb = true
                        } label: {
                            Label("Aus Webseite importieren", systemImage: "globe")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Hinzufügen")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        filterMenu
                    } label: {
                        Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill"
                                                          : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showsSettings) {
                KitchenSettingsView()
            }
            .sheet(item: $editing) { dish in
                DishEditorView(dish: dish) { saved in
                    library.save(saved)
                }
            }
            .sheet(isPresented: $importing, onDismiss: {
                if let pendingImport {
                    editing = pendingImport
                    self.pendingImport = nil
                }
            }) {
                DishTextImportView { dish in
                    pendingImport = dish
                }
            }
            .sheet(isPresented: $importingPhotos, onDismiss: {
                if let pendingImport {
                    editing = pendingImport
                    self.pendingImport = nil
                }
            }) {
                DishTextImportView(startsWithPhotos: true) { dish in
                    pendingImport = dish
                }
            }
            .sheet(isPresented: $importingWeb, onDismiss: {
                if let pendingImport {
                    editing = pendingImport
                    self.pendingImport = nil
                }
            }) {
                DishWebImportView(address: webImportAddress, startsAutomatically: webImportStartsAutomatically) { dish in
                    pendingImport = dish
                }
            }
            // The share extension opens the app with the page's address; the
            // same address is parked in the App Group, and only when it is
            // there did the link come from the extension — any web page can
            // open cookplanner://import-web, and then the analysis waits
            // for a tap.
            .onOpenURL { url in
                selectedTab?.wrappedValue = .dishes
                // A .cookplanner file tapped in Mail, Messages or Files.
                if url.isFileURL {
                    showsSettings = false
                    fileImportReport = library.importDishes(at: url)
                    return
                }
                guard let pageURL = PendingDishImport.url(fromDeepLink: url) else { return }
                beginWebImport(of: pageURL, startsAutomatically: PendingDishImport.takePending() == pageURL)
            }
            // The extension may have been unable to open the app; the parked
            // address is collected when the app comes forward.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, let pageURL = PendingDishImport.takePending() {
                    selectedTab?.wrappedValue = .dishes
                    beginWebImport(of: pageURL, startsAutomatically: true)
                }
            }
            .alert("Gerichte importieren",
                   isPresented: Binding(get: { fileImportReport != nil }, set: { if !$0 { fileImportReport = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(fileImportReport ?? "")
            }
            .alert("Sammlung sichern", isPresented: $namingCollection) {
                TextField("Name", text: $collectionName)
                Button("Sichern") { savedCollections.add(name: collectionName, filter: filter) }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Die gewählten Filter erscheinen als eigene Sammlung in der Leiste.")
            }
            .alert("Sammlung umbenennen", isPresented: Binding(get: { renaming != nil },
                                                                set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $collectionName)
                Button("Umbenennen") {
                    if let renaming { savedCollections.rename(renaming.id, to: collectionName) }
                }
                Button("Abbrechen", role: .cancel) { }
            }
            .alert("Speichern fehlgeschlagen",
                   isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(library.lastError ?? "")
            }
        }
    }

    // MARK: Selection

    /// The ready-made collections, then the saved ones; a tap sets the
    /// filter, a second tap clears it.
    private var collectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(KitchenDishCollection.allCases) { collection in
                    let isOn = filter == collection.filter
                    Button {
                        filter = isOn ? KitchenDishFilter() : collection.filter
                    } label: {
                        chipLabel(Text(collection.title), systemImage: collection.systemImage, isOn: isOn)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(savedCollections.collections) { collection in
                    let isOn = filter == collection.filter
                    Button {
                        filter = isOn ? KitchenDishFilter() : collection.filter
                    } label: {
                        chipLabel(Text(verbatim: collection.name), systemImage: "bookmark", isOn: isOn)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Umbenennen", systemImage: "pencil") {
                            collectionName = collection.name
                            renaming = collection
                        }
                        Button("Sammlung löschen", systemImage: "trash", role: .destructive) {
                            if filter == collection.filter { filter = KitchenDishFilter() }
                            savedCollections.remove(collection.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chipLabel(_ title: Text, systemImage: String, isOn: Bool) -> some View {
        Label { title } icon: { Image(systemName: systemImage) }
            .font(Theme.bodyFont(14).weight(isOn ? .semibold : .regular))
            .foregroundColor(isOn ? .white : Theme.cardTitle)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? AnyShapeStyle(Theme.accentBottom) : AnyShapeStyle(Theme.card.opacity(0.8)),
                        in: Capsule())
            .overlay(Capsule().stroke(Theme.accentText.opacity(isOn ? 0 : 0.25), lineWidth: 1))
    }

    /// The facets, one submenu each with "Alle" first, then the switches,
    /// resetting and saving.
    @ViewBuilder
    private var filterMenu: some View {
        if filter.isActive {
            Button("Filter zurücksetzen", systemImage: "xmark.circle") { filter = KitchenDishFilter() }
            if savedCollections.collection(matching: filter) == nil {
                Button("Sammlung sichern", systemImage: "bookmark") {
                    collectionName = ""
                    namingCollection = true
                }
            }
            Divider()
        }
        Picker("Dauer", selection: $filter.duration) {
            Text("Alle").tag(KitchenDishFacets.Duration?.none)
            Text("Bis 30 Minuten").tag(KitchenDishFacets.Duration?.some(.quick))
            Text("31 bis 45 Minuten").tag(KitchenDishFacets.Duration?.some(.medium))
            Text("46 bis 60 Minuten").tag(KitchenDishFacets.Duration?.some(.long))
            Text("Über eine Stunde").tag(KitchenDishFacets.Duration?.some(.longer))
        }
        .pickerStyle(.menu)
        Picker("Geräte", selection: $filter.equipment) {
            Text("Alle").tag(KitchenDishFacets.Equipment?.none)
            Text("Mit Ofen").tag(KitchenDishFacets.Equipment?.some(.oven))
            Text("Nur Herd").tag(KitchenDishFacets.Equipment?.some(.stoveOnly))
            Text("Ohne Hitze").tag(KitchenDishFacets.Equipment?.some(.noHeat))
        }
        .pickerStyle(.menu)
        Picker("Herkunft", selection: $filter.origin) {
            Text("Alle").tag(KitchenDishFacets.Origin?.none)
            Text("Eigene").tag(KitchenDishFacets.Origin?.some(.own))
            Text("Importiert").tag(KitchenDishFacets.Origin?.some(.imported))
            Text("Beispiele").tag(KitchenDishFacets.Origin?.some(.example))
        }
        .pickerStyle(.menu)
        Picker("Verlauf", selection: $filter.history) {
            Text("Alle").tag(KitchenDishFilter.HistoryChoice?.none)
            Text("Noch nie gekocht").tag(KitchenDishFilter.HistoryChoice?.some(.never))
            Text("Lange nicht gekocht").tag(KitchenDishFilter.HistoryChoice?.some(.longAgo))
            Text("Lieblinge").tag(KitchenDishFilter.HistoryChoice?.some(.favourites))
        }
        .pickerStyle(.menu)
        Divider()
        Toggle("Passt ins Budget", isOn: $filter.fitsBudgetOnly)
        Toggle("Wenig Handarbeit", isOn: $filter.lowWorkOnly)
    }

    /// Every dish gets a row. One the scheduler cannot plan — a step
    /// waiting for a deleted one, an oven dish in a kitchen set to no oven
    /// — shows why, and still opens, so it can be edited or deleted.
    private func row(_ dish: KitchenDish) -> some View {
        NavigationLink {
            DishPlanView(dish: dish)
        } label: {
            if let plan = plan(for: dish) {
                DishRow(plan: plan)
            } else {
                UnplannableDishRow(dish: dish, reason: DishPlan.failure(dish: dish, budget: budget, burners: burners, ovens: ovens))
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.brandFont(18))
            .foregroundColor(Theme.title)
            .textCase(nil)
    }

    /// Opens the web import with `pageURL` in its field, closing whatever
    /// sheet is in front.
    private func beginWebImport(of pageURL: URL, startsAutomatically: Bool) {
        showsSettings = false
        editing = nil
        importing = false
        webImportAddress = pageURL
        webImportStartsAutomatically = startsAutomatically
        importingWeb = true
    }
}

private struct DishRow: View {
    let plan: DishPlan

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: plan.fits ? "checkmark.circle" : "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: plan.dish.name)
                    .font(Theme.bodyFont(16).weight(.semibold))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !plan.dish.components.isEmpty {
                    Text(verbatim: plan.dish.components.joined(separator: " · "))
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.subtitle)
                }
                if plan.dish.tasks.isEmpty {
                    Text("Noch keine Schritte")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                        .padding(.top, 2)
                } else {
                    Text(plan.verdict)
                        .font(Theme.bodyFont(14).weight(.semibold))
                        .foregroundColor(plan.fits ? Theme.good : Theme.danger)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// A dish without a plan: its name and the reason, in the same card.
private struct UnplannableDishRow: View {
    let dish: KitchenDish
    let reason: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: dish.name)
                    .font(Theme.bodyFont(16).weight(.semibold))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason ?? "Der Plan geht nicht auf.")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// Budget and kitchen, the few numbers a plan depends on.
struct KitchenSettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens
    @AppStorage(CookSettings.alarmsKey) private var alarms = CookSettings.defaultAlarms
    @Environment(DishLibrary.self) private var library
    @State private var choosingFile = false
    @State private var importReport: String?
    @State private var sync = CloudSync.shared

    private var syncStatusText: String {
        switch sync.status {
        case .available:
            if let last = sync.lastSync {
                return String(localized: "Abgeglichen \(last.formatted(date: .omitted, time: .shortened))")
            }
            return String(localized: "Angemeldet")
        case .noAccount: return String(localized: "Nicht angemeldet")
        case .restricted: return String(localized: "Nicht verfügbar")
        case .failed(let message): return message
        case .unknown: return String(localized: "Wird geprüft …")
        }
    }

    private var ownDishes: [KitchenDish] { library.dishes.filter { $0.source != .sample } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitbudget") {
                    Stepper(value: $budget, in: 10...180, step: 5) {
                        Text("\(budget) Minuten")
                    }
                }
                Section("Küche") {
                    Stepper(value: $burners, in: 1...8) {
                        Text("Platten: \(burners)")
                    }
                    Stepper(value: $ovens, in: 0...3) {
                        Text("Öfen: \(ovens)")
                    }
                    Text("Die Öfen sind vorgeheizt, wenn die Uhr startet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section {
                    ShareLink(item: DishFileExport(dishes: ownDishes),
                              preview: SharePreview(Text("Meine Gerichte"))) {
                        Label("Eigene Gerichte sichern", systemImage: "square.and.arrow.up")
                    }
                    .disabled(ownDishes.isEmpty)
                    Button {
                        choosingFile = true
                    } label: {
                        Label("Gerichte importieren", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Sicherung")
                } footer: {
                    Text("Die Sicherung ist eine Datei mit allen eigenen Gerichten, z. B. für iCloud Drive. Beim Importieren bleiben Gerichte, die schon da sind, unverändert. Die Kochprotokolle sind nicht enthalten.")
                }
                Section {
                    LabeledContent("iCloud") {
                        Text(syncStatusText)
                    }
                    Button {
                        Task { await sync.fetchNow() }
                    } label: {
                        Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(sync.status != .available)
                } header: {
                    Text("Abgleich")
                } footer: {
                    Text("Eigene Gerichte, Kochprotokolle und Fotos gleichen sich über iCloud zwischen allen Geräten mit derselben Apple-ID ab. Die Einstellungen bleiben je Gerät.")
                }
                Section {
                    Toggle("Wecker für Topf und Ofen", isOn: $alarms)
                } footer: {
                    Text("Wenn ein Topf oder der Ofen die Zeit erreicht hat, klingelt ein Wecker – auch wenn das iPhone stumm ist oder ein Fokus läuft. Ohne Wecker gibt es eine Mitteilung.")
                }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.cookPlannerDishes, .json]) { result in
                if case .success(let url) = result {
                    importReport = library.importDishes(at: url)
                }
            }
            .alert("Gerichte importieren",
                   isPresented: Binding(get: { importReport != nil }, set: { if !$0 { importReport = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importReport ?? "")
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DishListView()
        .environment(DishLibrary(store: InMemoryKitchenDishStore()))
}
