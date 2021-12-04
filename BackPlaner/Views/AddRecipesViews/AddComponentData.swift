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
    @State private var componentId = ""
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 150), alignment: .leading), GridItem(.fixed(80), alignment: .trailing)]
    
    var body: some View {
        
        ScrollView {
            VStack (alignment: .leading) {
                
                Text("Komponenten:")
                    .bold()
                
                Group {
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        TextField("1", text: $componentId)
                        
                        TextField("Sauerteigkomponente", text: $componentName)
                        
                        Button("Add") {
                            
                            // Make sure that the fields are populated
                            let cleanedName = componentName.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Check that all the fields are filled in
                            if cleanedName == "" { return }
                            
                            // Create an ComponentFB object and set its properties
                            let c = ComponentFB()
                            c.id = componentId
                            c.name = cleanedName
                            components.append(c)
                            
                            componentId = String((Int(componentId) ?? 0) + 1)
                            componentName = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    LazyVGrid(columns: gridItemLayout, spacing: 6) {
                        
                        ForEach(components.sorted(by: { $0.id < $1.id })) { component in
                            Text(component.id ?? "")
                            Text(component.name)
                            Text("")
                        }
                    }
                }
            }
        }
    }
}

