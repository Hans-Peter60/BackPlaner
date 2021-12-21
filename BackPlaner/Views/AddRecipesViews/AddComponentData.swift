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
    @State private var componentNumber = ""
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 150), alignment: .leading), GridItem(.fixed(80), alignment: .trailing)]
    
    var body: some View {
        
        ScrollView {
            VStack (alignment: .leading) {
                
                Text("Komponenten:")
                    .bold()
                
                Group {
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        TextField("1", text: $componentNumber)
                        
                        TextField("Sauerteig", text: $componentName)
                        
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
                            
                            componentNumber = String((Int(componentNumber) ?? 0) + 1)
                            componentName = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        ForEach(components.sorted(by: { $0.number < $1.number })) { component in
                            Text(String(component.number))
                            Text(component.name)
                            Text(" ")
                        }
                    }
                }
            }
        }
    }
}

