//
//  RecipeFBListView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 23.11.21.
//

import SwiftUI
import CoreData

struct RecipeFBListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel

    @State private var filterBy  = ""
    @State private var nameOrTag = 1
    @State private var rating    = 0  // Ratingselektion NICHT anzeigen

    var recipeId: NSManagedObjectID?
    
    private var filteredFBRecipes: [RecipeFB] {
        
        var fR: [RecipeFB] = [RecipeFB]()
        
        if filterBy == "" && rating == 0 {
            return modelFB.recipesFB
        }
        else {
            if nameOrTag == 1 {
                for i in 0..<modelFB.recipesFB.count {
                    if modelFB.recipesFB[i].name.contains(filterBy) {
                        if modelFB.recipesFB[i].rating >= rating { fR.append(modelFB.recipesFB[i]) }
                    }
                }
            }
            else {
                for i in 0..<modelFB.recipesFB.count {
                    if modelFB.recipesFB[i].tags.contains(filterBy) {
                        if modelFB.recipesFB[i].rating >= rating { fR.append(modelFB.recipesFB[i]) }
                    }
                }
            }
        }
        return fR
    }
    
    var body: some View {
        
        NavigationView {
            
            VStack (alignment: .leading) {
                Text("Rezept-Datenbank")
                    .bold()
                    .padding(.top, 40)
                    .font(Font.custom("Avenir Heavy", size: 24))
                
                SearchBarView(filterBy: $filterBy, nameOrTag: $nameOrTag, rating: $rating, showRating: false)
                    .padding([.trailing, .bottom])
                
                ScrollView {
                    LazyVStack (alignment: .leading) {
                        ForEach (filteredFBRecipes) { r in
                            NavigationLink(
                                destination: RecipeFBDetailView(recipeFB: r),
                                label: {
                                    
                                    // MARK: Row item
                                    HStack(spacing: 20.0) {
                                        
                                        NavigationLink(
                                            destination: ShowBigImageView(image: (GlobalVariables.recipesImage[r.id ?? ""] ?? UIImage()).jpegData(compressionQuality: 1.0) ?? Data() )
                                        )
                                        {
                                            Image(uiImage: GlobalVariables.recipesImage[r.id ?? ""] ?? UIImage())
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
                                    }
                                }
                            )
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
