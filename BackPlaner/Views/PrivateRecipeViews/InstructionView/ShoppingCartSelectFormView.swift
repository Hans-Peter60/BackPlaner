//
//  ShoppingCardSelectFormView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 13.01.22.
//

import SwiftUI
import CoreData

struct ShoppingCartSelectFormView: View {
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    
    var recipe: Recipe
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]) // , predicate: NSPredicate(format: "shoppingCarts != nil"))
    var ingredients: FetchedResults<Ingredient>
    
    @State private var ingredientName = ""
    
    private var filteredIngredients: [Ingredient] {
        
        return ingredients.filter { i in
                return i.name.contains(ingredientName)
        }
    }

    @EnvironmentObject var model:   RecipeModel
    
    var dateFormat:DateFormat = DateFormat()
    let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents   = DateComponents(year: GlobalVariables.year! + 1, month: GlobalVariables.month, day: GlobalVariables.day)
        return calendar.date(from:startComponents)!
        ...
        calendar.date(from:endComponents)!
    }()
    
    @State private var selectedShoppingCartId: NSManagedObjectID?
    
    @State private var date            = Date()
    @State private var disableDateFlag = true
    @State private var showingSheet    = false
    
    var body: some View {
        
        Form {
            
            HStack {
                
                Section {
                    Text("Neue Einkaufsliste hinzufügen")
                    
                    DatePicker(
                        "",
                        selection: $date,
                        in: dateRange,
                        displayedComponents: [.date]
                    )
                        .onTapGesture { disableDateFlag = false }
                        .padding()
                        .environment(\.locale, Locale.init(identifier: "de"))
                        .font(Font.custom("Avenir Heavy", size: 18))
                    
                    Button("Add") {
                        
                        let shoppingCart  = ShoppingCart(context: viewContext)
                        shoppingCart.id   = UUID()
                        shoppingCart.date = date
                        
                        do {
                            try viewContext.save()
                        } catch {
                            // handle the Core Data error
                        }
                        
                        disableDateFlag.toggle()
                    }
                    .disabled(disableDateFlag)
                    .buttonStyle(.bordered)
                }
                .font(Font.custom("Avenir", size: 16))
            }
            
            ForEach(shoppingCarts.sorted(by: { $0.date < $1.date }), id: \.self) { shoppingCart in
                
                HStack {
                    Text("Einkaufsliste vom " + dateFormat.calculateDate(dT: shoppingCart.date))
                        .onTapGesture {
                            
                            shoppingCart.addToRecipes(recipe)

                             for c in recipe.componentsArray {
                                 
                                 for i in c.ingredientsArray {
                                     
                                     if i.name.contains("Wasser") || i.name.contains("Salz") || i.name.contains("Anstellgut") || i.name.contains("Sauerteig") || i.normWeight == 0 {

                                         // do nothing
                                     }
                                     else {
                                         
                                         let ingredient = shoppingCart.ingredientsArray.first(where: {$0.name == i.name})
                                             
                                         if ingredient?.name == i.name {
                                                     
                                             if ingredient!.unit == i.unit {

                                                 ingredient!.setValue(ingredient!.weight + i.weight, forKey: "weight")
                                                 ingredient!.setValue(ingredient!.normWeight + i.normWeight, forKey: "normWeight")
                                                 
                                                 if ingredient!.num != i.denom {
                                                     
                                                     let num   = (ingredient!.num   * i.denom) + (i.num * ingredient!.denom)
                                                     let denom =  ingredient!.denom * i.denom
                                                     let gcd   = Rational.greatestCommonDivisor(num, denom)
                                                     
                                                     ingredient!.setValue(num   / gcd, forKey: "num")
                                                     ingredient!.setValue(denom / gcd, forKey: "denom")
                                                 }
                                                 
                                                 do {
                                                     try viewContext.save()
                                                 }
                                                 catch {
                                                     // handle the Core Data error
                                                 }
                                             }
                                         }
                                         else {
                                             let ingredient = Ingredient(context: viewContext)
                                             
                                             ingredient.id         = UUID()
                                             ingredient.name       = i.name
                                             ingredient.unit       = i.unit
                                             ingredient.weight     = i.weight
                                             ingredient.num        = i.num
                                             ingredient.denom      = i.denom
                                             ingredient.normWeight = i.normWeight
                                             ingredient.number     = 0
                                             
                                             shoppingCart.addToIngredients(ingredient)
                                         }
                                    }
                                }
                            }
                        }
                        .font(Font.custom("Avenir Heavy", size: 16))
                    
                    Spacer()
                    
                    Button("Del") {
                        viewContext.delete(shoppingCart)
                        
                        do {
                            try viewContext.save()
                        } catch {
                            // handle the Core Data error
                        }
                    }
                    .font(Font.custom("Avenir", size: 15))
                    .padding()
                    .foregroundColor(.blue)
                    .buttonStyle(.bordered)
                }
            }
            .navigationBarTitle(Text("Bitte die Einkaufsliste auswählen"), displayMode: .inline)
            .navigationBarItems(leading: Button("Zurück") {
                self.presentationMode.wrappedValue.dismiss()
            }
            )
        }
        .padding()
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
