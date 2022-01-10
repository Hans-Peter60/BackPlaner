//
//  InstructionsFBView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 24.11.21.
//

import SwiftUI
import CoreData

struct InstructionsFBView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel

    var recipeFB: RecipeFB
    var recipeId: NSManagedObjectID?
    
    @State private var dateTime = GlobalVariables.dateTimePicker
    @State private var dateTimeStartSelection     = 0
    @State var         selectedServingSize        = 2
    @State private var showingNotificationMessage = false
    @State private var changeDurationsFlag        = false
    
    var startDates = [Double:Date]()
    
    @State private var durations = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]

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
    var dateCalculation:DateCalculation  = DateCalculation()
    
    var body: some View {
        
        GeometryReader { fullView in
            
            ScrollView(.vertical, showsIndicators: false) {
                
                VStack (alignment: .leading) {
                    
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
                    
                    Group {
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
                            
                            Text("Gewicht: " + String(Int((recipeFB.totalWeight ?? 0) * Double(selectedServingSize) / 2.0)) + "g")
                                    .font(Font.custom("Avenir", size: 15))
                            
                            Spacer()
                            
                           // MARK: Url-Link
                            Link("Link zum Rezept",
                                 destination: URL(string: recipeFB.urlLink)!)
                                .padding(.top, 2)
                                .padding(.leading)
                                .font(Font.custom("Avenir Heavy", size: 15))
                        }
                    }
                    
                    // MARK: Components
                    Group {
                        VStack(alignment: .leading) {
                            Text("Komponenten:")
                                .font(Font.custom("Avenir Heavy", size: 16))
                                .padding([.bottom, .top], 5)
                            
                            LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {
                                
                                ForEach (recipeFB.components.sorted(by: { $0.number < $1.number })) { item in
                                    
                                    VStack(alignment: .leading) {
                                        Text(item.name)
                                            .font(Font.custom("Avenir Heavy", size: 16))
                                            .padding([.bottom, .top], 5)
                                        
                                        VStack(alignment: .leading) {
                                            ForEach (item.ingredients.sorted(by: { $0.number < $1.number })) { ingred in
                                                
                                                let t = "• " + Rational.getPortion(unit:ingred.unit, weight:ingred.weight, num:ingred.num, denom:ingred.denom, targetServings: selectedServingSize)
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
                    }
 
                    // MARK: Selections
                    Group {
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
                    }
                    
                    // MARK: Instructions
                    Group {
                        HStack {
                            Text("Verarbeitungsschritte:")
                                .font(Font.custom("Avenir Heavy", size: 16))
                                .padding([.bottom, .top], 5)
                            
                            Spacer()
                            
                            Text("Bearbeitungdauer: " + Rational.displayHoursMinutes(recipeFB.prepTime))
                                .font(Font.custom("Avenir", size: 16))
                                .padding([.trailing], 5)
                        }
     
                        LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                            Text("Schritt").bold()
                            Text("Beschreibung").bold()
                            Text("Dauer").bold()
                            
                            if changeDurationsFlag {
                                
                                Text("Dauer [Min]").bold()

                                ForEach(recipeFB.instructions.indices) { index in
                                    
                                    let step = Rational.decimalPlace(recipeFB.instructions[index].step, 10)
                                    
                                    Text(step)
                                    Text(recipeFB.instructions[index].instruction)
                                    Text(Rational.displayHoursMinutes(recipeFB.instructions[index].duration))
                                    TextField(String(recipeFB.instructions[index].duration), text: $durations[index])
                                   
                                }
                                .font(Font.custom("Avenir", size: 15))
                            }
                            else {
                                
                                Text("Beginn").bold()

                                ForEach(recipeFB.instructions.sorted(by: { $0.step < $1.step })) { i in
                                    
                                    let step = Rational.decimalPlace(i.step, 10)
                                    
                                    Text(step)
                                    Text(i.instruction)
                                    Text(Rational.displayHoursMinutes(i.duration))
                                   
                                    if dateTimeStartSelection == 0 {
                                        
                                        let date = manager.setNotification(recipeFB.id ?? "", i.instruction, step, i.startTime ?? 0, dateTime, false)
                                        Text(dateCalculation.calculateDateTime(dT: date))
                                    }
                                    else {
                                        let date = manager.setNotification(recipeFB.id ?? "", i.instruction, step, (i.startTime ?? 0) - recipeFB.prepTime, dateTime, false)
                                        Text(dateCalculation.calculateDateTime(dT: date))
                                    }
                                }
                                .font(Font.custom("Avenir", size: 15))
                                
                                Group {
                                    Text(String(Int(recipeFB.instructions[recipeFB.instructions.count - 1].step + 1)))
                                    Text("Fertig")
                                    Text("")
                                    if dateTimeStartSelection == 0 {
                                        let date = Calendar.current.date(byAdding: .minute, value: recipeFB.prepTime, to: dateTime)!
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
                    }
                    
                    // MARK: Reminder setzen
                    HStack {
                        Button(" Reminder setzen ") {
                            
                            var bakeStartTime = 0
                            
                            for i in 0..<recipeFB.instructions.count {
                                
                                if dateTimeStartSelection == 0 {
                                    
                                    let _ = manager.setNotification(recipeFB.id ?? "",
                                                                       recipeFB.instructions[i].instruction,
                                                                       Rational.decimalPlace(recipeFB.instructions[i].step, 10),
                                                                       recipeFB.instructions[i].startTime ?? 0, dateTime, true)
                                }
                                else {
                                    let z = (recipeFB.instructions[i].startTime ?? 0) - recipeFB.prepTime
                                    let _ = manager.setNotification(recipeFB.id ?? "",
                                                                       recipeFB.instructions[i].instruction,
                                                                       Rational.decimalPlace(recipeFB.instructions[i].step, 10),
                                                                       z, dateTime, true)
                                }
                                
                                // If last step (assuming it is the start for baking) then calculate startTime of baking minus time to heat the oven and set a notification
                                if i == recipeFB.instructions.count - 1 {
                                    
                                    bakeStartTime = (recipeFB.instructions[i].startTime ?? 0) - GlobalVariables.vorheizZeit
                                }
                            }
                            showingNotificationMessage = true
                            
                            let i          = InstructionFB()
                            i.id           = UUID().uuidString
                            i.instruction  = GlobalVariables.startHeating
                            
                            for index in 0..<recipeFB.instructions.count {
                                
                                if bakeStartTime < recipeFB.instructions[index].startTime ?? 0 {
                                    
                                    i.step = recipeFB.instructions[index].step - 0.1
                                }
                            }
                            let _         = manager.setNotification(recipeFB.id ?? "", GlobalVariables.startHeating, String(i.step), bakeStartTime, dateTime, true)
                            i.startTime   = bakeStartTime
                            i.duration    = GlobalVariables.vorheizZeit
                            recipeFB.instructions.append(i)

                            let i2 = InstructionFB()
                            let endDate = manager.setNotification(recipeFB.id ?? "", GlobalVariables.bakeEnd, "99", recipeFB.prepTime, dateTime, true)
                            i2.id          = UUID().uuidString
                            i2.instruction = GlobalVariables.bakeEnd
                            i2.step        = 99
                            i2.startTime   = recipeFB.prepTime
                            i2.duration    = 0
                            recipeFB.instructions.append(i2)
                            
                            if dateTimeStartSelection == 0 {
                                uploadNextSteps(recipeFB: recipeFB, date: dateTime)
                            }
                            else {
                                dateTime = Calendar.current.date(byAdding: .minute, value: -recipeFB.prepTime, to: dateTime)!
                                uploadNextSteps(recipeFB: recipeFB, date: dateTime)
                            }
                            
                            let ix  = recipeFB.instructions.firstIndex(where: { $0.instruction == GlobalVariables.startHeating } )
                            recipeFB.instructions.remove(at: ix!)
                            let i2x = recipeFB.instructions.firstIndex(where: { $0.instruction == GlobalVariables.bakeEnd } )
                            recipeFB.instructions.remove(at: i2x!)

                            let bakeHistoryFB        = BakeHistoryFB()
                            bakeHistoryFB.date       = endDate
                            bakeHistoryFB.comment    = "kein Kommentar erfasst"
                            bakeHistoryFB.images     = [GlobalVariables.noImage]
                            recipeFB.bakeHistories.append(bakeHistoryFB)
                            recipeFB.bakeHistoryFlag = true

                            model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipeFB, context: viewContext, recipeImage: UIImage())
                        }
                        .padding()
                        .foregroundColor(.gray)
                        .buttonStyle(.bordered)
                        
                        if changeDurationsFlag {
                            
                            Button(" Dauer übernehmen ") {
                                
                                for i in 0..<recipeFB.instructions.count {
                                    
                                    let cleanedDuration = durations[i].trimmingCharacters(in: .whitespacesAndNewlines)
                                    if Int(cleanedDuration) ?? 0 > 0 { recipeFB.instructions[i].duration = Int(cleanedDuration) ?? 0}
                                }
                                recipeFB.instructions = Rational.calculateStartTimes(recipeFB.instructions, dateTime)
                                
                                recipeFB.prepTime = (recipeFB.instructions[recipeFB.instructions.count - 1].startTime ?? 0) + recipeFB.instructions[recipeFB.instructions.count - 1].duration
                                
                                changeDurationsFlag = false
                            }
                            .padding()
                            .foregroundColor(.gray)
                            .buttonStyle(.bordered)
                        }
                    }
                }.padding()
            }
            .navigationBarTitle("Backanleitung für " + recipeFB.name)
        }
    }
    
    func uploadNextSteps(recipeFB: RecipeFB, date: Date) {
    
        for iFB in recipeFB.instructions {
            
            let n = NextSteps(context: viewContext)
                    
            n.id          = UUID()
            n.recipeName  = recipeFB.name
            n.instruction = iFB.instruction
            n.step        = iFB.step
            n.duration    = iFB.duration
            n.startTime   = iFB.startTime ?? 0
            n.date = Calendar.current.date(byAdding: .minute, value: iFB.startTime ?? 0, to: date)!
        
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
