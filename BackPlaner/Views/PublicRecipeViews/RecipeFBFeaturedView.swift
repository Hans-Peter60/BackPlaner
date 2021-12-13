//
//  RecipeFBFeaturedView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 25.11.21.
//

import SwiftUI

struct RecipeFBFeaturedView: View {
    
    @EnvironmentObject var modelFB: RecipeFBModel
    
    @State var isDetailViewShowing = false
    @State var tabSelectionIndex = 0

    var body: some View {
        
        VStack(alignment: .leading, spacing: 0) {

            Text("Featured Recipes")
                .bold()
                .padding(.leading)
                .padding(.top, 40)
                .font(Font.custom("Avenir Heavy", size: 24))


            GeometryReader { geo in

                TabView (selection: $tabSelectionIndex) {

                    // Loop through each recipe
                    ForEach (0..<modelFB.recipesFB.count) { index in

                        // Recipe card button
                        Button(action: {

                            // Show the recipe detail sheet
                            self.isDetailViewShowing = true

                        }, label: {

                            // Recipe card
                            ZStack {
                                Rectangle()
                                    .foregroundColor(.white)


                                VStack(spacing: 0) {
//                                    let image = UIImage(data: recipes[index].image ?? Data()) ?? UIImage()
                                    Image(modelFB.recipesFB[index].image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .clipped()
                                    Text(modelFB.recipesFB[index].name)
                                        .padding(5)
                                        .font(Font.custom("Avenir", size: 15))
                                }
                            }
                        })
                        .tag(index)
                        .sheet(isPresented: $isDetailViewShowing) {
                            // Show the Recipe Detail View
                            RecipeFBDetailView(recipeFB: modelFB.recipesFB[index])
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(width: geo.size.width - 40, height: geo.size.height - 100, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                        .cornerRadius(15)
                        .shadow(color: Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.5), radius: 10, x: -5, y: 5)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            }

            VStack (alignment: .leading, spacing: 10) {

                if modelFB.recipesFB.count > 0 && tabSelectionIndex < modelFB.recipesFB.count {
                    Text("Preparation Time:")
                        .font(Font.custom("Avenir Heavy", size: 16))

                    Text("\(Rational.displayHoursMinutes(modelFB.recipesFB[tabSelectionIndex].prepTime))")
                        .font(Font.custom("Avenir", size: 15))
                    
                    Text("Tags")
                        .font(Font.custom("Avenir Heavy", size: 16))
                    RecipeTags(tags: modelFB.recipesFB[tabSelectionIndex].tags)
                }
            }
            .padding([.leading, .bottom])
        }
//        .onAppear(perform: {
//            setFeaturedIndex()
//        })
    }
    
//    func setFeaturedIndex() {
//
//        // Find the index of first recipe that is featured
//        let index = recipes.firstIndex { (recipe) -> Bool in
//            return recipe.featured
//        }
//        tabSelectionIndex = index ?? 0
//    }
}

//struct RecipeFBFeaturedView_Previews: PreviewProvider {
//    static var previews: some View {
//        RecipeFBFeaturedView()
//            .environmentObject(RecipeFBModel())
//    }
//}
