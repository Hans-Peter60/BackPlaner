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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ein Gericht, eine Person, \(budget) Minuten")
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.subtitle)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !library.dishes.isEmpty {
                    Section {
                        ForEach(library.dishes) { dish in
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
                Section {
                    ForEach(KitchenSampleDishes.all) { dish in
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
                    beginWebImport(of: pageURL, startsAutomatically: true)
                }
            }
            .alert("Gerichte importieren",
                   isPresented: Binding(get: { fileImportReport != nil }, set: { if !$0 { fileImportReport = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(fileImportReport ?? "")
            }
            .alert("Speichern fehlgeschlagen",
                   isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(library.lastError ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(_ dish: KitchenDish) -> some View {
        if let plan = plan(for: dish) {
            NavigationLink {
                DishPlanView(dish: dish)
            } label: {
                DishRow(plan: plan)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
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
