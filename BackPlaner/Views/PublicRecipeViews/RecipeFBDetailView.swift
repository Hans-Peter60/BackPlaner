//
//  RecipeFBDetailView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 23.11.21.
//

import SwiftUI

struct RecipeFBDetailView: View {
    
    var recipeFB:RecipeFB
    @EnvironmentObject var modelFB: RecipeFBModel
    
    @State private var instructions: [Int: String] = [:]
    
    @State var selectedServingSize = 2

    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .leading)]
  
    var body: some View {
        
        ScrollView {
            
            VStack (alignment: .leading) {
                
                // MARK: Recipe image
                NavigationLink(
                    destination: ShowBigImageView(image: (GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()).jpegData(compressionQuality: 1.0) ?? Data() )
                )
                {
                    Image(uiImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                        .cornerRadius(5)
                }
                
                // MARK: Recipe summary
                Text(recipeFB.summary)
                    .padding(.top, 2)
                    .padding(.leading)
                    .font(Font.custom("Avenir", size: 15))
                
                HStack {
                    // MARK: Serving size picker
                    HStack {
                        Text("Wähle die Portionsgröße:")
                            .font(Font.custom("Avenir", size: 15))
                        Picker("", selection: $selectedServingSize) {
                            Text("0,5").tag(1)
                            Text("1,0").tag(2)
                            Text("1,5").tag(3)
                            Text("2,0").tag(4)
                        }
                        .font(Font.custom("Avenir", size: 15))
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width:160)
                    }
                    .padding()
                    
                    Spacer()
                    
                    // MARK: Recipe urlLink
                    Link("Link zum Rezept",
                         destination: URL(string: recipeFB.urlLink)!)
                        .padding(.top, 2)
                        .padding(.leading)
                        .font(Font.custom("Avenir Heavy", size: 15))
                }
                
               // MARK: Components
                VStack(alignment: .leading) {
                    Text("Komponenten:")
                        .font(Font.custom("Avenir Heavy", size: 16))
                        .padding([.bottom, .top], 2)
                    
                    LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {

                        ForEach (recipeFB.components.sorted(by: { $0.id < $1.id })) { item in
                            
                            VStack(alignment: .leading) {

                            Text(item.name)
                                .font(Font.custom("Avenir Heavy", size: 14))
                                .padding([.bottom, .top], 5)
                            
                            VStack(alignment: .leading) {
                                ForEach (item.ingredients) { ingred in
                                    
                                    let t = "• " + RecipeFBModel.getPortion(ingredient: ingred, recipeServings: recipeFB.servings, targetServings: selectedServingSize) + " "
                                    Text(t + ingred.name)
                                        .font(Font.custom("Avenir", size: 15))
                                }
                            }                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // MARK: Divider
                Divider()
                
                // MARK: Instructions
                VStack(alignment: .leading) {
                    HStack {
                        Text("Verarbeitungsschritte:")
                            .font(Font.custom("Avenir Heavy", size: 16))
                            .padding([.bottom, .top], 5)
                        
                        Spacer()
                        
                        Text("Bearbeitungdauer: " + Rational.displayHoursMinutes(recipeFB.prepTime))
                            .font(Font.custom("Avenir", size: 16))
                            .padding([.trailing], 5)
                    }
                    
                    LazyVGrid(columns: gridItemLayout, spacing: 5) {
                        Text("Schritt").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                      
                        ForEach(recipeFB.instructions.sorted(by: { $0.step < $1.step })) { i in
                            
                            let step = Rational.decimalPlace(i.step, 10)
                            Text(step)
                            Text(i.instruction)
                            Text(Rational.displayHoursMinutes(i.duration))
                        }
                        .padding(.horizontal)
                    }
                    .font(Font.custom("Avenir", size: 16))
                        .padding([.bottom, .top], 5)
                }
            }
            .padding()
        }
        .navigationTitle(recipeFB.name)
            // MARK: Recipe title
//            Text()
//                .bold()
//                .padding(.top, 10)
//                .padding(.leading)
//                .font(Font.custom("Avenir Heavy", size: 24))

    }
}

//struct RecipeFBDetailView_Previews: PreviewProvider {
//    
//    static var previews: some View {
//        
//        let modelFB = RecipeFBModel()
//        
//        RecipeFBDetailView(recipeFB: modelFB.recipesFB[0])
//    }
//}
