//
//  RecipeFBListView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 23.11.21.
//

import SwiftUI

struct RecipeFBListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel

    @State private var filterBy = ""
    
    private var filteredFBRecipes: [RecipeFB] {
        
        var fR: [RecipeFB] = [RecipeFB]()
        if filterBy == "" {
            return modelFB.recipesFB
        }
        else {
            for i in 0..<modelFB.recipesFB.count {
                if modelFB.recipesFB[i].name.contains(filterBy) { fR.append(modelFB.recipesFB[i]) }
            }
        }
        return fR
    }
    
    var body: some View {
        
        NavigationView {
            
            VStack (alignment: .leading) {
                Text("Alle Rezepte")
                    .bold()
                    .padding(.top, 40)
                    .font(Font.custom("Avenir Heavy", size: 24))
                
                SearchBarView(filterBy: $filterBy)
                    .padding([.trailing, .bottom])
                
                ScrollView {
                    LazyVStack (alignment: .leading) {
                        ForEach (filteredFBRecipes) { r in
                            NavigationLink(
                                destination: RecipeFBDetailView(recipeFB:r),
                                label: {
                                    
                                    // MARK: Row item
                                    HStack(spacing: 20.0) {
                                        
                                        Image(uiImage: modelFB.recipesImage[r.id ?? ""] ?? UIImage())
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50, alignment: .center)
                                            .clipped()
                                            .cornerRadius(5)
                                        
                                        VStack (alignment: .leading) {
                                            Text(r.name)
                                                .font(Font.custom("Avenir Heavy", size: 16))
                                            
                                            RecipeTags(tags: r.tags)
                                                .font(Font.custom("Avenir", size: 12))
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

//struct RecipeFBListView_Previews: PreviewProvider {
//    static var previews: some View {
//        RecipeFBListView()
//            .environmentObject(RecipeFBModel())
//    }
//}
