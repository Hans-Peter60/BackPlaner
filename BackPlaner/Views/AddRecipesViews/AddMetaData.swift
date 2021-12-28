//
//  AddMetaData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.//

import SwiftUI

struct AddMetaData: View {
    
    @Binding var name:    String
    @Binding var summary: String
    @Binding var urlLink: String
    
    var gridItemLayout = [GridItem(.fixed(120), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading)]

    var body: some View {
        
        LazyVGrid(columns: gridItemLayout, spacing: 2) {
            
            Text("Name: ")
                .bold()
            TextField("Roggenbrot", text: $name)
                .frame(minWidth: 200, idealWidth: 300, maxWidth: 600, alignment: .leading)
        
            Text("Beschreibung: ")
                .bold()
            TextEditor(text: $summary)
                .multilineTextAlignment(.leading)
                .border(Color.blue, width: /*@START_MENU_TOKEN@*/1/*@END_MENU_TOKEN@*/)
                .frame(minWidth: 200, idealWidth: 300, maxWidth: 600, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .leading)
                .padding([.top, .bottom])
      
            Text("Url Link: ")
                .bold()
                
            TextField("https://", text: $urlLink)
                .frame(minWidth: 200, idealWidth: 300, maxWidth: 600, alignment: .leading)
        }
        .opacity(/*@START_MENU_TOKEN@*/0.8/*@END_MENU_TOKEN@*/)
    }
}

