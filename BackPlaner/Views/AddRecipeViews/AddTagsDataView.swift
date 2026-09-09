//
//  AddTagsDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.//

import SwiftUI

struct AddTagsDataView: View {
    
    @Binding var tags: [String]
    
    @State private var tag: String = ""
    
    var title:           String
    var placeholderText: String
    
    var gridItemLayout = [GridItem(scaledColumnSize(110), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(44), alignment: .trailing)]
    
    var body: some View {
        
        LazyVGrid(columns: gridItemLayout, spacing: 2) {
            
            Text(verbatim: "\(title):")
                .font(Theme.brandFont(15))
            
            TextField(placeholderText, text: $tag)
                .textFieldStyle(.roundedBorder)
                // The placeholder is an example tag, and the caption sits in a
                // neighbouring grid cell rather than in the control.
                .accessibilityLabel(title)
            
            IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Tag hinzufügen", controlSize: .regular) {
                // Add the item to the list
                if tag.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                    
                    // Add the item to the list
                    tags.append(tag.trimmingCharacters(in: .whitespacesAndNewlines))
                    
                    // Clear the text field
                    tag = ""
                }
            }
            
        }
        .scrollsSidewaysAtLargeText()
        RecipeTagsView(tags: tags)
            .font(Theme.bodyFont(18))
            .padding(.leading, 112)
    }
}
