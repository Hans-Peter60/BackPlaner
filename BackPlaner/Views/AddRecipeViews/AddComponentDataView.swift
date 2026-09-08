//
//  AddComponentDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 07.11.21.
//

import SwiftUI

struct AddComponentDataView: View {
    
    @Binding var components: [ComponentFB]
    
    @State private var componentName   = ""
    @State private var componentNumber = 1
    
    var gridItemLayout = [GridItem(.fixed(46), alignment: .leading), GridItem(.flexible(minimum: 120), alignment: .leading), GridItem(.fixed(60), alignment: .trailing)]
    
    var body: some View {

        // Note: intentionally no ScrollView here. This view is embedded in the
        // Form of AddRecipeView, which already scrolls. Nesting ScrollViews
        // inside a Form makes the screen jump up while editing a TextField,
        // because keyboard avoidance scrolls every scroll ancestor at once.
        VStack (alignment: .leading) {

            Text("Komponenten:")
                .font(Theme.brandFont(16))
                .foregroundColor(Theme.title)

            Group {

                LazyVGrid(columns: gridItemLayout, spacing: 6) {

                    TextField("", value: $componentNumber, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    TextField("Sauerteig", text: $componentName)
                        .textFieldStyle(.roundedBorder)

                    IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Komponente hinzufügen", controlSize: .regular) {
                        // Make sure that the fields are populated
                        let cleanedName = componentName.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Check that all the fields are filled in
                        if cleanedName == "" { return }

                        // Create an ComponentFB object and set its properties
                        let c      = ComponentFB()
                        c.id       = UUID().uuidString
                        c.name     = cleanedName
                        c.number   = componentNumber
                        components.append(c)

                        componentName   = ""
                        componentNumber = components.count + 1
                    }
                }

                ForEach(components.indices, id: \.self) { i in

                    LazyVGrid(columns: gridItemLayout, spacing: 6) {

                        TextField("", value: $components[i].number, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("", text: $components[i].name)
                            .textFieldStyle(.roundedBorder)
                        Text(verbatim: "")
                    }

                    AddIngredientDataView(ingredients: $components[i].ingredients)

                    Divider()
               }
            }
        }
        // Keep the wide component/ingredient grids from sitting flush against
        // the card edges in landscape, so the trailing "+"/trash buttons and the
        // leading labels aren't clipped by the section's rounded background.
        .padding(.horizontal, 6)
    }
}
