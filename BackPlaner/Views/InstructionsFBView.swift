//
//  InstructionsFBView.swift
//  BackPlaner2
//
//  Created by Hans-Peter Müller on 24.11.21.
//

import SwiftUI

struct InstructionsFBView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    var recipeFB: RecipeFB
    @EnvironmentObject var modelFB:RecipeFBModel
    
    @State private var dateTime = GlobalVariables.dateTimePicker
    @State private var dateTimeStartSelection = 0
    @State var selectedServingSize = 2
    @State private var showingNotificationMessage = false
    @State private var instructions = [InstructionFB]()
    
    //    let durations: KeyValuePairs <String, Int> = {
    //        for (recipeFB.instructions) { i in
    //            durations(i.step) = i.duration
    //        }
    //    }
    
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
                    
                    Image(uiImage: modelFB.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                        .cornerRadius(5)
                    
                    Text("Backanleitung für " + recipeFB.name)
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
                             destination: URL(string: recipeFB.urlLink)!)
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
                            
                            ForEach (recipeFB.components) { item in
                                
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
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Divider()
 
                    HStack {
                        Spacer()
                        
                        Picker("", selection: $dateTimeStartSelection) {
                            Text("Starten ab").tag(0)
                            Text("Fertig bis").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        DatePicker(
                            "",
                            selection: $dateTime,
                            in: dateRange,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                            .padding()
                            .environment(\.locale, Locale.init(identifier: "de"))
                        
                        let _ = setGlobaldateTime(dateTime)
                    }
                    
                    LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                        Text("Schritt").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                        Text("Beginn").bold()
                        
                        ForEach(recipeFB.instructions.sorted(by: { $0.step < $1.step })) { i in
                            
                            let step = Rational.decimalPlace(i.step, 10)
                            
                            Text(step)
                            Text(i.instruction)
                            Text(Rational.displayHoursMinutes(i.duration))
                            
                            //                        TextField(Rational.displayHoursMinutes(i.duration), text: $duration)
                            //                        let cleanedDuration = duration.trimmingCharacters(in: .whitespacesAndNewlines)
                            //                        if Int(cleanedDuration) > 0 { i.duration = Int(cleanedDuration) }
                            
                            if dateTimeStartSelection == 0 {
                                let date = manager.setNotification(recipeFB.id ?? "", i.instruction, step, i.startTime ?? 0, dateTime, false)
                                Text(dateCalculation.calculateDateTime(dT: date))
                            }
                            else {
                                let date = manager.setNotification(recipeFB.id ?? "", i.instruction, step, -recipeFB.prepTime + (i.startTime ?? 0), dateTime, false)
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
                    .padding(.leading)
                    
                    Divider()
                    
                    HStack {
                        Button(" Mitteilungen senden ") {
                            
                            var bakeStartTime = 0
                            
                            for i in 0..<recipeFB.instructions.count {
                                let _ = manager.setNotification(recipeFB.id ?? "",
                                                                   recipeFB.instructions[i].instruction,
                                                                   Rational.decimalPlace(recipeFB.instructions[i].step, 10),
                                                                   recipeFB.instructions[i].startTime ?? 0, dateTime, true)
                                
                                // If last step (assuming it is the start for baking) then calculate startTime of baking minus time to heat the oven and set a notification
                                if i == recipeFB.instructions.count - 1 {
                                    
                                    bakeStartTime = (recipeFB.instructions[i].startTime ?? 0) - GlobalVariables.vorheizZeit
                                }
                            }
                            showingNotificationMessage = true
                            
                            let _ = manager.setNotification(recipeFB.id ?? "", "Backofen anstellen", "99", bakeStartTime, dateTime, true)
                            
                        }.padding()
                            .foregroundColor(.gray)
                            .buttonStyle(.bordered)
                        //                        .alert("Benachrichtigungen eingerichtet", isPresented: $showingNotificationMessage) { Button("OK") { } }
                        
                        //                    Button(" Dauer anpassen ") {
                        //                        for i in 0..<recipeFB.instructions.count {
                        //                            let inst = recipeFB.instructions[i]
                        //                            instructions.append(inst)
                        //                        }
                        //                        changeDurationsView(instructions: $instructions)
                        //                        if instructions.count > 0 {
                        //                            for i in 0..<instructions.count {
                        //                                let inst = recipeFB.instructions[i]
                        //                                recipeFB.instructions[i] = instructions[i]
                        //                            }
                        //                        }
                        //                    }
                    }
                }.padding()
            }
        }
    }
    
    func setGlobaldateTime(_ date: Date) {
        GlobalVariables.dateTimePicker = date
    }
}

//struct InstructionsFBView_Previews: PreviewProvider {
//    static var previews: some View {
//        InstructionsFBView()
//    }
//}
