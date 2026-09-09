//
//  SearchBarView.swift
//  PetersBackPlaner
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
                    .font(Theme.bodyFont(15))
                Picker("", selection: $nameOrTag) {
                    Text("Name").tag(1)
                    Text("Tags").tag(2)
                }
                .font(Theme.bodyFont(15))
                .pickerStyle(SegmentedPickerStyle())
                .frame(maxWidth: scaledLayoutValue(160))
                .accessibilityLabel("Selektion nach")
            }

            ZStack {
                Rectangle()
                    .foregroundColor(Theme.card)
                    .cornerRadius(5)
                    .shadow(radius: 4)
                    .frame(height: scaledLayoutValue(36))
                
                HStack {
                    
                    Image(systemName: "magnifyingglass")
                        .accessibilityHidden(true)
                    
                    TextField("Filtern nach...", text: $filterBy)
                        .accessibilityAddTraits(.isSearchField)
                    
                    Button {
                        // Clear the text field
                        filterBy = ""
                    } label: {
                        Image(systemName: "multiply.circle.fill")
                    }
                    .accessibilityLabel("Filter löschen")
                }
                .padding()
            }
            .frame(maxWidth: scaledLayoutValue(264), minHeight: scaledLayoutValue(36))
            // This tints the field's own text too, and .gray only reaches 3.3:1.
            .foregroundColor(Theme.subtitle)
            
            if showRating {
                RatingStarsUpdateView(rating: $rating)
            }
        }
    }
}
