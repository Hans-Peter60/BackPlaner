//
//  BakeHistoriesView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 06.12.21.


import SwiftUI

struct BakeHistoriesListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>
    
    @State private var filterBy = ""
    
    private var filteredRecipes: [Recipe] {
        
        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            // No filter text, so return all recipes
            return Array(recipes)
        }
        else {
            // Filter by the search term and return
            // a subset of recipes which contain the search term in the name
            return recipes.filter { r in
                return r.bakeHistories.contains(filterBy)
            }
        }
    }
    
    var gridItemLayout = [GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 180), alignment: .leading), GridItem(.fixed(80), alignment: .leading), GridItem(.fixed(160), alignment: .leading)]
    
    var dateFormat:DateFormat = DateFormat()
    
    var body: some View {
        
        Text("Backhistorie")
            .bold()
        
        SearchBarView(filterBy: $filterBy)
            .padding([.leading, .trailing, .bottom])
        
        ScrollView {
            
            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                
                Text("Datum").bold()
                Text("Rezept").bold()
                Text("Kommentar").bold()
                Text("Bilder").bold()
                Text("")
                
                ForEach(filteredRecipes) { recipe in
                    
                    if recipe.bakeHistories.count > 0 {
                        
                        ForEach(recipe.bakeHistories.allObjects as! [BakeHistory]) { bakeHistory in
                            
                            Text(dateFormat.calculateDate(dT: bakeHistory.date ?? Date()))
                                .font(Font.custom("Avenir Heavy", size: 14))
                            Text(recipe.name)
                                .font(Font.custom("Avenir Heavy", size: 14))
                            Text(bakeHistory.comment)
                                .font(Font.custom("Avenir", size: 14))
                            
                            HStack {
                                if bakeHistory.images.count > 0 {
                                    // MARK: History Images
                                    ForEach(0..<bakeHistory.images.count) { index in
                                        
                                        let image = UIImage(data: bakeHistory.images[index]) ?? UIImage()
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50, alignment: .center)
                                            .clipped()
                                            .cornerRadius(5)
                                    }
                                }
                                else {
                                    Image("no-image-icon-23494")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50, alignment: .center)
                                        .clipped()
                                        .cornerRadius(5)
                                }
                            }

                            Button("Löschen") {
                                
                                viewContext.delete(bakeHistory)

                                do {
                                    try viewContext.save()
                                } catch {
                                    // handle the Core Data error
                                }
                            }
                            .font(Font.custom("Avenir", size: 15))
                            .padding()
                            .foregroundColor(.gray)
                            .buttonStyle(.bordered)
                        }
                    }
                }
//                .padding()
            }
        }
        .padding()
    }
}

//struct BakeHistoriesListView_Previews: PreviewProvider {
//    static var previews: some View {
//        BakeHistoriesListView()
//            .environmentObject(RecipeModel())
//    }
//}
