//
//  ListCoreDataRecipesView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 06.12.21.
//

import SwiftUI

struct ListCoreDataRecipesView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var model: RecipeModel
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "id", ascending: true)])
    private var recipes: FetchedResults<Recipe>


    var body: some View {
        
        Text("Liste der CoreData Rezepte")
            .bold()
        
        ScrollView {
            
            ForEach(recipes) { r in
                Text(r.name)
            }
        }
    }
}

struct ListCoreDataRecipesView_Previews: PreviewProvider {
    static var previews: some View {
        ListCoreDataRecipesView()
    }
}
