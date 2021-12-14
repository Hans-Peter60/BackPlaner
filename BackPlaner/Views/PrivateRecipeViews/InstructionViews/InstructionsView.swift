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
    
//    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "id", ascending: true)])
//    private var recipes: FetchedResults<Recipe>
    
    var recipe: Recipe
    
    @State private var dateTime = GlobalVariables.dateTimePicker
    @State private var dateTimeStartSelection     = 0
    @State var         selectedServingSize        = 2
    @State private var showingNotificationMessage = false
    @State private var changeDurationsFlag        = false
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

                        if changeDurationsFlag {

                            Text("Dauer [Min]").bold()

                            ForEach(recipe.instructionsArray.indices) { index in

                                let step = Rational.decimalPlace(recipe.instructionsArray[index].step, 10)

                                Text(step)
                                Text(recipe.instructionsArray[index].instruction)
                                Text(Rational.displayHoursMinutes(recipe.instructionsArray[index].duration))
                                TextField(String(recipe.instructionsArray[index].duration), text: $durations[index])

                            }
                            .font(Font.custom("Avenir", size: 15))
                        }
                        else {
                            
                            Text("Beginn").bold()
                            
                            ForEach(recipe.instructionsArray.indices) { index in

                                let step = Rational.decimalPlace(recipe.instructionsArray[index].step, 10)

                                Text(step)
                                    .font(Font.custom("Avenir", size: 15))
                                Text(recipe.instructionsArray[index].instruction)
                                    .font(Font.custom("Avenir", size: 15))
                                Text(Rational.displayHoursMinutes(recipe.instructionsArray[index].duration))
                                    .font(Font.custom("Avenir", size: 15))

                                if dateTimeStartSelection == 0 {
                                    let date = manager.setNotification(recipe.firestoreId ?? "", recipe.instructionsArray[index].instruction, step, recipe.instructionsArray[index].startTime ?? 0, dateTime, false)
                                    Text(dateCalculation.calculateDateTime(dT: date))
                                        .font(Font.custom("Avenir", size: 15))
                                }
                                else {
                                    let date = manager.setNotification(recipe.firestoreId ?? "", recipe.instructionsArray[index].instruction, step, -recipe.prepTime + (recipe.instructionsArray[index].startTime ?? 0), dateTime, false)
                                    Text(dateCalculation.calculateDateTime(dT: date))
                                        .font(Font.custom("Avenir", size: 15))
                                }
                            }

                            Group {
                                Text(String(Int(recipe.instructionsArray[recipe.instructionsArray.count - 1].step + 1)))
                                Text("Fertig")
                                Text("")
                                if dateTimeStartSelection == 0 {
                                    let date = Calendar.current.date(byAdding: .minute, value: recipe.prepTime, to: dateTime)!
                                    Text(dateCalculation.calculateDateTime(dT: date))
                                }
                                else {
                                    Text(dateCalculation.calculateDateTime(dT: dateTime))
                                }
                            }
                            .font(Font.custom("Avenir", size: 15))
                        }
                    }
                    .padding(.leading)

                    Divider()

                    HStack {
                        Button(" Mitteilungen senden ") {

                            var bakeStartTime = 0

                            for i in 0..<recipe.instructionsArray.count {
                                let _ = manager.setNotification(recipe.firestoreId ?? "",
                                                                recipe.instructionsArray[i].instruction,
                                                                Rational.decimalPlace(recipe.instructionsArray[i].step, 10),
                                                                recipe.instructionsArray[i].startTime, dateTime, true)

                                // If last step (assuming it is the start for baking) then calculate startTime of baking minus time to heat the oven and set a notification
                                if i == recipe.instructions.count - 1 {

                                    bakeStartTime = (recipe.instructionsArray[i].startTime) - GlobalVariables.vorheizZeit
                                }
                            }
                            showingNotificationMessage = true

                            let i         = Instruction(context: viewContext)
                            i.id          = UUID()
                            i.instruction = GlobalVariables.startHeating
                            for index in 0..<recipe.instructionsArray.count {
                                if bakeStartTime < recipe.instructionsArray[index].startTime {

                                    i.step = recipe.instructionsArray[index].step - 0.1
                                }
                            }
                            let _ = manager.setNotification(recipe.firestoreId ?? "", GlobalVariables.startHeating, String(i.step), bakeStartTime, dateTime, true)
                            i.startTime   = bakeStartTime
                            i.duration    = GlobalVariables.vorheizZeit
                            recipe.addToInstructions(i)

                            let i2 = Instruction(context: viewContext)
                            let endDate = manager.setNotification(recipe.firestoreId ?? "", GlobalVariables.bakeEnd, "99", recipe.prepTime, dateTime, true)
                            i2.id          = UUID()
                            i2.instruction = GlobalVariables.bakeEnd
                            i2.step        = 99
                            i2.startTime   = recipe.prepTime
                            i2.duration    = 0
                            recipe.addToInstructions(i2)

                            uploadNextSteps(recipe: recipe, date: dateTime)

                            let bakeHistory     = BakeHistory(context: viewContext)
                            bakeHistory.date    = endDate
                            bakeHistory.comment = "kein Kommentar erfasst"
                            bakeHistory.images  = [UIImage(named: "no-image-icon-23494")?.jpegData(compressionQuality: 1.0) ?? Data()]
                            recipe.addToBakeHistories(bakeHistory)

                            // Save to core data
                            do {
                                // Save the recipe to core data
                                try viewContext.save()

                                // Switch the view to list view
                            }
                            catch {
                                // Couldn't save the recipe
                                print("Couldn't save the recipe")
                            }
                        }
                        .padding()
                        .foregroundColor(.gray)
                        .buttonStyle(.bordered)

                        if changeDurationsFlag {

                            Button(" Dauer übernehmen ") {

                                var instructionsFB = [InstructionFB]()
                                
                                for i in 0..<recipe.instructionsArray.count {

                                    let cleanedDuration = durations[i].trimmingCharacters(in: .whitespacesAndNewlines)
                                    if Int(cleanedDuration) ?? 0 > 0 { recipe.instructionsArray[i].duration = Int(cleanedDuration) ?? 0}
                                    
                                    let instruction = InstructionFB()
                                    instruction.instruction = recipe.instructionsArray[i].instruction
                                    instruction.step        = recipe.instructionsArray[i].step
                                    instruction.startTime   = recipe.instructionsArray[i].startTime
                                    instruction.duration    = recipe.instructionsArray[i].duration
                                    instructionsFB.append(instruction)

                                }
                                instructionsFB = Rational.calculateStartTimes(instructionsFB, dateTime)
                                
                                for i in 0..<recipe.instructionsArray.count {
                                    recipe.instructionsArray[i].instruction = instructionsFB[i].instruction
                                    recipe.instructionsArray[i].step        = instructionsFB[i].step
                                    recipe.instructionsArray[i].startTime   = instructionsFB[i].startTime ?? 0
                                    recipe.instructionsArray[i].duration    = instructionsFB[i].duration
                                }
                                changeDurationsFlag = false
                            }
                            .padding()
                            .foregroundColor(.gray)
                            .buttonStyle(.bordered)
                        }
                    }
                }.padding()
            }
        }
    }
    
    func uploadNextSteps(recipe: Recipe, date: Date) {

        for i in recipe.instructionsArray {

            let n = NextSteps(context: viewContext)

            n.id          = UUID()
            n.recipeName  = recipe.name
            n.instruction = i.instruction
            n.step        = i.step
            n.duration    = i.duration
            n.startTime   = i.startTime
            n.date = Calendar.current.date(byAdding: .minute, value: i.startTime, to: date)!

            // Save to core data
            do {
                // Save the recipe to core data
                try viewContext.save()
            }
            catch {
                // Couldn't save the recipe
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
}


