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
    @State var selectedSelection = 1

    var recipeId: NSManagedObjectID?
    
    private var filteredFBRecipes: [RecipeFB] {
        
        var fR: [RecipeFB] = [RecipeFB]()
        
        if filterBy == "" {
            return modelFB.recipesFB
        }
        else {
            if selectedSelection == 1 {
                for i in 0..<modelFB.recipesFB.count {
                    if modelFB.recipesFB[i].name.contains(filterBy) { fR.append(modelFB.recipesFB[i]) }
                }
            }
            else {
                for i in 0..<modelFB.recipesFB.count {
                    if modelFB.recipesFB[i].tags.contains(filterBy) { fR.append(modelFB.recipesFB[i]) }
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
                
                SearchBarView(filterBy: $filterBy)
                    .padding([.trailing, .bottom])
                
                HStack {
                    Text("Selektion nach:")
                        .font(Font.custom("Avenir", size: 15))
                    Picker("", selection: $selectedSelection) {
                        Text("Name").tag(1)
                        Text("Tags").tag(2)
                    }
                    .font(Font.custom("Avenir", size: 15))
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width:160)
                }
                
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
