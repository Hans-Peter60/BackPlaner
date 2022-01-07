//
//  SearchBarView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import SwiftUI

struct SearchBarView: View {
    
    @Binding var filterBy: String
    
    var body: some View {
        
        ZStack {
            Rectangle()
                .foregroundColor(.white)
                .cornerRadius(5)
                .shadow(radius: 4)
            
            HStack {
                
                Image(systemName: "magnifyingglass")
                
                TextField("Filtern nach...", text: $filterBy)
                
                Button {
                    // Clear the text field
                    filterBy = ""
                } label: {
                    Image(systemName: "multiply.circle.fill")
                }

            }
            .padding()
        }
        .frame(height: 42)
        .foregroundColor(.gray)
    }
}
