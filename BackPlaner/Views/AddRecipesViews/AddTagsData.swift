//
//  AddTagsData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.//

import SwiftUI

struct AddTagsData: View {
    
    @Binding var tags: [String]
    
    @State private var tag: String = ""
    
    var title:           String
    var placeholderText: String
    
    var gridItemLayout = [GridItem(.fixed(120), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .trailing)]
    
    var body: some View {
        
        LazyVGrid(columns: gridItemLayout, spacing: 2) {
            
            Text("\(title):")
                .bold()
            
            TextField(placeholderText, text: $tag)
                .textFieldStyle(.roundedBorder)
            
            Button("Add") {
                // Add the item to the list
                if tag.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                    
                    // Add the item to the list
                    tags.append(tag.trimmingCharacters(in: .whitespacesAndNewlines))
                    
                    // Clear the text field
                    tag = ""
                }
            }
            .buttonStyle(.bordered)
            
        }
        RecipeTags(tags: tags)
    }
}
