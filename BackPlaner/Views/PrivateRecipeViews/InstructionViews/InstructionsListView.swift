//
//  InstructionsListView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.12.21.
//

import SwiftUI

struct InstructionsListView: View {
    
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
                return r.name.contains(filterBy)
            }
        }
    }

    var body: some View {
        
        NavigationView {
            
            VStack (alignment: .leading) {
                Text("Backauswahl")
                    .bold()
                    .padding(.top, 40)
                    .font(Font.custom("Avenir Heavy", size: 24))
                
                SearchBarView(filterBy: $filterBy)
                    .padding([.trailing, .bottom])
                
                ScrollView {
                    LazyVStack (alignment: .leading) {
                        ForEach(filteredRecipes) { r in
                            NavigationLink(
                                destination: InstructionsView(recipe: r),
                                label: {
                                    
                                    // MARK: Row item
                                    HStack(spacing: 20.0) {
                                        let image = UIImage(data: r.image ?? Data()) ?? UIImage()
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50, alignment: .center)
                                            .clipped()
                                            .cornerRadius(5)
                                        
                                        VStack (alignment: .leading) {
                                            Text(r.name)
                                                .font(Font.custom("Avenir Heavy", size: 16))
                                                .multilineTextAlignment(.leading)
                                            
                                            RecipeTags(tags: r.tags)
                                                .font(Font.custom("Avenir", size: 12))
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .padding(.leading)
            .onTapGesture {
                // Resign first responder
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
}
