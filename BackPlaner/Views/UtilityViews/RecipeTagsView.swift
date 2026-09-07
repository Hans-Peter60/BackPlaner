//
//  RecipeTagsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import SwiftUI

struct RecipeTagsView: View {
    
    var allTags = ""
    
    init(tags:[String]) {
        
        // Loop through the tags and build the string
        for index in 0..<tags.count {
            
            // If this is the last item, don't add a comma
            if index == tags.count - 1 {
                allTags += tags[index]
            }
            else {
                allTags += tags[index] + ", "
            }
        }
    }
    
    var body: some View {
        Text(allTags)
    }
}
