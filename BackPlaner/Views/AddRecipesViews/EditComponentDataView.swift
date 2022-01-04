//
//  EditComponentDataView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 03.01.22.
//

import SwiftUI
import CoreData

struct EditComponentDataView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    var recipeId: NSManagedObjectID?
    
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    
    @State private var componentName = ""
    @State private var showingSheet  = false
    @State private var selectedComponentId: NSManagedObjectID?
    
    @State private var name      = ""
    @State private var number    = ""
    @State private var unit      = ""
    @State private var num       = ""
    @State private var denom     = ""
    @State private var weight    = ""
    
    var gridItemLayout = [GridItem(.fixed(60),  alignment: .leading),  GridItem(.fixed(120),             alignment: .trailing),
                          GridItem(.fixed(120), alignment: .leading),  GridItem(.flexible(minimum: 200), alignment: .leading),
                          GridItem(.fixed(40),  alignment: .leading),  GridItem(.fixed(10),              alignment: .trailing),
                          GridItem(.fixed(40),  alignment: .leading),  GridItem(.fixed(80),              alignment: .trailing)]
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "number", ascending: true)])
    private var components: FetchedResults<Component>
    
    private var filteredComponents: [Component] {
        
        if recipeId != nil {
            // No filter text, so return all recipes
            return components.filter { c in
                return c.recipe!.objectID == recipeId
            }
        }
        else {
            return [Component]()
        }
    }
    
    var body: some View {
        
        ScrollView {
            
            // MARK: Components
            VStack(alignment: .leading) {
                
                ForEach (filteredComponents, id: \.self) { component in
                    
                    Section {
                        
                        HStack {
                            ComponentRowView(component: component)
                                .onTapGesture {
                                    self.selectedComponentId = component.objectID
                                    self.showingSheet        = true
                                }
                            
                            Spacer()
                            
                            Button("Del") {
                                viewContext.delete(component)
                                
                                do {
                                    try viewContext.save()
                                } catch {
                                    // handle the Core Data error
                                }
                            }
                            .font(Font.custom("Avenir", size: 15))
                            .padding()
                            .foregroundColor(.gray)
                            .buttonStyle(.bordered)
                        }
                            
                        // MARK: Ingredients
                        VStack(alignment: .leading) {
                            
                            Text("Zutaten")
                                .font(Font.custom("Avenir Heavy", size: 16))
                                .padding([.bottom, .top], 5)
                            
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
                                
                                // MARK: Add Button
                                Button("Add") {
                                    
                                    // Make sure that the fields are populated
                                    let cleanedName      = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let cleanedNumber    = number.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let cleanedNum       = num.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let cleanedDenom     = denom.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let cleanedWeight    = Double(weight.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                                    let cleanedUnit      = unit.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    // Check that all relevant fields are filled in
                                    if cleanedName == "" {
                                        return
                                    }
                                    
                                    let componentCD: Component
                                    if let objectId = selectedComponentId,
                                       let fetchedComponent = model.fetchComponent(for: objectId, context: viewContext) {
                                        componentCD = fetchedComponent
                                    } else {
                                        componentCD = Component(context: viewContext)
                                        return
                                    }
                                    
                                    let i         = Ingredient(context: viewContext)
                                    i.id          = UUID()
                                    i.name        = cleanedName
                                    i.number      = Int(cleanedNumber) ?? 0
                                    i.num         = Int(cleanedNum) ?? 0
                                    i.denom       = Int(cleanedDenom) ?? 0
                                    i.weight      = cleanedWeight
                                    i.unit        = cleanedUnit
                                    
                                    componentCD.addToIngredients(i)
                                    
                                    componentName = ""
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            // MARK: Ingredients
                            EditIngredientDataView(componentId: selectedComponentId)
                            
                        }
                    }
                }
                .sheet(isPresented: $showingSheet ) {
                    if selectedComponentId != nil {
                        EditComponentView(componentId: self.selectedComponentId!)
                            .environment(\.managedObjectContext, self.viewContext)
                    }
                }
            }
        }
    }
}

struct EditComponentView: View {
    
    var componentId: NSManagedObjectID
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    @State private var name = ""
    
    var component: Component {
        viewContext.object(with: componentId) as! Component
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
            }
            .navigationBarTitle(Text("Komponente ändern"), displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                self.presentationMode.wrappedValue.dismiss()
            }, trailing: Button("Done") {
                self.presentationMode.wrappedValue.dismiss()
                self.component.name = self.name
                try? self.viewContext.save()
            }
            )
        }
        .onAppear {
            self.name = self.component.name
        }
    }
}

struct ComponentRowView: View {
    @ObservedObject var component: Component
    
    var body: some View {
        HStack {
            Text(component.name)
        }
    }
}

struct EditComponentDataView_Previews: PreviewProvider {
    static var previews: some View {
        EditComponentDataView()
    }
}
