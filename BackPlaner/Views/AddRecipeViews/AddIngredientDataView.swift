//
//  AddIngredientDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import SwiftUI

struct AddIngredientDataView: View {
    
    @Binding var ingredients: [IngredientFB]
    
    @State private var name       = ""
    @State private var number     = 1
    @State private var unit       = ""
    @State private var num        = 0
    @State private var denom      = 0
    @State private var weight     = 0.0
    @State private var normWeight = 0.0

    var calcWeight:CalcIngredientWeight = CalcIngredientWeight()

    
    // Column widths are kept compact so the grid's minimum width fits inside the
    // recipe card in landscape. If the fixed columns are too wide, the flexible
    // "Zutat" column can't shrink past its minimum and the whole row overflows the
    // card, pushing the trailing +/trash buttons off the right edge.
    var gridItemLayout = [GridItem(scaledColumnSize(30), spacing: 4, alignment: .leading), GridItem(scaledColumnSize(64), spacing: 4, alignment: .trailing),
                          GridItem(scaledColumnSize(54), spacing: 4, alignment: .leading), GridItem(.flexible(minimum: 50), spacing: 4, alignment: .leading),
                          GridItem(scaledColumnSize(26), spacing: 4, alignment: .leading), GridItem(scaledColumnSize(8), spacing: 4, alignment: .center),
                          GridItem(scaledColumnSize(26), spacing: 4, alignment: .leading), GridItem(scaledColumnSize(40), spacing: 0, alignment: .trailing)]
    
    var body: some View {

        // Note: intentionally no ScrollView here. This view is embedded in the
        // Form of AddRecipeView (via AddComponentDataView), which already
        // scrolls. Nesting ScrollViews inside a Form makes the screen jump up
        // when a TextField such as weight or unit is edited, because keyboard
        // avoidance scrolls every scroll ancestor at once.
        VStack (alignment: .leading) {

            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                Text("Nr.")
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Menge /")
                    Text("Gewicht")
                }
                .fixedSize(horizontal: true, vertical: false)
                Text("Einheit")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("Zutat")
                Text("Z")
                Text(verbatim: "/")
                Text("N")
                Text(verbatim: "")
            }
            .scrollsSidewaysAtLargeText()

            Group {
                LazyVGrid(columns: gridItemLayout, spacing: 6) {

                    // The grid header above names each column visually, but a
                    // header cell is not a label — every field needs its own.
                    TextField("", value: $number, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Nummer")
                    TextField("", value: $weight, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Gewicht")
                    UnitSelectionView(unit: $unit)
                    TextField("", text:  $name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Zutat")
                    TextField("", value: $num, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Zähler")
                    Text(verbatim: "/")
                        .accessibilityHidden(true)
                    TextField("", value: $denom, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Nenner")

                    IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Zutat hinzufügen", controlSize: .regular) {
                        // Make sure that the fields are populated
                        let cleanedName      = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedUnit      = unit.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Check that all the fields are filled in
                        if cleanedName == "" {
                            return
                        }

                        // Set the IngredientFB instance properties
                        let i        = IngredientFB()
                        i.id         = UUID().uuidString
                        i.name       = cleanedName
                        i.number     = number
                        i.num        = num
                        i.denom      = denom
                        i.weight     = weight
                        i.unit       = cleanedUnit
                        i.normWeight = calcWeight.calcIngredientWeight(weight: i.weight, unit: i.unit, name: i.name, num: i.num, denom: i.denom)

                        // Add this ingredient to the list
                        ingredients.append(i)

                        // Clear text fields
                        number     = ingredients.count + 1
                        name       = ""
                        num        = 0
                        denom      = 0
                        unit       = ""
                        weight     = 0
                        normWeight = 0
                    }
                }
                .scrollsSidewaysAtLargeText()

                LazyVGrid(columns: gridItemLayout, spacing: 6) {

                    ForEach(ingredients.indices, id: \.self) { i in

                        TextField("", value: $ingredients[i].number, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Nummer")
                        TextField("", value: $ingredients[i].weight, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Gewicht")
                        UnitSelectionView(unit: $ingredients[i].unit)
                        TextField("", text:  $ingredients[i].name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Zutat")

                        TextField("", value: $ingredients[i].num, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Zähler")

                        Text(verbatim: "/")
                            .accessibilityHidden(true)

                        TextField("", value: $ingredients[i].denom, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Nenner")

                        IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Zutat löschen", controlSize: .regular) {
                            ingredients.remove(at: i)
                        }
                    }
                }
                .scrollsSidewaysAtLargeText()
            }
        }
    }
}
