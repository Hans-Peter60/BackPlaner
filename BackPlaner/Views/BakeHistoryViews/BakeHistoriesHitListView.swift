//
//  BakeHistoriesView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 06.12.21.


import SwiftUI
import CoreData

struct BakeHistoriesHitListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(format: "bakeHistoryFlag == true"))
    private var recipes: FetchedResults<Recipe>
    
    @State private var filterBy           = ""
    @State private var nameOrTag          = 1
    @State private var rating             = 0
    @State private var bakeHistoryImages  = [Data]()
    
    private var filteredRecipes: [Recipe] {

        let search = filterBy.trimmingCharacters(in: .whitespacesAndNewlines)

        // No filter text, so only apply the rating threshold
        if search.isEmpty {
            return recipes.filter { $0.rating >= rating }
        }

        // Filter by the search term and return a subset of recipes whose name
        // or tags contain it. The rating threshold keeps applying, so the two
        // filters can be combined.
        return recipes.filter { r in

            guard r.rating >= rating else { return false }

            if nameOrTag == 1 {
                return r.name.localizedCaseInsensitiveContains(search)
            }
            return r.tags.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    
    var gridItemLayout       = [GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 180), alignment: .leading)]
    var gridItemLayoutImages = [GridItem(.fixed(54), alignment: .leading), GridItem(.fixed(54), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    @State private var confirmationShown = false
    
    var body: some View {
        
        VStack(spacing: 0) {

        LazyVGrid(columns: gridItemLayout, spacing: 6) {
            
            Text("")
            Text("Rezept")
            Text("Anzahl")
            Text("")
            Text("")
            Text("")
        }
        .padding(.leading, 28)
        .font(Theme.brandFont(18))
        
        List {
            
            ForEach(filteredRecipes.sorted(by: { $0.bakeHistories.count > $1.bakeHistories.count } )) { recipe in
                
                if recipe.bakeHistories.count > 0 {
                    
                    VStack {
                        
                        LazyVGrid(columns: gridItemLayout, spacing: 6) {
                            
                            Text("")
                            Text(recipe.name)
                                .font(Theme.brandFont(16))
                            Text(String(recipe.bakeHistories.count))
                                .font(Theme.bodyFont(16))
                        }
                        
                        HStack {
                            
                            ForEach(recipe.bakeHistories.allObjects as? [BakeHistory] ?? [] ) { bakeHistory in
                                
                                if bakeHistory.images != nil {

                                    // MARK: History Images
                                    ForEach(bakeHistory.images!, id: \.self) { image in

                                        let i = UIImage(data: image) ?? UIImage()
                                        Image(uiImage: i)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50, alignment: .center)
                                            .clipped()
                                            .cornerRadius(5)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 292)
                    }
                }
                else {
                    Text("")
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .clearScrollBackground()
        }
        .warmBackground()
        .navigationTitle("Back Hit-Liste")
        .searchable(text: $filterBy, prompt: "Rezept suchen")
        .searchScopes($nameOrTag) {
            Text("Name").tag(1)
            Text("Tags").tag(2)
        }
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Mindestbewertung", selection: $rating) {
                        Text("Alle Bewertungen").tag(0)
                        ForEach(1...5, id: \.self) { stars in
                            Text("\(stars) Sterne und mehr").tag(stars)
                        }
                    }
                } label: {
                    Label("Nach Bewertung filtern",
                          systemImage: rating > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}
