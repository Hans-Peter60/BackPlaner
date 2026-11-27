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
    @State private var composingMenu = false
    /// The Pro feature whose paywall is showing.
    @State private var proOffer: CookProOffer?
    @State private var requests = AppRequests.shared
    @FocusState private var searchFocused: Bool
    /// A page address handed in by the share extension or a link to the app.
    @State private var webImportAddress: URL?
    @State private var webImportStartsAutomatically = false
    @Environment(\.scenePhase) private var scenePhase
    /// The dish the import handed over, opened in the editor once the
    /// import sheet is gone.
    @State private var pendingImport: KitchenDish?
    /// What reading a .cookplanner file opened from outside came to.
    @State private var fileImportReport: String?
    /// The dishes open on top of the list, by id — so Spotlight and Siri
    /// can open one.
    @State private var path: [String] = []
    /// The plans of the dishes as last computed, so a keystroke in the
    /// search does not schedule every dish anew several times per render.
    @State private var planCache = DishPlanCache()

    private func plan(for dish: KitchenDish) -> DishPlan? {
        planCache.plan(for: dish, budget: budget, burners: burners, ovens: ovens)
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
        NavigationStack(path: $path) {
            alerts(events(sheets(listContent)))
        }
    }

    /// The list with its search and its toolbar.
    private var listContent: some View {
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
            .searchFocused($searchFocused)
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
                        Divider()
                        Button {
                            withCookPro(.menu, offer: $proOffer) { composingMenu = true }
                        } label: {
                            Label("Menü zusammenstellen", systemImage: "list.number")
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
    }

    /// The sheets the list opens: editor, imports, settings, menu.
    private func sheets(_ view: some View) -> some View {
        view
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
    }

    /// Navigation, links from outside and the keyboard.
    private func events(_ view: some View) -> some View {
        view
            .navigationDestination(for: String.self) { id in
                if let dish = library.dish(id: id) ?? KitchenSampleDishes.all.first(where: { $0.id == id }) {
                    DishPlanView(dish: dish)
                } else {
                    ContentUnavailableView("Gericht nicht gefunden", systemImage: "fork.knife")
                }
            }
            .onOpenURL { url in
                selectedTab?.wrappedValue = .dishes
                // A .cookplanner file tapped in Mail, Messages or Files.
                if url.isFileURL {
                    showsSettings = false
                    fileImportReport = library.importDishes(at: url)
                    return
                }
                // Spotlight or Siri: a dish, perhaps straight into the cook mode.
                if let link = DishDeepLink.parse(url) {
                    showsSettings = false
                    AppRequests.shared.cookDishID = link.startsCooking ? link.dishID : nil
                    path = [link.dishID]
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
    }

    /// The alerts: import reports, collections, save failures.
    private func alerts(_ view: some View) -> some View {
        view
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
            // ⌘N, ⇧⌘N, ⌘, and ⇧⌘F from the keyboard.
            .onChange(of: requests.command) { _, command in handle(command) }
            .cookProPaywall($proOffer)
            .sheet(isPresented: $composingMenu) {
                MenuComposerView { menu in
                    if library.save(menu) { path = [menu.id] }
                }
            }
            .alert("Speichern fehlgeschlagen",
                   isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(library.lastError ?? "")
            }
    }

    /// ⌘N, ⇧⌘N, ⌘, and ⇧⌘F from the keyboard; ⌘⏎ is the plan's.
    private func handle(_ command: AppRequests.Command?) {
        guard let command else { return }
        switch command {
        case .newDish: editing = KitchenDish(name: "", createdAt: .now, tasks: [])
        case .newMenu: withCookPro(.menu, offer: $proOffer) { composingMenu = true }
        case .settings: showsSettings = true
        case .focusSearch: searchFocused = true
        case .startCooking: return
        }
        requests.command = nil
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
                    withCookPro(.collections, offer: $proOffer) {
                        collectionName = ""
                        namingCollection = true
                    }
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
        NavigationLink(value: dish.id) {
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

/// Plans by dish, reused while the dish and the kitchen are unchanged.
/// Scheduling tries several orderings per dish; the list asked for it
/// three or four times per render and dish, on every keystroke.
@MainActor
final class DishPlanCache {
    private struct Entry {
        let dish: KitchenDish
        let budget: Int, burners: Int, ovens: Int
        let plan: DishPlan?
    }
    private var entries: [String: Entry] = [:]

    func plan(for dish: KitchenDish, budget: Int, burners: Int, ovens: Int) -> DishPlan? {
        if let entry = entries[dish.id], entry.dish == dish, entry.budget == budget,
           entry.burners == burners, entry.ovens == ovens {
            return entry.plan
        }
        let plan = DishPlan(dish: dish, budget: budget, burners: burners, ovens: ovens)
        entries[dish.id] = Entry(dish: dish, budget: budget, burners: burners, ovens: ovens, plan: plan)
        return plan
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
    @State private var pro = CookPro.shared
    @State private var showingPro = false

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
                if pro.storeVisible {
                    Section {
                        Button {
                            showingPro = true
                        } label: {
                            HStack {
                                Label {
                                    Text(verbatim: "CookPlanner Pro")
                                } icon: {
                                    Image(systemName: pro.hasPurchased ? "checkmark.seal.fill" : "seal")
                                }
                                Spacer()
                                Text(pro.hasPurchased ? "Freigeschaltet" : "Mehr erfahren")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("Menü, Vorlesen und Sprachbefehle, Kochjahr-Buch, Statistik und mehr – einmal kaufen, kein Abo.")
                    }
                }
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
                    ShareLink(item: DishFileExport(dishes: ownDishes, includesRecords: true),
                              preview: SharePreview(Text("Meine Gerichte"))) {
                        Label("Gerichte und Protokolle sichern", systemImage: "square.and.arrow.up")
                    }
                    .disabled(ownDishes.isEmpty && CookRunLog.shared.runs.isEmpty)
                    Button {
                        choosingFile = true
                    } label: {
                        Label("Gerichte importieren", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Sicherung")
                } footer: {
                    Text("Die Sicherung ist eine Datei mit allen eigenen Gerichten, den Kochprotokollen und ihren Fotos, z. B. für iCloud Drive. Beim Importieren bleibt unverändert, was schon da ist.")
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
                    Text("Eigene Gerichte, Kochprotokolle und Fotos gleichen sich über iCloud zwischen allen Geräten mit derselben Apple-ID ab, ebenso die Einstellungen, Portionen und Sammlungen.")
                }
                Section {
                    Toggle("Wecker für Topf und Ofen", isOn: $alarms)
                } footer: {
                    Text("Wenn ein Topf oder der Ofen die Zeit erreicht hat, klingelt ein Wecker – auch wenn das iPhone stumm ist oder ein Fokus läuft. Ohne Wecker gibt es eine Mitteilung.")
                }
                // The help page, the privacy policy and the legal notice live
                // on the website, so they can be corrected without an update;
                // they open in Safari, as in BakePlanner. Privacy policy and
                // legal notice have to be reachable from inside the app.
                Section {
                    Link(destination: HelpLinks.cookPlannerManual) {
                        Label("Benutzerhandbuch", systemImage: "book")
                    }
                    Link(destination: HelpLinks.cookPlannerSupport) {
                        Label("Hilfe und Kontakt", systemImage: "questionmark.circle")
                    }
                    Link(destination: HelpLinks.cookPlannerPrivacy) {
                        Label("Datenschutzerklärung", systemImage: "hand.raised")
                    }
                    Link(destination: HelpLinks.imprint) {
                        Label("Impressum", systemImage: "building.columns")
                    }
                } header: {
                    Text("Hilfe")
                } footer: {
                    Text("Öffnet die Seiten im Browser.")
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
            .sheet(isPresented: $showingPro) {
                CookProPaywallView()
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
