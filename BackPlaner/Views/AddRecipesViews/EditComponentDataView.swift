//
//  EditComponentDataView.swift
//  BackPlaner
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
    var components: FetchedResults<Component> { componentsRequest.wrappedValue }
    
    init(recipeId: NSManagedObjectID) {
        self.recipeId = recipeId
        self.componentsRequest = FetchRequest(entity: Component.entity(), sortDescriptors: [], predicate: NSPredicate(format: "recipe == %@", recipeId))
    }

    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    
    @State private var componentName = ""
    @State private var showingSheet  = false
    @State private var selectedComponentId: NSManagedObjectID?
    
    var body: some View {
        
        ScrollView {
            
            // MARK: Components
            VStack(alignment: .leading) {
                
                ForEach (components.sorted(by: { $0.number < $1.number }), id: \.self) { component in
                    
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

struct EditComponentView: View {
    
    var componentId: NSManagedObjectID?
    
    @EnvironmentObject var model:   RecipeModel
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    
    @State private var componentName   = ""
    @State private var componentNumber = 0
    
    @State private var name   = ""
    @State private var number = 0
    @State private var unit   = ""
    @State private var num    = 0
    @State private var denom  = 0
    @State private var weight = 0.0
    
    var component: Component {
        viewContext.object(with: componentId!) as! Component
    }
    
    var body: some View {
        
        NavigationView {
        
            Form {
                Section {
                    HStack {
                        Text("Nr.")
                            .frame(width: 40)
                        Text("Komponente")
                    }
                    HStack {
                        TextField("Nr.", value: $componentNumber, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 40)
                        TextField("...", text: $componentName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Section {
          
                    Text("Zutaten")
                        .font(Font.custom("Avenir Heavy", size: 16))
                        .padding([.bottom, .top], 5)
                    
                    LazyVGrid(columns: GlobalVariables.gridItemLayoutIngredients, spacing: 6) {
                        
                        Group {
                            Text("Nr.")
                            Text("Gewicht")
                            Text("Einheit")
                            Text("Zutat")
                            Text("Z")
                            Text("/")
                            Text("N")
                            Text("")
                        }
                        
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
                            
                            // Check that all relevant fields are filled in
                            if name == "" {
                                return
                            }
                            
                            let componentCD: Component
                            if let objectId = componentId,
                               let fetchedComponent = model.fetchComponent(for: objectId, context: viewContext) {
                                componentCD = fetchedComponent
                            } else {
                                
                                return
                            }
                            
                            let i         = Ingredient(context: viewContext)
                            i.id          = UUID()
                            i.name        = name
                            i.number      = number
                            i.num         = num
                            i.denom       = denom
                            i.weight      = weight
                            i.unit        = unit
                            
                            componentCD.addToIngredients(i)
                            
                            componentName = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    
                }
                .navigationBarTitle(Text("Komponente ändern"), displayMode: .inline)
                .navigationBarItems(leading: Button("Cancel") {
                    self.presentationMode.wrappedValue.dismiss()
                }, trailing: Button("Done") {
                    self.presentationMode.wrappedValue.dismiss()
                    self.component.name   = self.componentName
                    self.component.number = self.componentNumber
                    
                    try? self.viewContext.save()
                }
                )
                if componentId != nil { EditIngredientDataView(componentId: componentId!) }
            }
            .onAppear {
                self.componentName   = self.component.name
                self.componentNumber = self.component.number
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
