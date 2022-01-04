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
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
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
    
    @State private var name      = ""
    @State private var number    = ""
    @State private var unit      = ""
    @State private var num       = ""
    @State private var denom     = ""
    @State private var weight    = ""
    
    var body: some View {
        
        ScrollView {
            
            // MARK: Ingredients
            VStack(alignment: .leading) {
                
                LazyVGrid(columns: GlobalVariables.gridItemLayoutIngredients, spacing: 6) {
                    Text("Nr.")
                    Text("Gewicht")
                    Text("Einheit")
                    Text("Zutat")
                    Text("Z")
                    Text("/")
                    Text("N")
                    Text("")
                }
                
                ForEach (filteredIngredients, id: \.self) { ingredient in
                    
                    Section {
                        
                        HStack {
                            IngredientRowView(ingredient: ingredient)
                                .onTapGesture {
                                    self.selectedIngredientId = ingredient.objectID
                                    self.showingSheet        = true
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
                .sheet(isPresented: $showingSheet ) {
                    if selectedIngredientId != nil {
                        EditIngredientView(ingredientId: self.selectedIngredientId!)
                            .environment(\.managedObjectContext, self.viewContext)
                    }
                }
            }
        }
    }
}

struct EditIngredientView: View {
    
    var ingredientId: NSManagedObjectID
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    
    @State private var name      = ""
    @State private var number    = ""
    @State private var unit      = ""
    @State private var num       = ""
    @State private var denom     = ""
    @State private var weight    = ""
    
    var ingredient: Ingredient {
        viewContext.object(with: ingredientId) as! Ingredient
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    LazyVGrid(columns: GlobalVariables.gridItemLayoutIngredients, spacing: 6) {
                        
                        TextField("1", text: $number)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onReceive(Just(number)) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    self.number = filtered
                                }
                            }
                        
                        TextField("Menge/Gewicht", text: $weight)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onReceive(Just(weight)) { newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue {
                                    self.weight = filtered
                                }
                            }
                        
                        TextField("g", text: $unit)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("Zucker", text: $name)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("1", text: $num)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onReceive(Just(num)) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    self.num = filtered
                                }
                            }
                        
                        Text("/")
                        
                        TextField("1", text: $denom)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .onReceive(Just(denom)) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    self.denom = filtered
                                }
                            }
                    }
                }
            }
            .navigationBarTitle(Text("Zutat ändern"), displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                self.presentationMode.wrappedValue.dismiss()
            }, trailing: Button("Done") {
                self.presentationMode.wrappedValue.dismiss()
                
                self.ingredient.name   = self.name
                self.ingredient.weight = Double(self.weight) ?? 0
                self.ingredient.unit   = self.unit
                self.ingredient.number = Int(self.number) ?? 0
                self.ingredient.num    = Int(self.num) ?? 0
                self.ingredient.denom  = Int(self.denom) ?? 0
                
                try? self.viewContext.save()
            }
            )
        }
        .onAppear {
            self.name   = self.ingredient.name
            self.weight = String(self.ingredient.weight)
            self.unit   = self.ingredient.unit ?? ""
            self.number = String(self.ingredient.number)
            self.num    = String(self.ingredient.num)
            self.denom  = String(self.ingredient.denom)
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
