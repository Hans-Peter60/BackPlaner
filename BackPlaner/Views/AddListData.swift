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
    
    var body: some View {
        
        VStack (alignment: .leading) {
            
            HStack {
                Text("\(title):")
                    .bold()
                
                TextField(placeholderText, text: $item)
                
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
            
            // List out the items added so far
//            ForEach(list, id: \.self) { item in
//                Text(item)
//            }
            RecipeTags(tags: list)
        }
    }
}
