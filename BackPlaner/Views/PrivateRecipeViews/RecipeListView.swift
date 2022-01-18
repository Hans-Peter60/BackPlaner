//
//  RecipeListView.swift
//  BackPlaner App
//
//  Created by Christopher Ching on 2021-01-14.
//

import SwiftUI
import CoreData

struct RecipeListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @EnvironmentObject var model:RecipeModel
    
    let viewModel = RecipeModel()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>
    
    @State private var filterBy  = ""
    @State private var nameOrTag = 1
    @State private var rating    = 0

    var recipeId: NSManagedObjectID?
    
    private var filteredRecipes: [Recipe] {
        
        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            // No filter text, so return all recipes
            return recipes.filter { r in
                return r.rating >= rating
            }
        }
        else {
            // Filter by the search term and return
            // a subset of recipes which contain the search term in the name
            if nameOrTag == 1 {
                return recipes.filter { r in
                    return r.name.contains(filterBy)
                }
            }
            else {
                return recipes.filter { r in
                    return r.tags.contains(filterBy)
                }
            }
        }
    }
    
    var body: some View {
        
        NavigationView {
            
            VStack (alignment: .leading) {
                
                Text("Eigene Rezepte")
                    .bold()
                    .padding(.top, 40)
                    .font(Font.custom("Avenir Heavy", size: 24))
                
                SearchBarView(filterBy: $filterBy, nameOrTag: $nameOrTag, rating: $rating, showRating: true)
                    .padding([.trailing, .bottom])

                ScrollView {
                    LazyVStack (alignment: .leading) {
                        ForEach(filteredRecipes) { r in
                            
                            NavigationLink(
                                destination: RecipeDetailView(recipe: r),
                                label: {
                                    
                                    // MARK: Row item
                                    HStack(spacing: 10.0) {
                                        
                                        NavigationLink(
                                            destination: ShowBigImageView(image: r.image)
                                        )
                                        {
                                            let image = UIImage(data: r.image) ?? UIImage()
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 50, height: 50, alignment: .center)
                                                .clipped()
                                                .cornerRadius(5)
                                        }
                                        
                                        VStack (alignment: .leading) {
                                            Text(r.name)
                                                .font(Font.custom("Avenir Heavy", size: 16))
                                                .multilineTextAlignment(.leading)
                                            
                                            RecipeTags(tags: r.tags)
                                                .font(Font.custom("Avenir", size: 12))
                                                .multilineTextAlignment(.leading)
                                        }
                                        .frame(width: 190, alignment: .leading)
                                        
                                        VStack {
                                            NavigationLink(
                                                destination: EditRecipeView(recipeId: r.objectID)
                                            )
                                            {
                                                Image(systemName: "pencil.circle")
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 25, height: 25, alignment: .trailing)
                                                    .clipped()
                                            }

                                            NavigationLink(
                                                destination: ShoppingCartSelectFormView(recipe: r)
                                            )
                                            {
                                                Image(systemName: "list.bullet.rectangle")
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 35, height: 25, alignment: .trailing)
                                                    .clipped()
                                            }
                                            .padding(.top)
                                        }
                                    }
                                })
                        }
                        .onDelete { indexSet in
                            withAnimation {
                                //
                            }
                        }
                    }
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .navigationBarHidden(true)
            .padding(.leading)
            .onTapGesture {
                // Resign first responder
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
     }
}
