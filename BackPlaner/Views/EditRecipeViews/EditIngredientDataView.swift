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
    
    var componentId: NSManagedObjectID
    
    var ingredientsRequest: FetchRequest<Ingredient>
    var ingredients: FetchedResults<Ingredient> { ingredientsRequest.wrappedValue }
    
    init(componentId: NSManagedObjectID) {
        self.componentId = componentId
        self.ingredientsRequest = FetchRequest(entity: Ingredient.entity(), sortDescriptors: [], predicate: NSPredicate(format: "component == %@", componentId))
    }
    
    @EnvironmentObject var model:   RecipeModel
    
    @State private var showingSheet  = false
    @State private var selectedIngredientId: NSManagedObjectID?
    
    @State private var name   = ""
    @State private var number = ""
    @State private var unit   = ""
    @State private var num    = ""
    @State private var denom  = ""
    @State private var weight = ""
    
    var body: some View {
            
        // MARK: Ingredients
        Section {
            
            LazyVGrid(columns: GlobalVariables.gridItemLayoutIngredients, spacing: 6)  {
                
                ForEach(ingredients.sorted(by: { $0.number < $1.number }), id: \.self) { ingredient in

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
    
    var calcWeight:CalcIngredientWeight = CalcIngredientWeight()
    
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
            .frame(height: 120)
            .navigationBarTitle(Text("Zutat ändern"), displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                self.presentationMode.wrappedValue.dismiss()
            }, trailing: Button("Done") {
                self.presentationMode.wrappedValue.dismiss()
                
                self.ingredient.name       = self.name
                self.ingredient.weight     = self.weight
                self.ingredient.unit       = self.unit
                self.ingredient.number     = self.number
                self.ingredient.num        = self.num
                self.ingredient.denom      = self.denom
                self.ingredient.normWeight = calcWeight.calcIngredientWeight(weight: self.weight, unit: self.unit, name: self.name, num: self.num, denom: self.denom)

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
            
        Group {
            
            Text(String(ingredient.number))
            if ingredient.weight > 0 { Text(String(ingredient.weight)) } else { Text("") }
            Text(ingredient.unit ?? "")
            Text(ingredient.name)
            
            if ingredient.num == ingredient.denom {
            
                Text("")
                Text("")
                Text("")
            }
            else {
                Text(String(ingredient.num))
                Text("")
                Text(String(ingredient.denom))
            }
        }
        .font(Font.custom("Avenir", size: 15))
    }
}
