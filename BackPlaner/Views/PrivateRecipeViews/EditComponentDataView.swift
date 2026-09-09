//
//  EditComponentDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 03.01.22.
//

import SwiftUI
import CoreData
import Combine

struct EditComponentDataView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    var recipeId: NSManagedObjectID
    
    var componentsRequest: FetchRequest<Component>
    var components:        FetchedResults<Component> { componentsRequest.wrappedValue }
    
    @State private var selectedComponent: Component? = nil
    
    init(recipeId: NSManagedObjectID) {
        self.recipeId = recipeId
        self.componentsRequest = FetchRequest(entity: Component.entity(), sortDescriptors: [], predicate: NSPredicate(format: "recipe == %@", recipeId))
    }

    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    
    @State private var componentName = ""

    private let componentGridLayout = [
        GridItem(.flexible(minimum: 80), alignment: .leading),
        GridItem(scaledColumnSize(44), alignment: .trailing)
    ]

    
    var body: some View {
        
        ScrollView {
            
            // MARK: Components
            VStack(alignment: .leading) {
                
                ForEach (components.sorted(by: { $0.number < $1.number }), id: \.self) { component in
                    
                    Section {
                        
                        LazyVGrid(columns: componentGridLayout, spacing: 6) {
                            ComponentRowView(component: component)
                                .onTapGesture {
                                    self.selectedComponent = component
                                }
                                // A tap gesture alone carries no semantics: without
                                // the button trait VoiceOver announces the row as
                                // plain text and never offers to activate it.
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Komponente bearbeiten")

                            IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Komponente löschen", controlSize: .regular) {
                                let recipe = component.recipe
                                viewContext.delete(component)
                                recipe?.recalculateTotalWeight()
                                do {
                                    try viewContext.save()
                                } catch {
                                    // handle the Core Data error
                                }
                            }
                        }
                        .scrollsSidewaysAtLargeText()
                    }
                }
            }
        }
        .sheet(item: $selectedComponent) { component in
            EditComponentView(componentId: component.objectID)
                .environment(\.managedObjectContext, self.viewContext)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct EditComponentView: View {
    
    var componentId: NSManagedObjectID
    
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var component: Component
    
    @EnvironmentObject var model:   RecipeModel
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var componentName: String = ""
    @State private var componentNumber: Int = 0
    
    @State private var name   = ""
    @State private var number = 0
    @State private var unit   = ""
    @State private var num    = 0
    @State private var denom  = 0
    @State private var weight = 0.0

    private let calcWeight = CalcIngredientWeight()

    /// A purely visual placeholder. Passing a `String` instead of a
    /// `LocalizedStringKey` keeps it out of the String Catalog.
    private let namePlaceholder = "..."

    private let ingredientGridLayout = [
        GridItem(scaledColumnSize(30), spacing: 4, alignment: .leading),
        GridItem(scaledColumnSize(64), spacing: 4, alignment: .trailing),
        GridItem(scaledColumnSize(54), spacing: 4, alignment: .leading),
        GridItem(.flexible(minimum: 50), spacing: 4, alignment: .leading),
        GridItem(scaledColumnSize(26), spacing: 4, alignment: .leading),
        GridItem(scaledColumnSize(8), spacing: 4, alignment: .center),
        GridItem(scaledColumnSize(26), spacing: 4, alignment: .leading),
        GridItem(scaledColumnSize(40), spacing: 0, alignment: .trailing)
    ]
    
    init(componentId: NSManagedObjectID) {
        self.componentId = componentId
        let context = PersistenceController.shared.container.viewContext
        if let comp = try? context.existingObject(with: componentId) as? Component {
            _component = ObservedObject(wrappedValue: comp)
            _componentName = State(initialValue: comp.name)
            _componentNumber = State(initialValue: comp.number)
        } else {
            fatalError("Component not found")
        }
    }
    
    var body: some View {
        
        NavigationStack {
        
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Nr.")
                                .frame(width: 40, alignment: .leading)
                            Text("Komponente")
                        }
                        HStack {
                            TextField("Nr.", value: $componentNumber, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 40)
                                .accessibilityLabel("Nummer")
                            TextField(namePlaceholder, text: $componentName)
                                .textFieldStyle(.roundedBorder)
                                // The placeholder is an example name, not the
                                // field's own name.
                                .accessibilityLabel("Komponente")
                        }
                    }
                }
                
                Section {
          
                    Text("Zutaten")
                        .font(Theme.brandFont(16))
                        .padding([.bottom, .top], 5)
                    
                    LazyVGrid(columns: ingredientGridLayout, spacing: 6) {
                        
                        Group {
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
                        
                        // MARK: Add Button
                        IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Zutat hinzufügen", controlSize: .regular) {
                            // Check that all relevant fields are filled in
                            if name == "" {
                                return
                            }

                            let componentCD = component

                            let i    = Ingredient(context: viewContext)
                            i.id     = UUID()
                            i.name       = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            i.number     = number
                            i.num        = num
                            i.denom      = denom
                            i.weight     = weight
                            i.unit       = unit.trimmingCharacters(in: .whitespacesAndNewlines)
                            i.normWeight = calcWeight.calcIngredientWeight(weight: i.weight, unit: i.unit ?? "", name: i.name, num: i.num, denom: i.denom)

                            componentCD.addToIngredients(i)
                            componentCD.recipe?.recalculateTotalWeight()
                            try? viewContext.save()

                            number = componentCD.ingredientsArray.count + 1
                            name   = ""
                            num    = 0
                            denom  = 0
                            unit   = ""
                            weight = 0.0
                        }
                    }
                    .scrollsSidewaysAtLargeText()
                    
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                EditIngredientDataView(componentId: component.objectID)
            }
            .navigationTitle(Text("Komponente ändern"))
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
                        self.component.name   = self.componentName
                        self.component.number = self.componentNumber

                        try? self.viewContext.save()
                    }
                }
            }
        }
    }
}
    
struct ComponentRowView: View {
    @ObservedObject var component: Component
    
    var body: some View {
        HStack {
            Text(String(component.number))
            Text(component.name)
        }
    }
}
