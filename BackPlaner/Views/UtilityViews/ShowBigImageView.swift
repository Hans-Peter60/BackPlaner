//
//  ShowBigImageView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 17.12.21.
//

import SwiftUI

struct ShowBigImageView: View {
    
    var image: Data
    
    @State var tabSelectionIndex = 0
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 0) {
            
            GeometryReader { geo in
                        
                // Image card
                ZStack {
                    Rectangle()
                        .foregroundColor(.white)
                    
                    VStack(spacing: 0) {
                        let image = UIImage(data: image) ?? UIImage()
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    }
                }
                .frame(width: geo.size.width - 100, height: geo.size.height - 200, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                .cornerRadius(15)
                .shadow(color: Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.5), radius: 10, x: -5, y: 5)
            }
        }
        .padding([.leading, .bottom])
    }
}

struct ShowBigImagesView: View {
    @Environment(\.presentationMode) var presentation
    
    var images: [Data]
    var index:  Int
    
    @State var tabSelectionIndex = 0
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 0) {
            
            GeometryReader { geo in
                  
                TabView (selection: $tabSelectionIndex) {
                    
                    // Loop through each recipe
                    ForEach (images, id: \.self) { image in

                        // Image card
                        ZStack {
                            Rectangle()
                                .foregroundColor(.white)
                            
                            VStack(spacing: 0) {
                                let image = UIImage(data: image) ?? UIImage()
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipped()
                            }
                        }
                        .frame(width: geo.size.width - 100, height: geo.size.height - 200, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                        .cornerRadius(15)
                        .shadow(color: Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.5), radius: 10, x: -5, y: 5)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            }
        }
        .padding([.leading, .bottom])
        .onAppear(perform: {
            setImageIndex()
        })
    }
    
    func setImageIndex() {
        
        tabSelectionIndex = index
    }
}


