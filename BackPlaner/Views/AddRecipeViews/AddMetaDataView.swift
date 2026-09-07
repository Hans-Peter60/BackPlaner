//
//  AddMetaDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.//

import SwiftUI

struct AddMetaDataView: View {
    
    @Binding var name:    String
    @Binding var summary: String
    @Binding var urlLink: String
    
    var gridItemLayout = [GridItem(.fixed(110), alignment: .leading), GridItem(.flexible(minimum: 150), alignment: .leading)]

    var body: some View {
        
        LazyVGrid(columns: gridItemLayout, spacing: 2) {
            
            Text("Name: ")
                .font(Theme.brandFont(15))
            TextField("Roggenbrot", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150, idealWidth: 300, maxWidth: 600, alignment: .leading)
        
            Text("Beschreibung: ")
                .font(Theme.brandFont(15))
                .padding(.bottom, 106)
            TextEditor(text: $summary)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3))
                }
                .multilineTextAlignment(.leading)
                .frame(minWidth: 150, idealWidth: 300, maxWidth: 600, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .leading)
                .padding([.top, .bottom])
      
            Text("Url Link: ")
                .font(Theme.brandFont(15))
                
            TextField("https://", text: $urlLink)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150, idealWidth: 300, maxWidth: 600, alignment: .leading)
        }
    }
}
