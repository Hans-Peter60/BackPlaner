//
//  BakeHistoriesHitListView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.02.22.
//

import SwiftUI
import CoreData

struct BakeHistoriesListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(format: "recipe != nil"))
    private var bakeHistories: FetchedResults<BakeHistory>
    
    @State private var filterBy           = ""
    @State private var nameOrTag          = 1
    @State private var rating             = 0
    @State private var bakeHistoryComment = ""
    @State private var bakeHistoryImages  = [Data]()
    
    @State var isBigImageShowing          = false
    
    private var filteredBakeHistories: [BakeHistory] {
        
        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            // No filter text, so return all recipes (skip any history without a recipe)
            return bakeHistories.filter { b in
                guard let recipe = b.recipe else { return false }
                return recipe.rating >= rating
            }
        }
        else {
            // Filter by the search term and return
            // a subset of recipes which contain the search term in the name
            if nameOrTag == 1 {
                return bakeHistories.filter { b in
                    guard let recipe = b.recipe else { return false }
                    return recipe.name.contains(filterBy)
                }
            }
            else {
                return bakeHistories.filter { b in
                    guard let recipe = b.recipe else { return false }
                    return recipe.tags.contains(filterBy)
                }
            }
        }
    }
    
    var gridItemLayout = [
        GridItem(.fixed(76), alignment: .leading),
        GridItem(.flexible(minimum: 80), alignment: .leading),
        GridItem(.flexible(minimum: 80), alignment: .leading)
    ]
    var gridItemLayoutImages = [GridItem(.fixed(54), alignment: .leading), GridItem(.fixed(54), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    @State private var confirmationShown = false
    
    var body: some View {
        
        VStack(spacing: 0) {

        LazyVGrid(columns: gridItemLayout, spacing: 6) {
            
            Text("Datum")
            Text("Rezept")
            Text("Kommentar")
            Text(verbatim: "")
            Text(verbatim: "")
            Text(verbatim: "")
        }
        .padding(.horizontal, 16)
        .font(Theme.brandFont(18))
        
        List {
            
            ForEach(filteredBakeHistories, id: \.self) { bakeHistory in
                
                NavigationLink(
                    destination: BakeHistoryUpdateFormView(recipeName: bakeHistory.recipe?.name ?? "", bakeHistory: bakeHistory)
                        .environment(\.managedObjectContext, self.viewContext),
                    label: {
                        
                        VStack {
                            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                                
                                Text(dateFormat.calculateDate(dT: bakeHistory.date))
                                    .font(Theme.brandFont(16))
                                Text(bakeHistory.recipe?.name ?? "")
                                    .font(Theme.brandFont(16))
                                Text(bakeHistory.comment)
                                    .font(Theme.bodyFont(16))
                            }
                            HStack {
                                
                                if bakeHistory.images != nil {
                                    
                                    // MARK: History Images
                                    ForEach(bakeHistory.images!, id: \.self) { image in
                                        
                                        NavigationLink(
                                            destination: ShowBigImagesView(images: bakeHistory.images!, index: 0)
                                        )
                                        {
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
                                else {
                                    Image(systemName: "photo")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50, alignment: .center)
                                        .clipped()
                                        .cornerRadius(5)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    })
            }
            .onDelete { indexSet in
                guard let index = indexSet.first, filteredBakeHistories.indices.contains(index) else { return }
                let deleteBakeHistory = self.filteredBakeHistories[index]
                
                self.viewContext.delete(deleteBakeHistory)

                do {
                    try viewContext.save()
                }
                catch {
                    // handle the Core Data error
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

        }
        .listStyle(.plain)
        .clearScrollBackground()
        }
        .warmBackground()
        .navigationTitle("Backhistorie")
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
