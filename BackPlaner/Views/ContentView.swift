//
//  ContentView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.02.24.
//
//  The root of the app: a tab bar with the four places a baker goes every
//  day — recipes, shopping lists, bake history, planned steps — each in its
//  own navigation stack, so a tab keeps its place when another is visited.
//  The calculators and the settings sit behind "Mehr" in the recipe list,
//  a new recipe behind "+". Until 2.2 the app opened on a menu of nine
//  cards; the tab bar is what the Android app had from the start and what
//  turned out to be the quicker way around.
//

import BakePlannerCore
import SwiftUI
import CoreData

/// The tabs of the root, in their order.
enum AppTab: Hashable {
    case recipes, shoppingLists, bakeHistory, scheduledSteps
}

struct ContentView: View {

    @State private var selectedTab = AppTab.recipes

    /// The recipe tab's stack. Pushed programmatically when the share
    /// extension hands a page over; the list's own links navigate by view.
    @State private var recipesPath = NavigationPath()

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase

    /// The last page handed over by the share extension and when: its deep
    /// link and the parked copy of the same address can both arrive within
    /// one launch, and the second must not start the import again.
    @State private var lastWebImportURL: URL?
    @State private var lastWebImportDate = Date.distantPast

    /// Shown once at launch when the store on disk could not be opened and
    /// the app runs on an empty one (see PersistenceController.loadError).
    @State private var showStoreError = PersistenceController.shared.loadError != nil

    var manager:LocalNotificationManager = LocalNotificationManager()

    init() {
        manager.requestAuthorization()
    }

    var body: some View {

        TabView(selection: $selectedTab) {

            Tab("Rezepte", systemImage: "books.vertical.fill", value: .recipes) {
                NavigationStack(path: $recipesPath) {
                    AllRecipesListView()
                        // The next planned step floats as a Liquid Glass
                        // bar over the bottom edge of the recipe list: the
                        // rows scroll underneath it, and the countdown stays
                        // in view. Only present while a step is ahead or
                        // just due. On the list, not the stack, so a recipe
                        // opened from the list is not covered by it.
                        .safeAreaBar(edge: .bottom) {
                            NextStepCardView {
                                selectedTab = .scheduledSteps
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        .navigationDestination(for: MenuDestination.self) { destination in
                            MenuDestinationView(destination: destination)
                        }
                }
            }

            Tab("Einkaufslisten", systemImage: "cart.fill", value: .shoppingLists) {
                NavigationStack {
                    // Shopping lists are a Pro feature; locked, the tab offers Pro.
                    ProLockedScreen(.shoppingList) { ShoppingCartsView() }
                }
            }

            Tab("Backhistorie", systemImage: "clock.arrow.circlepath", value: .bakeHistory) {
                NavigationStack {
                    BakeHistoriesListView()
                }
            }

            Tab("Zeitleiste", systemImage: "calendar", value: .scheduledSteps) {
                NavigationStack {
                    ScheduledTasksTabsView()
                }
            }
        }
        // accentText, not accentBottom: the tab bar keeps the system's own
        // background, so the tint has to be light in dark mode, not dark.
        .tint(Theme.accentText)
        // The widget's deep link goes straight to the planned steps; the
        // share extension's carries a page address for the web import.
        .onOpenURL { url in
            if url == PlanSnapshot.scheduledStepsURL {
                selectedTab = .scheduledSteps
            } else if let pageURL = PendingWebImport.url(fromDeepLink: url) {
                // The same address is parked in the App Group; take it so it
                // does not start a second import on the next activation.
                _ = PendingWebImport.takePending()
                beginWebImport(of: pageURL)
            }
        }
        // The share extension may have been unable to open the app; the
        // address it parked is collected when the app comes forward.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let pageURL = PendingWebImport.takePending() {
                beginWebImport(of: pageURL)
            }
        }
        .alert("Rezepte konnten nicht geladen werden", isPresented: $showStoreError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("BakePlanner konnte seinen Datenspeicher nicht öffnen und läuft vorübergehend ohne Deine Rezepte, Pläne und Einkaufslisten. Was Du jetzt anlegst, wird nicht gespeichert. Deine Daten bleiben erhalten: Prüfe, ob auf dem Gerät genug Speicher frei ist, und starte die App neu.")
        }
        .environmentObject(RecipeModel())
        .environmentObject(RecipeFBModel())
    }

    /// Opens the web import on `pageURL` in the recipe tab, replacing
    /// whatever was on screen there. Sharing the same page again later
    /// starts a fresh import; only the echo of the same hand-off within a
    /// few seconds is dropped.
    private func beginWebImport(of pageURL: URL) {
        if pageURL == lastWebImportURL, Date().timeIntervalSince(lastWebImportDate) < 5 { return }
        lastWebImportURL = pageURL
        lastWebImportDate = Date()
        AppLog.recipeImport.info("Web import handed over from the share sheet: \(pageURL.absoluteString, privacy: .private)")
        selectedTab = .recipes
        recipesPath = NavigationPath([MenuDestination.webImport(pageURL, handoff: UUID())])
    }
}

/// Where a screen reached from the recipe list leads: the entries of its
/// "Mehr" menu and "+", and the web import the share extension opens.
/// Named rather than positional so the entries can be reordered without
/// the destinations following along by accident.
enum MenuDestination: Hashable {
    case newRecipe
    case doughTemperature
    case flourSubstitution
    case starterYield
    case settings
    /// Not a menu entry: reached through the share extension, with the page
    /// to import. The hand-off id makes every share a new screen, so the
    /// same page shared twice is analysed twice instead of being ignored.
    case webImport(URL, handoff: UUID)
}

/// The screen behind a `MenuDestination`.
struct MenuDestinationView: View {
    let destination: MenuDestination

    var body: some View {
        switch destination {
        case .newRecipe:         AddNewRecipeDataView()
        case .doughTemperature:  DoughTemperatureCalculatorView()
        case .flourSubstitution: FlourSubstitutionCalculatorView()
        case .starterYield:      StarterYieldCalculatorView()
        case .settings:          SettingsView()
        case .webImport(let pageURL, let handoff):
            // Without an explicit identity the stack keeps the previous
            // import screen's state when one hand-off replaces another, and
            // the new address is never analysed.
            RecipeWebImportView(initialURL: pageURL).id(handoff)
        }
    }
}
