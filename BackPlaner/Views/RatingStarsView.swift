//
//  RatingStarsView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 29.12.21.
//

import SwiftUI

struct RatingStarsView: View {
    
    var rating: Int

    var label = "Bewertung:   "

    var maximumRating = 5

    var offImage = Image(systemName: "star")
    var onImage  = Image(systemName: "star.fill")

    var offColor = Color.gray
    var onColor  = Color.blue
    
    var body: some View {
        
        HStack {
            if label.isEmpty == false {
                Text(label)
            }

            ForEach(1..<maximumRating + 1, id: \.self) { number in
                image(for: number)
                    .foregroundColor(number > rating ? offColor : onColor)
            }
        }
    }
    
    func image(for number: Int) -> Image {
        if number > rating {
            return offImage
        } else {
            return onImage
        }
    }
}

struct RatingStarsUpdateView: View {
    
    @Binding var rating: Int

    var label = "Bewertung:"

    var maximumRating = 5

    var offImage = Image(systemName: "star")
    var onImage  = Image(systemName: "star.fill")

    var offColor = Color.gray
    var onColor  = Color.yellow
    
    var body: some View {
        
        HStack {
            if label.isEmpty == false {
                Text(label)
            }

            ForEach(1..<maximumRating + 1, id: \.self) { number in
                image(for: number)
                    .foregroundColor(number > rating ? offColor : onColor)
                    .onTapGesture {
                        if rating == 1 {
                            rating = 0
                        } else {
                            rating = number
                        }
                    }
            }
        }
    }
    
    func image(for number: Int) -> Image {
        if number > rating {
            return offImage
        } else {
            return onImage
        }
    }
}


struct RatingStarsView_Previews: PreviewProvider {
    
    static var previews: some View {
        RatingStarsView(rating: 4)
    }
}
