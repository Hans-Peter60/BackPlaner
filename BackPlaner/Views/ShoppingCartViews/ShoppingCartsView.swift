//
//  ShoppingCartsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 12.01.22.
//

import SwiftUI
import CoreData
import os

struct ShoppingCartsView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    var gridItemLayout = [GridItem(.fixed(80), alignment: .trailing), GridItem(.fixed(80), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading)]

    var dateFormat:DateFormat = DateFormat()
    
    @State private var confirmationShown = false
    
    var body: some View {
        Group {
            if shoppingCarts.isEmpty {
                ContentUnavailableView(
                    "Keine Einkaufslisten",
                    systemImage: "cart",
                    description: Text("Erstelle eine Einkaufsliste direkt aus einem Rezept.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ForEach(shoppingCarts.sorted(by: { $0.date < $1.date }), id: \.self) { shoppingCart in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Einkaufsliste vom " + dateFormat.calculateDate(dT: shoppingCart.date))
                                    .font(Theme.brandFont(20))
                                
                                Spacer()
                                
                                IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Einkaufsliste löschen", title: "Löschen", controlSize: .regular) {
                                    confirmationShown = true
                                }
                                .padding(.trailing)
                                .confirmationDialog("Bist Du sicher?", isPresented: $confirmationShown) {
                                    Button("Ja, löschen") {
                                        withAnimation {
                                            viewContext.delete(shoppingCart)
                                            do {
                                                try viewContext.save()
                                            } catch {
                                                AppLog.shoppingCart.error("Einkaufsliste konnte nicht gelöscht werden: \(error)")
                                            }
                                        }
                                    }
                                    .keyboardShortcut(.defaultAction)

                                    Button("Nein", role: .cancel) {}
                                }
                            }
                            
                            let recipes = (shoppingCart.recipes as? Set<Recipe> ?? []).sorted { $0.name < $1.name }
                            if !recipes.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(recipes) { recipe in
                                        Text("- " + recipe.name)
                                            .font(Theme.brandFont(16))
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                            
                            if shoppingCart.ingredientsArray.isEmpty {
                                Text("Noch keine Zutaten")
                                    .font(Theme.bodyFont(15))
                                    .foregroundColor(Theme.subtitle)
                            } else {
                                ForEach(shoppingCart.ingredientsArray.sorted(by: { $0.name < $1.name })) { ingredient in
                                    HStack {
                                        Text("• " + Rational.getPortion(unit:ingredient.unit ?? "", weight:ingredient.weight, num:ingredient.num, denom:ingredient.denom, targetServings: 2) + ingredient.name)
                                            .font(Theme.bodyFont(15))
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 10)
                        
                        Divider()
                    }
                }
                .padding(.leading)
            }
        }
        .warmBackground()
        .navigationTitle("Einkaufslisten")
    }
}
