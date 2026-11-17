//
//  EditIngredientDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 04.01.22.
//

import BakePlannerCore
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

    // Number, amount (weight or fraction, as the amount field writes it),
    // unit, name, delete. The fraction used to take three columns of its
    // own, which left the name so little room that "Weizenmehl 550" broke
    // inside the word.
    private let ingredientGridLayout = [
        GridItem(scaledColumnSize(30), alignment: .leading),
        GridItem(scaledColumnSize(56), alignment: .trailing),
        GridItem(scaledColumnSize(44), alignment: .leading),
        GridItem(.flexible(minimum: 80), alignment: .leading),
        GridItem(scaledColumnSize(40), alignment: .trailing)
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
                        // A tap gesture alone carries no semantics: without the
                        // button trait VoiceOver announces the row as plain text
                        // and never offers to activate it.
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Zutat bearbeiten")
                    
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
            .scrollsSidewaysAtLargeText()
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
        GridItem(scaledColumnSize(30), alignment: .leading),
        GridItem(scaledColumnSize(50), alignment: .trailing),
        GridItem(scaledColumnSize(44), alignment: .leading),
        GridItem(.flexible(minimum: 56), alignment: .leading),
        GridItem(scaledColumnSize(26), alignment: .leading),
        GridItem(scaledColumnSize(8), alignment: .center),
        GridItem(scaledColumnSize(26), alignment: .leading)
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
                        
                        NumberField("", value: $number)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Nummer")
                        NumberField("", value: $weight)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Gewicht")
                        UnitSelectionView(unit: $unit)
                        TextField("", text:  $name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Zutat")
                        NumberField("", value: $num)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Zähler")
                        Text(verbatim: "/")
                            .accessibilityHidden(true)
                        NumberField("", value: $denom)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Nenner")
                    }
                    .scrollsSidewaysAtLargeText()
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

    private var amountText: String {
        if ingredient.weight > 0 {
            return IngredientAmountText.text(weight: ingredient.weight, numerator: 0, denominator: 0)
        }
        guard ingredient.num > 0, ingredient.denom > 0, ingredient.num != ingredient.denom else { return "" }
        return IngredientAmountText.text(weight: 0, numerator: ingredient.num, denominator: ingredient.denom)
    }
    
    var body: some View {
            
        Group {
            
            Text(String(ingredient.number))
            // "400", "12,5", "1 1/2" — as the amount field writes it, in the
            // app's language; String(weight) showed "400.0" with a point.
            // A fraction of one whole (1/1, the whole component) shows none,
            // as before.
            Text(verbatim: amountText)
            Text(UnitLocalizer.display(ingredient.unit ?? "",
                                       amount: ingredient.weight > 0 ? ingredient.weight
                                           : (ingredient.denom != 0 ? Double(ingredient.num) / Double(ingredient.denom) : 0)))
            WordWrappedText(ingredient.name)
                // Room before the delete button for a name that fills the column.
                .padding(.trailing, 6)
        }
        .font(Theme.bodyFont(15))
    }
}

/// A name that breaks only between words: each word is a line of its own
/// that shrinks a little rather than split. In the narrow name column a
/// Text broke "Roggenvollkornmehl" inside the word.
struct WordWrappedText: View {
    let text: String
    let words: [String]

    init(_ text: String) {
        self.text = text
        words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var body: some View {
        WordFlowLayout(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(verbatim: word)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        // Read as the one name it is, not word by word with pauses.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}

/// Lays its subviews out left to right and starts a new line when the next
/// one does not fit; a subview wider than the line on its own gets the
/// line's width.
struct WordFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +)
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                           proposal: ProposedViewSize(width: item.size.width, height: item.size.height))
                x += item.size.width + spacing
            }
            y += row.height
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

