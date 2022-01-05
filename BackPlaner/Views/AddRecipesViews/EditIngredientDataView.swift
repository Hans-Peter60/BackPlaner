//
//  EditIngredientDataView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 04.01.22.
//

import SwiftUI
import CoreData
import Combine

struct EditIngredientDataView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    var componentId: NSManagedObjectID?
    
    @EnvironmentObject var model:   RecipeModel
    
    @State private var showingSheet  = false
    @State private var selectedIngredientId: NSManagedObjectID?
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "component", ascending: true)])
    private var ingredients: FetchedResults<Ingredient>
    
    private var filteredIngredients: [Ingredient] {
        
        if componentId != nil {
            // return all ingredients for selected component
            return ingredients.filter { i in
                return i.component!.objectID == componentId
            }
        }
        else {
            return [Ingredient]()
        }
    }
    
    @State private var name   = ""
    @State private var number = ""
    @State private var unit   = ""
    @State private var num    = ""
    @State private var denom  = ""
    @State private var weight = ""
    
    var body: some View {
        
        ScrollView {
            
            // MARK: Ingredients
            VStack(alignment: .leading) {
            
                Text("Anzahl Zutaten: " + String(filteredIngredients.count))
                
                LazyVGrid(columns: GlobalVariables.gridItemLayoutIngredients, spacing: 6) {
                    
                    ForEach(filteredIngredients.sorted(by: { $0.number < $1.number }), id: \.self) { ingredient in
                        
                        Section {
                            
                            HStack {
                                IngredientRowView(ingredient: ingredient)
                                    .onTapGesture {
                                        self.selectedIngredientId = ingredient.objectID
                                        self.showingSheet         = true
                                    }
                                
                                Button("Del") {
                                    viewContext.delete(ingredient)
                                    
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
                }
            }
            .sheet(isPresented: $showingSheet ) {
                if selectedIngredientId != nil {
                    EditIngredientView(ingredientId: self.selectedIngredientId!)
                        .environment(\.managedObjectContext, self.viewContext)
                }
            }
        }
    }
}

struct EditIngredientView: View {
    
    var ingredientId: NSManagedObjectID
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    
    @State private var name   = ""
    @State private var number = 0
    @State private var unit   = ""
    @State private var num    = 0
    @State private var denom  = 0
    @State private var weight = 0.0
    
    var ingredient: Ingredient {
        viewContext.object(with: ingredientId) as! Ingredient
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    LazyVGrid(columns: GlobalVariables.gridItemLayoutIngredients, spacing: 6) {
                        
                        TextField("", value: $number, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $weight, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("", text:  $unit)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                        TextField("", text:  $name)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $num, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("/")
                        TextField("", value: $denom, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .navigationBarTitle(Text("Zutat ändern"), displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                self.presentationMode.wrappedValue.dismiss()
            }, trailing: Button("Done") {
                self.presentationMode.wrappedValue.dismiss()
                
                self.ingredient.name   = self.name
                self.ingredient.weight = self.weight
                self.ingredient.unit   = self.unit
                self.ingredient.number = self.number
                self.ingredient.num    = self.num
                self.ingredient.denom  = self.denom
                
                try? self.viewContext.save()
            }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            self.name   = self.ingredient.name
            self.weight = self.ingredient.weight
            self.unit   = self.ingredient.unit ?? ""
            self.number = self.ingredient.number
            self.num    = self.ingredient.num
            self.denom  = self.ingredient.denom
        }

    }
}

struct IngredientRowView: View {
    @ObservedObject var ingredient: Ingredient
    
    var body: some View {
        
        LazyVGrid(columns: GlobalVariables.gridItemLayoutIngredients, spacing: 6) {
            
            Text(String(ingredient.number))
            Text(String(ingredient.weight))
            Text(ingredient.unit ?? "")
            Text(ingredient.name)
            Text(String(ingredient.num))
            Text("")
        }
        .font(Font.custom("Avenir", size: 15))
    }
}

struct EditIngredientDataView_Previews: PreviewProvider {
    static var previews: some View {
        EditIngredientDataView()
    }
}
