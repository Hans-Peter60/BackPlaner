//
//  RatingStarsView.swift
//  PetersBackPlaner
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

    // System gray/blue only reach 2.1:1 and 2.6:1 on the warm background these
    // stars are drawn on; the theme colors clear the 3:1 needed for meaningful UI.
    var offColor = Theme.subtitle
    var onColor  = Theme.accentText
    
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
        // The row of stars is one piece of information, not five images:
        // read it as a single value instead of announcing every star.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bewertung")
        .accessibilityValue("\(rating) von \(maximumRating) Sternen")
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

    var offColor = Theme.subtitle
    var onColor  = Theme.accentText
    
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
        // Tapping a single star is a pointing gesture VoiceOver cannot aim.
        // Expose the whole row as one adjustable control instead, so the
        // rating can be swiped up/down like a slider.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bewertung")
        .accessibilityValue("\(rating) von \(maximumRating) Sternen")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if rating < maximumRating { rating += 1 }
            case .decrement: if rating > 0 { rating -= 1 }
            @unknown default: break
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
