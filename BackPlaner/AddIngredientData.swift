//
//  AddIngredientData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import SwiftUI

struct AddIngredientData: View {
    
    @Binding var ingredients: [IngredientFB]
    
    @State private var component = ""
    @State private var name = ""
    @State private var unit = ""
    @State private var num = ""
    @State private var denom = ""
    @State private var weight = ""
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading),
                          GridItem(.fixed(120), alignment: .leading), GridItem(.fixed(120), alignment: .leading),
                          GridItem(.fixed(40), alignment: .leading), GridItem(.fixed(10), alignment: .leading),
                          GridItem(.fixed(40), alignment: .leading), GridItem(.fixed(80), alignment: .trailing)]
    
    var body: some View {
        
        VStack (alignment: .leading) {
            
            ScrollView {
                
                Text("Zutaten:")
                    .bold()
//                    .padding(.leading, 5)
                
                LazyVGrid(columns: gridItemLayout, spacing: 6) {
                    Text("Komp.")
                    Text("Zutat")
                    Text("Gewicht")
                    Text("Einheit")
                    Text("Z")
                    Text("/")
                    Text("N")
                    Text("")
                }
                
                Group {
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        TextField("1", text: $component)
                        
                        TextField("Zucker", text: $name)
                        
                        TextField("Menge/Gewicht", text: $weight)
                        
                        TextField("Gramm", text: $unit)
                        
                        TextField("1", text: $num)
                        Text("/")
                        TextField("1", text: $denom)
                        
                        Button("Add") {
                            
                            // Make sure that the fields are populated
                            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedNum = num.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedDenom = denom.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanedWeight:Double = Double(weight.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                            let cleanedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Check that all the fields are filled in
                            if cleanedName == "" {
                                return
                            }
                            
                            // Set the IngredientFB instance properties
                            let i = IngredientFB()
                            i.id = UUID().uuidString
                            i.name = cleanedName
                            i.component = cleanedComponent
                            i.num = Int(cleanedNum)
                            i.denom = Int(cleanedDenom)
                            i.weight = cleanedWeight
                            i.unit = cleanedUnit
                            
                            // Add this ingredient to the list
                            ingredients.append(i)
                            
                            // Clear text fields
                            component = ""
                            name = ""
                            num = ""
                            denom = ""
                            unit = ""
                            weight = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        ForEach(ingredients) { ingredient in
                            if ingredient.component != nil { Text(String(ingredient.component!)) } else { Text(" ") }
                            Text(ingredient.name)

                            if ingredient.weight != nil { Text(Rational.decimalPlace(ingredient.weight!, 1000)) } else { Text(" ") }
                            if ingredient.unit != nil { Text(String(ingredient.unit!)) } else { Text(" ") }
                            if ingredient.num != nil { Text(String(ingredient.num!)) } else { Text(" ") }
                            Text("/")
                            if ingredient.denom != nil { Text(String(ingredient.denom!)) } else { Text(" ") }
                            Text("")
                        }
                    }
                }
            }
        }
    }
}

