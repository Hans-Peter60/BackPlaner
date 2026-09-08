//
//  EditIngredientDataView.swift
//  PetersBackPlaner
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
    
    @State private var selectedIngredient: Ingredient?
    
    @State private var name   = ""
    @State private var number = ""
    @State private var unit   = ""
    @State private var num    = ""
    @State private var denom  = ""
    @State private var weight = ""

    private let ingredientGridLayout = [
        GridItem(.fixed(30), alignment: .leading),
        GridItem(.fixed(50), alignment: .trailing),
        GridItem(.fixed(44), alignment: .leading),
        GridItem(.flexible(minimum: 56), alignment: .leading),
        GridItem(.fixed(26), alignment: .leading),
        GridItem(.fixed(8), alignment: .center),
        GridItem(.fixed(26), alignment: .leading),
        GridItem(.fixed(40), alignment: .trailing)
    ]
    
    var body: some View {
            
        // MARK: Ingredients
        Section {
            
            LazyVGrid(columns: ingredientGridLayout, spacing: 6)  {
                
                ForEach(ingredients.sorted(by: { $0.number < $1.number }), id: \.self) { ingredient in

                    IngredientRowView(ingredient: ingredient)
                        .onTapGesture {
                            selectedIngredient = ingredient
                        }
                    
                    IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Zutat löschen", controlSize: .regular) {
                        let recipe = ingredient.component?.recipe
                        viewContext.delete(ingredient)
                        recipe?.recalculateTotalWeight()
                        do {
                            try viewContext.save()
                        } catch {
                            // handle the Core Data error
                        }
                    }
                }
            }
            .sheet(item: $selectedIngredient) { ingredient in
                EditIngredientView(ingredient: ingredient)
                    .environment(\.managedObjectContext, self.viewContext)
            }
        }
    }
}

struct EditIngredientView: View {
    
    @ObservedObject var ingredient: Ingredient
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    
    @State private var name: String
    @State private var number: Int
    @State private var unit: String
    @State private var num: Int
    @State private var denom: Int
    @State private var weight: Double
    
    var calcWeight:CalcIngredientWeight = CalcIngredientWeight()

    // 7-column layout sized for iPhone portrait so the edit fields aren't clipped left/right.
    private let ingredientGridLayout = [
        GridItem(.fixed(30), alignment: .leading),
        GridItem(.fixed(50), alignment: .trailing),
        GridItem(.fixed(44), alignment: .leading),
        GridItem(.flexible(minimum: 56), alignment: .leading),
        GridItem(.fixed(26), alignment: .leading),
        GridItem(.fixed(8), alignment: .center),
        GridItem(.fixed(26), alignment: .leading)
    ]

    init(ingredient: Ingredient) {
        self.ingredient = ingredient
        _name = State(initialValue: ingredient.name)
        _number = State(initialValue: ingredient.number)
        _unit = State(initialValue: ingredient.unit ?? "")
        _num = State(initialValue: ingredient.num)
        _denom = State(initialValue: ingredient.denom)
        _weight = State(initialValue: ingredient.weight)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: ingredientGridLayout, spacing: 6) {
                        
                        TextField("", value: $number, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $weight, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        UnitSelectionView(unit: $unit)
                        TextField("", text:  $name)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $num, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text(verbatim: "/")
                        TextField("", value: $denom, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .navigationTitle(Text("Zutat ändern"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        self.presentationMode.wrappedValue.dismiss()

                        self.ingredient.name       = self.name
                        self.ingredient.weight     = self.weight
                        self.ingredient.unit       = self.unit
                        self.ingredient.number     = self.number
                        self.ingredient.num        = self.num
                        self.ingredient.denom      = self.denom
                        self.ingredient.normWeight = calcWeight.calcIngredientWeight(weight: self.weight, unit: self.unit, name: self.name, num: self.num, denom: self.denom)
                        self.ingredient.component?.recipe?.recalculateTotalWeight()

                        try? self.viewContext.save()
                    }
                }
            }
        }
    }
}

struct IngredientRowView: View {
    @ObservedObject var ingredient: Ingredient
    
    var body: some View {
            
        Group {
            
            Text(String(ingredient.number))
            if ingredient.weight > 0 { Text(String(ingredient.weight)) } else { Text(verbatim: "") }
            Text(ingredient.unit ?? "")
            Text(ingredient.name)
            
            if ingredient.num == ingredient.denom {
            
                Text(verbatim: "")
                Text(verbatim: "")
                Text(verbatim: "")
            }
            else {
                Text(String(ingredient.num))
                Text(verbatim: "")
                Text(String(ingredient.denom))
            }
        }
        .font(Theme.bodyFont(15))
    }
}

