//
//  AddComponentData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 07.11.21.
//

import SwiftUI

struct AddComponentData: View {
    
    @Binding var components: [ComponentFB]
    
    @State private var componentName = ""
    @State private var componentNumber = "1"
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 150), alignment: .leading), GridItem(.fixed(80), alignment: .trailing)]
    
    var body: some View {
        
        ScrollView {
            VStack (alignment: .leading) {
                
                Text("Komponenten:")
                    .bold()
                
                Group {
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        Text(componentNumber)
                        
                        TextField("Sauerteig", text: $componentName)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Add") {
                            
                            // Make sure that the fields are populated
                            let cleanedName = componentName.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Check that all the fields are filled in
                            if cleanedName == "" { return }
                            
                            // Create an ComponentFB object and set its properties
                            let c      = ComponentFB()
                            c.id       = UUID().uuidString
                            c.number   = Int(componentNumber) ?? 0
                            c.name     = cleanedName
                            components.append(c)
                            
                            componentNumber = String(components.count + 1)
                            componentName = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    ForEach(components.indices, id: \.self) { i in

                        LazyVGrid(columns: gridItemLayout, spacing: 6) {
                            
                            TextField("", value: $components[i].number, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("", text: $components[i].name)
                                .textFieldStyle(.roundedBorder)
                            Text(" ")
                        }
                        
                        Divider()
                        
                        AddIngredientData(ingredients: $components[i].ingredients, componentsCount: components.count)
                    }
                }
            }
        }
    }
}

