//
//  AddListData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.//

import SwiftUI

struct AddListData: View {
    
    @Binding var list: [String]
    
    @State private var item: String = ""
    
    var title: String
    var placeholderText: String
    
    var gridItemLayout = [GridItem(.fixed(120), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .trailing)]
    
    var body: some View {
        
        LazyVGrid(columns: gridItemLayout, spacing: 2) {
            
            Text("\(title):")
                .bold()
            
            TextField(placeholderText, text: $item)
                .textFieldStyle(.roundedBorder)
            
            Button("Add") {
                // Add the item to the list
                if item.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                    
                    // Add the item to the list
                    list.append(item.trimmingCharacters(in: .whitespacesAndNewlines))
                    
                    // Clear the text field
                    item = ""
                }
            }
            .buttonStyle(.bordered)
            
        }
        RecipeTags(tags: list)
    }
}
