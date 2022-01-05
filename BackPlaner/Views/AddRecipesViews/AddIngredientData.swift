//
//  AddIngredientData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import SwiftUI
import Combine

struct AddIngredientData: View {
    
    @Binding var ingredients: [IngredientFB]
    
    @State private var name      = ""
    @State private var number    = 1
    @State private var unit      = ""
    @State private var num       = 0
    @State private var denom     = 0
    @State private var weight    = 0.0
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading),  GridItem(.fixed(120), alignment: .trailing),
                          GridItem(.fixed(120), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading),
                          GridItem(.fixed(40), alignment: .leading),  GridItem(.fixed(10), alignment: .trailing),
                          GridItem(.fixed(40), alignment: .leading),  GridItem(.fixed(80), alignment: .trailing)]
    
    var body: some View {
        
        ScrollView {
            
            VStack (alignment: .leading) {
            
                LazyVGrid(columns: gridItemLayout, spacing: 6) {
                    Text("")
                    Text("Gewicht")
                    Text("Einheit")
                    Text("Zutat")
                    Text("Z")
                    Text("/")
                    Text("N")
                    Text("")
                }
                
                Group {
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
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
                        
                        Button("Add") {
                            
                            // Make sure that the fields are populated
                            let cleanedName      = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedUnit      = unit.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Check that all the fields are filled in
//                            if cleanedName == "" || Int(cleanedComponent) ?? 0 < 1 || Int(cleanedComponent) ?? 0 > componentsCount {
                            if cleanedName == "" {
                                return
                            }
                            
                            // Set the IngredientFB instance properties
                            let i         = IngredientFB()
                            i.id          = UUID().uuidString
                            i.name        = cleanedName
                            i.number      = ingredients.count
                            i.num         = num
                            i.denom       = denom
                            i.weight      = weight
                            i.unit        = cleanedUnit
                            
                            // Add this ingredient to the list
                            ingredients.append(i)
                            
                            // Clear text fields
                            number    = ingredients.count + 1
                            name      = ""
                            num       = 0
                            denom     = 0
                            unit      = ""
                            weight    = 0
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        ForEach(ingredients.indices, id: \.self) { i in
                            
                            TextField("", value: $ingredients[i].number, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("", value: $ingredients[i].weight, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("", text:  $ingredients[i].unit)
                                .autocapitalization(.none)
                                .textFieldStyle(.roundedBorder)
                            TextField("", text:  $ingredients[i].name)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("", value: $ingredients[i].num, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("/")
                            
                            TextField("", value: $ingredients[i].denom, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            
                            Button("Del") {
                                ingredients.remove(at: i)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

