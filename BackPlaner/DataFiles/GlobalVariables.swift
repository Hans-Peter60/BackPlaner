//
//  GlobalVariables.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import BakePlannerCore
import Foundation
import SwiftUI

extension GlobalVariables {

    static var recipesImage = [String : UIImage]()

    // These three are computed, not stored: `scaledLayoutValue` reads the
    // current text size, and a stored `static var` would freeze whatever it
    // was on first access and never grow with the user's setting.
    static var gridItemLayoutInstructions: [GridItem] { [GridItem(scaledColumnSize(60), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(100), alignment: .trailing), GridItem(scaledColumnSize(120), alignment: .trailing)] }

    static var gridItemLayoutIngredients: [GridItem] { [GridItem(scaledColumnSize(40),  alignment: .leading),  GridItem(scaledColumnSize(80), alignment: .trailing),
                          GridItem(scaledColumnSize(80), alignment: .leading),  GridItem(.flexible(minimum: 200), alignment: .leading),
                          GridItem(scaledColumnSize(40),  alignment: .leading), GridItem(scaledColumnSize(10),              alignment: .trailing),
                          GridItem(scaledColumnSize(40),  alignment: .leading), GridItem(scaledColumnSize(80),              alignment: .trailing)] }
}
