//
//  AddMetaData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.//

import SwiftUI

struct AddMetaData: View {
    
    @Binding var name: String
    @Binding var summary: String
    @Binding var urlLink: String
    
    var body: some View {
        
        Group {
            
            HStack {
                Text("Name: ")
                    .bold()
                TextField("Tuna Casserole", text: $name)
            }
            
            HStack {
                Text("Beschreibung: ")
                    .bold()
                TextEditor(text: $summary)
                    .navigationTitle("Beschreibung")
            }
            
            HStack {
                Text("Url Link: ")
                    .bold()
                TextField("https://", text: $urlLink)
            }
        }
    }
}

