//
//  AddToShoppingCart.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 12.01.22.
//

import Foundation
import SwiftUI
import CoreData

struct AddToShoppingCartFB {
    
    var recipeFB:RecipeFB
    
    @Environment(\.managedObjectContext) private var viewContext
    
    
    // ausschließen: Wasser, Salz, Anstellgut, Sauerteig, alles ohne Mengenangabe
    
}
