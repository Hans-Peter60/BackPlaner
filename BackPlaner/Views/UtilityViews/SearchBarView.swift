//
//  SearchBarView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 05.11.21.
//

import SwiftUI

struct SearchBarView: View {
    
    @Binding var filterBy:  String
    @Binding var nameOrTag: Int
    @Binding var rating:    Int
    var          showRating:Bool

    var body: some View {
        
        VStack {
            HStack {
                Text("Selektion nach:")
                    .font(Font.custom("Avenir", size: 15))
                Picker("", selection: $nameOrTag) {
                    Text("Name").tag(1)
                    Text("Tags").tag(2)
                }
                .font(Font.custom("Avenir", size: 15))
                .pickerStyle(SegmentedPickerStyle())
                .frame(width:160)
            }

            ZStack {
                Rectangle()
                    .foregroundColor(.white)
                    .cornerRadius(5)
                    .shadow(radius: 4)
                    .frame(height: 36)
                
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
            .frame(width: 264, height: 36)
            .foregroundColor(.gray)
            
            if showRating {
                RatingStarsUpdateView(rating: $rating)
            }
        }
    }
}
