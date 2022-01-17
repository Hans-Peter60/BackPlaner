//
//  ShoppingCartsView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 12.01.22.
//

import SwiftUI
import CoreData

struct ShoppingCartsView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    var gridItemLayout = [GridItem(.fixed(80), alignment: .trailing), GridItem(.fixed(80), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading)]

    var dateFormat:DateFormat = DateFormat()
    let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents   = DateComponents(year: GlobalVariables.year! + 1, month: GlobalVariables.month, day: GlobalVariables.day)
        return calendar.date(from:startComponents)!
        ...
        calendar.date(from:endComponents)!
    }()
    
    @State private var deleteFlag = false
    
    var body: some View {
        
//        if shoppingCarts.count > 0 { deleteFlag = true } else { deleteFlag = false }
        
        Button("Einkaufsliste löschen") {
            
            let deleteFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "ShoppingCart")
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: deleteFetch)
            
            do {
                try viewContext.execute(deleteRequest)
                try viewContext.save()
            } catch {
                print ("There was an error")
            }
            deleteFlag = false
        }
        .padding()
        .foregroundColor(deleteFlag ? Color.blue : Color.gray)
        .buttonStyle(.bordered)
        
        ScrollView {
                
            ForEach(shoppingCarts.sorted(by: { $0.date < $1.date }), id: \.self) { shoppingCart in
                
                HStack {
                    Text("Einkaufsliste vom " + dateFormat.calculateDate(dT: shoppingCart.date))
                        .font(Font.custom("Avenir Heavy", size: 16))
                    Spacer()
                }
                
                ForEach(shoppingCart.recipes.allObjects as! [Recipe]) { recipe in
                    HStack {
                        Text(recipe.name)
                            .font(Font.custom("Avenir", size: 15))
                        Spacer()
                    }
                }
                    
                ForEach(shoppingCart.ingredientsArray.sorted(by: { $0.name < $1.name })) { ingredient in
                    HStack {
                        Text("• " + Rational.getPortion(unit:ingredient.unit ?? "", weight:ingredient.weight, num:ingredient.num, denom:ingredient.denom, targetServings: 2) + ingredient.name)
                            .font(Font.custom("Avenir", size: 15))
                        Spacer()
                    }
                }
                
                Divider()
            }
        }
        .padding(.leading)
        .navigationTitle("Einkaufsliste")
        .onAppear {
            if shoppingCarts.count > 0 { deleteFlag = true }
        }
    }
}
