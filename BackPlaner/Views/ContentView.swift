//
//  ContentView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.02.24.
//

import SwiftUI
import CoreData

struct ContentView: View {
    
    @State private var tabSelection = 0
    
    @Environment(\.managedObjectContext) private var viewContext
    
    var manager:LocalNotificationManager = LocalNotificationManager()
    
    var recipeId: NSManagedObjectID?
    
    init() {
        manager.requestAuthorization()
    }
    
    // The menu entries that make up the main navigation of the app. Each one
    // carries its own destination, so the cards can be laid out in a loop —
    // they used to be eight hand-written links indexed into this array, which
    // could not be rearranged into rows without renumbering them.
    private let menuItems: [MenuItem] = [
        MenuItem(destination: .publicRecipes,  title: "Rezept-Datenbank",     subtitle: "Öffentliche Rezepte durchsuchen", systemImage: "books.vertical.fill"),
        MenuItem(destination: .ownRecipes,     title: "Eigene Rezepte",       subtitle: "Deine gespeicherten Rezepte",     systemImage: "book.closed.fill"),
        MenuItem(destination: .newRecipe,      title: "Neues Rezept anlegen", subtitle: "Ein Rezept von Grund auf erstellen", systemImage: "plus.circle.fill"),
        MenuItem(destination: .scheduledSteps, title: "Geplante Schritte",    subtitle: "Als Liste oder Timeline",         systemImage: "calendar"),
        MenuItem(destination: .bakeHistory,    title: "Backhistorie",         subtitle: "Vergangene Backvorgänge",         systemImage: "clock.arrow.circlepath"),
        MenuItem(destination: .hitList,        title: "Back Hit-Liste",       subtitle: "Deine besten Rezepte",            systemImage: "star.fill"),
        MenuItem(destination: .shoppingList,   title: "Einkaufsliste",        subtitle: "Zutaten zum Einkaufen",           systemImage: "cart.fill"),
        MenuItem(destination: .settings,       title: "Einstellungen",        subtitle: "Sprache und App-Defaults",        systemImage: "gearshape.fill")
    ]

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize)     private var dynamicTypeSize

    /// How many cards stand side by side. One full-width column per card fills
    /// an iPhone, but on a 13-inch iPad it left the bottom half of the screen
    /// empty. At the accessibility text sizes a card is tall enough on its own.
    private var columnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return hSize == .regular ? 2 : 1
    }

    private var rows: [[MenuItem]] {
        stride(from: 0, to: menuItems.count, by: columnCount).map { start in
            Array(menuItems[start ..< min(start + columnCount, menuItems.count)])
        }
    }

    var body: some View {

        NavigationStack {

            GeometryReader { fullView in

            ScrollView(showsIndicators: false) {

                VStack(spacing: 14) {

                    header

                    // An eager Grid, not a LazyVGrid: a lazy one reports its
                    // size only once its cells exist, which on iPad arrives a
                    // layout pass too late.
                    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                ForEach(row) { item in
                                    NavigationLink {
                                        destination(for: item.destination)
                                    } label: {
                                        // Deliberately no maxHeight here: with
                                        // the centring frame below, a card that
                                        // may grow absorbs the leftover screen
                                        // height and the rows drift apart.
                                        MenuCard(item: item)
                                    }
                                }

                                // A short last row keeps the column widths of a
                                // full one instead of stretching its card.
                                if row.count < columnCount {
                                    ForEach(row.count ..< columnCount, id: \.self) { _ in
                                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                // Two columns halve the height the menu needs, which on a
                // 13-inch iPad left 64 % of the screen empty below it — more
                // than the single column did. Centring the block uses that
                // space instead of stacking everything against the top.
                // `minHeight` and not `height`: when the cards are taller than
                // the screen — an iPhone, or any accessibility text size — this
                // has no effect and the screen scrolls as before.
                .frame(minHeight: fullView.size.height, alignment: .center)
            }
            .warmBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)

            }
        }
        .environmentObject(RecipeModel())
        .environmentObject(RecipeFBModel())
    }

    @ViewBuilder
    private func destination(for destination: MenuDestination) -> some View {
        switch destination {
        case .publicRecipes:  RecipeFBListView()
        case .ownRecipes:     RecipeListView()
        case .newRecipe:      AddNewRecipeDataView()
        case .scheduledSteps: ScheduledTasksTabsView()
        case .bakeHistory:    BakeHistoriesListView()
        case .hitList:        BakeHistoriesHitListView()
        case .shoppingList:   ShoppingCartsView()
        case .settings:       SettingsView()
        }
    }
    
    // A branded header shown above the menu cards.
    private var header: some View {
        ScreenHeader(brand: "BakePlanner",
                     subtitle: "Plane und backe dein perfektes Brot")
    }
}

/// Where a menu entry leads. Named rather than positional so the cards can be
/// reordered or regrouped without the destinations following along by accident.
enum MenuDestination {
    case publicRecipes
    case ownRecipes
    case newRecipe
    case scheduledSteps
    case bakeHistory
    case hitList
    case shoppingList
    case settings
}

// A single navigation entry shown on the main screen.
struct MenuItem: Identifiable {
    let destination: MenuDestination
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String

    var id: String { systemImage }
}

// A styled card used for each menu entry, giving the whole screen a
// consistent, professional look.
struct MenuCard: View {
    
    let item: MenuItem

    // At the accessibility text sizes the badge, the two lines of text and the
    // chevron no longer fit on one line — the title wraps around the badge and
    // the card clips. Stack everything instead.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 16))

        return layout {

            // Icon badge.
            IconBadge(systemImage: item.systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(Theme.cardTitle)

                Text(item.subtitle)
                    .font(.caption)
                    // .secondary only reaches 3.4:1 on the white card.
                    .foregroundColor(Theme.subtitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.subtitle)
                    .accessibilityHidden(true)
            }
        }
        .cardStyle()
        // Title and subtitle describe one destination: announce the card as
        // a single link rather than as two separate texts.
        .accessibilityElement(children: .combine)
    }
}
