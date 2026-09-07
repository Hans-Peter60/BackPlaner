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
    
    // The menu entries that make up the main navigation of the app.
    private let menuItems: [MenuItem] = [
        MenuItem(title: "Rezept-Datenbank",     subtitle: "Öffentliche Rezepte durchsuchen", systemImage: "books.vertical.fill"),
        MenuItem(title: "Eigene Rezepte",       subtitle: "Deine gespeicherten Rezepte",     systemImage: "book.closed.fill"),
        MenuItem(title: "Neues Rezept anlegen", subtitle: "Ein Rezept von Grund auf erstellen", systemImage: "plus.circle.fill"),
        MenuItem(title: "Geplante Schritte",    subtitle: "Als Liste oder Timeline",         systemImage: "calendar"),
        MenuItem(title: "Backhistorie",         subtitle: "Vergangene Backvorgänge",         systemImage: "clock.arrow.circlepath"),
        MenuItem(title: "Back Hit-Liste",       subtitle: "Deine besten Rezepte",            systemImage: "star.fill"),
        MenuItem(title: "Einkaufsliste",        subtitle: "Zutaten zum Einkaufen",           systemImage: "cart.fill"),
        MenuItem(title: "Einstellungen",        subtitle: "Sprache und App-Defaults",        systemImage: "gearshape.fill")
    ]
    
    var body: some View {
        
        NavigationStack {

            ScrollView(showsIndicators: false) {

                VStack(spacing: 14) {

                    header

                    // Build a card for every menu entry, keeping the
                    // original navigation destinations intact.
                    NavigationLink(destination: RecipeFBListView())            { MenuCard(item: menuItems[0]) }
                    NavigationLink(destination: RecipeListView())              { MenuCard(item: menuItems[1]) }
                    NavigationLink(destination: AddNewRecipeDataView())        { MenuCard(item: menuItems[2]) }
                    NavigationLink(destination: ScheduledTasksTabsView())      { MenuCard(item: menuItems[3]) }
                    NavigationLink(destination: BakeHistoriesListView())       { MenuCard(item: menuItems[4]) }
                    NavigationLink(destination: BakeHistoriesHitListView())    { MenuCard(item: menuItems[5]) }
                    NavigationLink(destination: ShoppingCartsView())           { MenuCard(item: menuItems[6]) }
                    NavigationLink(destination: SettingsView())                 { MenuCard(item: menuItems[7]) }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .warmBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .environmentObject(RecipeModel())
        .environmentObject(RecipeFBModel())
    }
    
    // A branded header shown above the menu cards.
    private var header: some View {
        ScreenHeader(title: "Backplaner",
                     subtitle: "Plane und backe dein perfektes Brot")
    }
}

// A single navigation entry shown on the main screen.
struct MenuItem {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
}

// A styled card used for each menu entry, giving the whole screen a
// consistent, professional look.
struct MenuCard: View {
    
    let item: MenuItem
    
    var body: some View {
        HStack(spacing: 16) {

            // Icon badge.
            IconBadge(systemImage: item.systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(Theme.cardTitle)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .cardStyle()
    }
}
