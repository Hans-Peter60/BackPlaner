//
//  RecipeDetailView.swift
//  Recipe List App
//
//  Created by Christopher Ching on 2021-01-14.
//

import SwiftUI

struct RecipeDetailView: View {
    
    var recipe:Recipe
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .leading)]

    @State var selectedServingSize = 2
    
    var body: some View {
        
        ScrollView {
        
            VStack (alignment: .leading) {
                
                // MARK: Recipe Image
                let image = UIImage(data: recipe.image ?? Data()) ?? UIImage()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                    .cornerRadius(5)
                
                // MARK: Recipe title
                Text(recipe.name)
                    .bold()
                    .padding(.top, 20)
                    .padding(.leading)
                    .font(Font.custom("Avenir Heavy", size: 24))
                
                
                // MARK: Serving size picker
                VStack (alignment: .leading) {
                    Text("Select your serving size:")
                        .font(Font.custom("Avenir", size: 15))
                    Picker("", selection: $selectedServingSize) {
                        Text("0.5").tag(1)
                        Text("1.0").tag(2)
                        Text("1.5").tag(3)
                        Text("2.0").tag(4)
                    }
                    .font(Font.custom("Avenir", size: 15))
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width:160)
                }
                .padding()
                
                // MARK: Components
                VStack(alignment: .leading) {
                    Text("Komponenten")
                        .font(Font.custom("Avenir Heavy", size: 16))
                        .padding([.bottom, .top], 5)

                    LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {

                        ForEach (recipe.components.allObjects as! [Component]) { component in
                            
                            VStack(alignment: .leading) {
                                
                                Text(component.name)
                                    .font(Font.custom("Avenir Heavy", size: 14))
                                    .padding([.bottom, .top], 5)
                                
                                VStack(alignment: .leading) {

                                    ForEach (component.ingredients.allObjects as! [Ingredient]) { item in

                                        Text("• " + RecipeModel.getPortion(ingredient: item, recipeServings: recipe.servings, targetServings: selectedServingSize) + " " + item.name.lowercased())
                                            .font(Font.custom("Avenir", size: 15))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                

                Divider()
                
                // MARK: Instructions
                VStack(alignment: .leading) {
                    Text("Verarbeitungsschritte:")
                        .font(Font.custom("Avenir Heavy", size: 16))
                        .padding([.bottom, .top], 5)
                    
                    LazyVGrid(columns: gridItemLayout, spacing: 5) {
                        Text("Schritt").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                      
                        ForEach(recipe.instructions.allObjects as! [Instruction]) { i in
                            
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
    }
}

//struct RecipeDetailView_Previews: PreviewProvider {
//    static var previews: some View {
//        
//        // Create a dummy recipe and pass it into the detail view so that we can see a preview
//        let model = RecipeModel()
//        
//        RecipeDetailView(recipe: model.recipes[0])
//    }
//}
