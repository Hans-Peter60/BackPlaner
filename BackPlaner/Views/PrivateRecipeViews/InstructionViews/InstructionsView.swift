//
//  InstructionsView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 08.12.21.
//

import SwiftUI
import UIKit
import CoreData

struct InstructionsView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @EnvironmentObject var model: RecipeModel
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "id", ascending: true)])
    private var recipes: FetchedResults<Recipe>
    
    var recipe: Recipe
    
    @State private var dateTime = GlobalVariables.dateTimePicker
    @State private var dateTimeStartSelection = 0
    @State var         selectedServingSize = 2
    @State private var showingNotificationMessage = false
    @State private var changeDurationsFlag = false
    @State private var instructions = [Instruction]()
    
    @State private var durations = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]
    
    var gridItemLayoutSelection = [GridItem(.fixed(200), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .center), GridItem(.fixed(180), alignment: .trailing)]
    
    let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents = DateComponents(year: GlobalVariables.year! + 1, month: GlobalVariables.month, day: GlobalVariables.day)
        return calendar.date(from:startComponents)!
        ...
        calendar.date(from:endComponents)!
    }()
    
    var manager:LocalNotificationManager = LocalNotificationManager()
    var dateCalculation:DateCalculation = DateCalculation()
    
    var body: some View {
        
//        copyInstructions(id: recipe.id)
        
        GeometryReader { fullView in
            
            ScrollView(.vertical, showsIndicators: false) {
                
                VStack (alignment: .leading) {
                    
                    let image = UIImage(data: recipe.image ?? Data()) ?? UIImage()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                        .cornerRadius(5)
                    
                    Text("Backanleitung für " + recipe.name)
                        .font(.largeTitle)
                        .padding(.leading)
                    
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
                        
                        // MARK: Url-Link
                        Link("Link zum Rezept",
                             destination: URL(string: (recipe.urlLink ?? "")) ?? URL(string: "https://")!)
                            .padding(.top, 2)
                            .padding(.leading)
                            .font(Font.custom("Avenir Heavy", size: 15))
                    }
                    
                    // MARK: Components
                    VStack(alignment: .leading) {
                        Text("Komponenten:")
                            .font(Font.custom("Avenir Heavy", size: 16))
                            .padding([.bottom, .top], 5)
                        
                        LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {
                            
                            ForEach (recipe.components.allObjects as! [Component]) { item in
                                
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                        .font(Font.custom("Avenir Heavy", size: 16))
                                        .padding([.bottom, .top], 5)
                                    
                                    VStack(alignment: .leading) {
                                        ForEach (item.ingredients.allObjects as! [Ingredient]) { ingred in
                                            
                                            let t = "• " + RecipeModel.getPortion(ingredient: ingred, recipeServings: recipe.servings, targetServings: selectedServingSize) + " "
                                            Text(t + ingred.name)
                                                .font(Font.custom("Avenir", size: 15))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Divider()
                    
                    // MARK: Selections
                    LazyVGrid (columns: gridItemLayoutSelection, spacing: 6) {
                        
                        Picker("", selection: $dateTimeStartSelection) {
                            Text("Starten ab").tag(0)
                            Text("Fertig bis").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .font(Font.custom("Avenir", size: 15))
                        
                        Toggle(isOn: $changeDurationsFlag) {
                            Image(systemName: "hourglass")
                            Text("Dauer ändern")
                        }
                        .font(Font.custom("Avenir Heavy", size: 15))
                        .padding()
                        .frame(width: 220)
                        
                        DatePicker(
                            "",
                            selection: $dateTime,
                            in: dateRange,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                            .padding()
                            .environment(\.locale, Locale.init(identifier: "de"))
                            .font(Font.custom("Avenir", size: 16))
                        
                        let _ = setGlobaldateTime(dateTime)
                    }
                    
                    
                    LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                        Text("Schritt").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                        
//                                                if changeDurationsFlag {
//
//                                                    Text("Dauer [Min]").bold()
//
//                                                    ForEach(recipe.instructions.allObjects as! [Instruction]) { i in
//
//                                                        let step = Rational.decimalPlace(i.step, 10)
//
//                                                        Text(step)
//                                                        Text(i.instruction)
//                                                        Text(Rational.displayHoursMinutes(i.duration))
//                                                        TextField(String(i.duration), text: $durations[Int(step) ?? 0])
//
//                                                    }
//                                                    .font(Font.custom("Avenir", size: 15))
//                                                }
//                                                else {
                        //
                                                    Text("Beginn").bold()
                        
                        ForEach(recipe.instructionsArray, id: \.self) { i in
                        
                                                        let step = Rational.decimalPlace(i.step, 10)
                        
                                                        Text(step)
                                                            .font(Font.custom("Avenir", size: 15))
                                                        Text(i.instruction)
                                                            .font(Font.custom("Avenir", size: 15))
                                                        Text(Rational.displayHoursMinutes(i.duration))
                                                            .font(Font.custom("Avenir", size: 15))
                        
//                                                        if dateTimeStartSelection == 0 {
                                                            let date = manager.setNotification(recipe.name ?? "", i.instruction, step, i.startTime ?? 0, dateTime, false)
                                                            Text(dateCalculation.calculateDateTime(dT: date))
                                                                .font(Font.custom("Avenir", size: 15))
//                                                        }
//                                                        else {
//                                                            let date = manager.setNotification(recipe.id ?? "", i.instruction, step, -recipe.prepTime + (i.startTime ?? 0), dateTime, false)
//                                                            Text(dateCalculation.calculateDateTime(dT: date))
//                                                                .font(Font.custom("Avenir", size: 15))
//                                                        }
                                                    }
                        //
                        //                            Group {
                        //                                Text(String(Int(recipe.instructions[recipe.instructions.count - 1].step + 1)))
                        //                                Text("Fertig")
                        //                                Text("")
                        //                                if dateTimeStartSelection == 0 {
                        //                                    let date = Calendar.current.date(byAdding: .minute, value: recipe.prepTime, to: dateTime)!
                        //                                    Text(dateCalculation.calculateDateTime(dT: date))
                        //                                }
                        //                                else {
                        //                                    Text(dateCalculation.calculateDateTime(dT: dateTime))
                        //                                }
                        //                            }
                        //                            .font(Font.custom("Avenir", size: 15))
                    }
                }
                .padding(.leading)
                
                Divider()
                
                //                    HStack {
                //                        Button(" Mitteilungen senden ") {
                //
                //                            var bakeStartTime = 0
                //
                //                            for i in 0..<recipe.instructions.count {
                //                                let _ = manager.setNotification(recipe.id ?? "",
                //                                                                recipe.instructions[i].instruction,
                //                                                                Rational.decimalPlace(recipe.instructions[i].step, 10),
                //                                                                recipe.instructions[i].startTime ?? 0, dateTime, true)
                //
                //                                // If last step (assuming it is the start for baking) then calculate startTime of baking minus time to heat the oven and set a notification
                //                                if i == recipe.instructions.count - 1 {
                //
                //                                    bakeStartTime = (recipe.instructions[i].startTime ?? 0) - GlobalVariables.vorheizZeit
                //                                }
                //                            }
                //                            showingNotificationMessage = true
                //
                //                            let i = InstructionFB()
                //                            let _ = manager.setNotification(recipeFB.id ?? "", "Backofen anstellen", "98", bakeStartTime, dateTime, true)
                //                            i.id          = UUID().uuidString
                //                            i.instruction = "Backofen anstellen"
                //                            i.step        = 0
                //                            i.startTime   = bakeStartTime
                //                            i.duration    = GlobalVariables.vorheizZeit
                //                            recipeFB.instructions.append(i)
                //
                //                            let i2 = InstructionFB()
                //                            let endDate = manager.setNotification(recipeFB.id ?? "", "Backvorgang ist beendet", "99", recipeFB.prepTime, dateTime, true)
                //                            i2.id          = UUID().uuidString
                //                            i2.instruction = "Backvorgang ist beendet"
                //                            i2.step        = 0
                //                            i2.startTime   = recipeFB.prepTime
                //                            i2.duration    = 0
                //                            recipeFB.instructions.append(i2)
                //
                //                            uploadNextSteps(recipeFB: recipeFB, date: dateTime)
                //
                //                            let bakeHistoryFB     = BakeHistoryFB()
                //                            bakeHistoryFB.date    = endDate
                //                            bakeHistoryFB.comment = "kein Kommentar erfasst"
                //                            bakeHistoryFB.images  = ["no-image-icon-23494"]
                //                            recipeFB.bakeHistories.append(bakeHistoryFB)
                //
                //                            model.uploadRecipeIntoCoreData(recipeFB: recipeFB)
                //
                //                            //                            let recipe = recipes {
                //                            //                                recipes.value(forKey: "id") ?? "" {
                //                            //                                    model.uploadRecipeIntoCoreData(recipeFB: recipeFB)
                //                            //                                }
                //                            //                            }
                //
                //
                //                        }
                //                        .padding()
                //                        .foregroundColor(.gray)
                //                        .buttonStyle(.bordered)
                //
                //                        if changeDurationsFlag {
                //
                //                            Button(" Dauer übernehmen ") {
                //
                //                                for i in 0..<recipeFB.instructions.count {
                //
                //                                    let cleanedDuration = durations[i].trimmingCharacters(in: .whitespacesAndNewlines)
                //                                    if Int(cleanedDuration) ?? 0 > 0 { recipeFB.instructions[i].duration = Int(cleanedDuration) ?? 0}
                //                                }
                //                            }<
                //                            .padding()
                //                            .foregroundColor(.gray)
                //                            .buttonStyle(.bordered)
                //                        }
                //                    }
            }.padding()
        }
    }
}

//struct CopyInstructions {
//    
//    @Environment(\.managedObjectContext) private var viewContext
//    
//    @EnvironmentObject var model: RecipeModel
//    
//    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "id", ascending: true)])
//    private var instructionsCD: FetchedResults<Instruction>
//    
//    var recipe: Recipe
//    
//    @State private var instructions = [Instruction]()
//
//    func copyInstructions(id: UUID) {
//        
//        NSManagedObjectContext *context = [[CBICoreDataController sharedInstance] masterManagedObjectContext];
//        NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
//        NSEntityDescription *entity = [NSEntityDescription entityForName:@"UnsyncedOrders"
//                                                  inManagedObjectContext:context];
//        NSError *error = nil;
//        [fetchRequest setEntity:entity];
//        NSArray *fetchedObjects = [context executeFetchRequest:fetchRequest error:&error];
//        for (UnsyncedOrders *info in fetchedObjects) {
//            [mutableArray addObject:info.items];
//        }
//        
//    }
//}
//    func uploadNextSteps(recipe: Recipe, date: Date) {
//
//        for iFB in recipe.instructions {
//
//            let n = NextSteps(context: viewContext)
//
//            n.id = UUID()
//            n.recipeName = recipe.name
//            n.instruction = iFB.instruction
//            n.step = iFB.step
//            n.duration = iFB.duration
//            n.startTime = iFB.startTime ?? 0
//            n.date = Calendar.current.date(byAdding: .minute, value: iFB.startTime ?? 0, to: date)!
//
//            // Save to core data
//            do {
//                // Save the recipe to core data
//                try viewContext.save()
//            }
//            catch {
//                // Couldn't save the recipe
//            }
//        }
//    }

func setGlobaldateTime(_ date: Date) {
    GlobalVariables.dateTimePicker = date
}


struct CheckboxStyle: ToggleStyle {
    
    func makeBody(configuration: Self.Configuration) -> some View {
        
        return HStack {
            
            configuration.label
            
            Spacer()
            
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(configuration.isOn ? .purple : .gray)
                .font(.system(size: 20, weight: .bold, design: .default))
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
        
    }
}

