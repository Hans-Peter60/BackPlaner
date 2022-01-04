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
    var componentsCount: Int
    
    @State private var component = ""
    @State private var name      = ""
    @State private var number    = ""
    @State private var unit      = ""
    @State private var num       = ""
    @State private var denom     = ""
    @State private var weight    = ""
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading),  GridItem(.fixed(120), alignment: .trailing),
                          GridItem(.fixed(120), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading),
                          GridItem(.fixed(40), alignment: .leading),  GridItem(.fixed(10), alignment: .trailing),
                          GridItem(.fixed(40), alignment: .leading),  GridItem(.fixed(80), alignment: .trailing)]
    
    var body: some View {
        
        ScrollView {
            
            VStack (alignment: .leading) {
            
//                Text("Zutaten:")
//                    .bold()
//
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
                        
                        Text("")
//                        TextField("1", text: $component)
//                            .keyboardType(.numberPad)
//                            .textFieldStyle(.roundedBorder)
//                            .onReceive(Just(component)) { newValue in
//                                let filtered = newValue.filter { "0123456789".contains($0) }
//                                if filtered != newValue {
//                                    self.component = filtered
//                                }
//                            }
                        
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
                        
                        Button("Add") {
                            
                            // Make sure that the fields are populated
                            let cleanedName      = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedNum       = num.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedDenom     = denom.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedWeight    = Double(weight.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
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
                            i.componentNr = Int(cleanedComponent) ?? 0
                            i.number      = ingredients.count
                            i.num         = Int(cleanedNum)
                            i.denom       = Int(cleanedDenom)
                            i.weight      = cleanedWeight
                            i.unit        = cleanedUnit
                            
                            // Add this ingredient to the list
                            ingredients.append(i)
                            
                            // Clear text fields
                            number    = ""
                            component = ""
                            name      = ""
                            num       = ""
                            denom     = ""
                            unit      = ""
                            weight    = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        ForEach(ingredients.indices, id: \.self) { i in
                            
//                            TextField("", value: $ingredients[i].componentNr, formatter: GlobalVariables.formatter)
//                                .keyboardType(.decimalPad)
//                                .textFieldStyle(.roundedBorder)
                            Text("")
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

