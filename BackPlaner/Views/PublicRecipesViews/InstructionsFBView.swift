//
//  InstructionsFBView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 24.11.21.
//

import SwiftUI
import CoreData

struct InstructionsFBView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.locale) private var locale
    @EnvironmentObject var modelFB:      RecipeFBModel
    @EnvironmentObject var model:        RecipeModel
    
    var recipeFB: RecipeFB
    var recipeId: NSManagedObjectID?
    var languageCode = ""
    
    @State private var dateTime = GlobalVariables.dateTimePicker
    @State private var dateTimeStartSelection     = 0
    @State var         selectedServingSize        = AppSettings.storedServingSize
    @State private var showingNotificationMessage = false
    @State private var changeDurationsFlag        = false
    @State private var showingAlert               = false
    // Summary shown after reminders are scheduled, so the action is no longer opaque.
    @State private var reminderCount              = 0
    @State private var reminderOvenOnText         = ""
    @State private var reminderFinishText         = ""

    var startDates = [Double:Date]()

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>
    
    @State private var oldName       = ""
    @State private var ingredientsFB = [IngredientFB]()
    @State private var index         = -1

    @State private var durations = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]

    // Narrow the step ("S."), duration and start columns so the description column stays as wide as possible.
    var gridItemLayoutInstructions = [GridItem(.fixed(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(.fixed(60), alignment: .trailing), GridItem(.fixed(90), alignment: .trailing)]

    let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents = DateComponents(year: GlobalVariables.year! + 1, month: GlobalVariables.month, day: GlobalVariables.day)
        return calendar.date(from:startComponents)!
        ...
        calendar.date(from:endComponents)!
    }()
    
    var manager:LocalNotificationManager = LocalNotificationManager()
    
    var body: some View {
        
        GeometryReader { fullView in
            
            ScrollView(.vertical, showsIndicators: false) {
                
                VStack (alignment: .leading) {
                    
                    PortraitAdaptiveStack(spacing: 12) {
                        NavigationLink(
                            destination: ShowBigImageView(image: (GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()).jpegData(compressionQuality: 1.0) ?? Data() )
                        ) {
                            Image(uiImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                                .cornerRadius(5)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(recipeFB.name)
                                .font(Theme.brandFont(18))
                                .foregroundColor(Theme.title)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            IconActionButton(systemImage: "square.and.arrow.down", style: .primary, accessibilityLabel: "Als eigenes Rezept speichern", title: "Als eigenes Rezept speichern", controlSize: .regular) {
                                _ = model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipeFB, context: viewContext, recipeImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    
                    Group {
                        PortraitAdaptiveStack(spacing: 12) {
                            // MARK: Serving size picker
                            PortraitAdaptiveStack(spacing: 6) {
                                Text("Portionsgröße")
                                    .font(Theme.bodyFont(15))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Picker("", selection: $selectedServingSize) {
                                    Text(0.5, format: .number.precision(.fractionLength(1))).tag(1)
                                    Text(1.0, format: .number.precision(.fractionLength(1))).tag(2)
                                    Text(1.5, format: .number.precision(.fractionLength(1))).tag(3)
                                    Text(2.0, format: .number.precision(.fractionLength(1))).tag(4)
                                }
                                .font(Theme.bodyFont(15))
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(width:160)
                            }
                            
                            Text("Gewicht: \(Int((recipeFB.totalWeight) * Double(selectedServingSize) / 2.0), format: .number) g")
                                .font(Theme.bodyFont(15))
                            
                            // MARK: Url-Link
                            if let url = URL(string: recipeFB.urlLink) {
                                Link("Link zum Rezept", destination: url)
                                    .padding(.top, 2)
                                    .font(Theme.brandFont(15))
                            }
                        }
                    }
                    
                    TotalIngredientsView(
                        ingredients: recipeFB.components.flatMap(\.ingredients).map {
                            TotalIngredientData(
                                name: $0.name,
                                unit: $0.unit,
                                weight: $0.weight,
                                numerator: $0.num,
                                denominator: $0.denom
                            )
                        },
                        componentNames: recipeFB.components.map(\.name),
                        selectedServingSize: selectedServingSize
                    )

                    // MARK: Components
                    VStack(alignment: .leading) {
                            Text("Komponenten:")
                                .font(Theme.brandFont(16))
                                .foregroundColor(Theme.title)
                                .padding([.bottom, .top], 5)
                            
                            LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {
                                
                                ForEach (recipeFB.components.sorted(by: { $0.number < $1.number })) { item in
                                    
                                    VStack(alignment: .leading) {
                                        Text(item.name)
                                            .font(Theme.brandFont(16))
                                            .padding([.bottom, .top], 5)
                                        
                                        VStack(alignment: .leading) {
                                            ForEach (item.ingredients.sorted(by: { $0.number < $1.number })) { ingred in
                                                
                                                let t = "• " + Rational.getPortion(unit:ingred.unit, weight:ingred.weight, num:ingred.num, denom:ingred.denom, targetServings: selectedServingSize)
                                                Text(t + ingred.name)
                                                    .font(Theme.bodyFont(15))
                                            }
                                        }
                                    }
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    
                    // MARK: Selections
                    InstructionSchedulingControlsView(
                        changeDurations: $changeDurationsFlag,
                        startSelection: $dateTimeStartSelection,
                        dateTime: $dateTime,
                        dateRange: dateRange,
                        onDateTapped: showNotificationMessage,
                        onDateChanged: setGlobalDateTime
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    
                    // MARK: Instructions
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Verarbeitungsschritte:")
                                .font(Theme.brandFont(16))
                                .foregroundColor(Theme.title)
                                .padding([.bottom, .top], 5)
                            
                            Spacer()
                            
                            Text("Bearbeitungsdauer: " + Rational.displayHoursMinutes(recipeFB.prepTime))
                                .font(Theme.bodyFont(16))
                                .padding([.trailing], 5)
                        }
                        
                        LazyVGrid(columns: gridItemLayoutInstructions, spacing: 6) {
                            Text("S.").bold()
                            Text("Beschreibung").bold()
                            Text("Dauer").bold()
                            
                            if changeDurationsFlag {
                                
                                Text("Dauer [Min]").bold()
                                
                                ForEach(recipeFB.instructions.indices, id: \.self) { index in

                                    // Guard against a mismatch between the (mutating) instructions array
                                    // and the fixed-size durations array to avoid an index-out-of-range crash
                                    if index < durations.count {

                                        let step = Rational.decimalPlace(recipeFB.instructions[index].step, 10)

                                        Text(step)
                                        Text(recipeFB.instructions[index].instruction)
                                        Text(Rational.displayHoursMinutes(recipeFB.instructions[index].duration))
                                        TextField(String(recipeFB.instructions[index].duration), text: $durations[index])
                                    }
                                }
                                .font(Theme.bodyFont(15))
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
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                    else {
                                        let date = manager.setNotification(recipeFB.id ?? "", i.instruction, step, (i.startTime ?? 0) - recipeFB.prepTime, dateTime, false)
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                }
                                .font(Theme.bodyFont(15))
                                
                                Group {
                                    Text("99")
                                    Text("Fertig")
                                    Text("")
                                    if dateTimeStartSelection == 0 {
                                        let date = Calendar.current.date(byAdding: .minute, value: recipeFB.prepTime, to: dateTime) ?? dateTime
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                    else {
                                        StackedDateTime(date: dateTime, alignment: .trailing)
                                    }
                                }
                                .font(Theme.bodyFont(15))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    
                    // MARK: Reminder setzen
                    HStack {
                        
                        IconActionButton(systemImage: "bell.badge", style: .primary, accessibilityLabel: "Reminder setzen", title: "Reminder setzen", controlSize: .regular) {
                            
                            // Reminders are set whenever the button is pressed
                                let originalStepCount = recipeFB.instructions.count

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
                                        
                                        if dateTimeStartSelection == 0 {

                                            bakeStartTime = (recipeFB.instructions[i].startTime ?? 0) - GlobalVariables.preheatTime
                                        }
                                        else {
                                            bakeStartTime = (recipeFB.instructions[i].startTime ?? 0) - GlobalVariables.preheatTime - recipeFB.prepTime
                                        }
                                    }
                                }
                                showingNotificationMessage = true

                                let activeLanguageCode = languageCode.isEmpty ? locale.identifier : languageCode
                                let generatedStepTexts = AppSettings.generatedStepTexts(languageCode: activeLanguageCode)
                                let startHeatingText = generatedStepTexts.startHeating
                                let bakeEndText = generatedStepTexts.bakeEnd
                                
                                // MARK: Step und Notification für das Einschalten des Backofens einstellen
                                let i          = InstructionFB()
                                i.id           = UUID().uuidString
                                i.instruction  = startHeatingText
                                // Berechnung der Step-Nummer
                                for index in 0..<recipeFB.instructions.count {
                                    
                                    if bakeStartTime < recipeFB.instructions[index].startTime ?? 0 {
                                        
                                        i.step = recipeFB.instructions[index].step - 0.1
                                    }
                                }

                                // Notification einstellen
                                let ovenOnDate = manager.setNotification(recipeFB.id ?? "", startHeatingText, String(i.step), bakeStartTime, dateTime, true)
                                if dateTimeStartSelection == 0 {
                                    i.startTime   = bakeStartTime
                                }
                                else {
                                    i.startTime   = bakeStartTime + recipeFB.prepTime
                                }
                                i.duration    = GlobalVariables.preheatTime
                                recipeFB.instructions.append(i)
                                
                                let i2 = InstructionFB()
                                var finishDate = dateTime
                                if dateTimeStartSelection == 0 {

                                    finishDate = manager.setNotification(recipeFB.id ?? "", bakeEndText, "99", recipeFB.prepTime, dateTime, true)
                                }
                                else {
                                    finishDate = manager.setNotification(recipeFB.id ?? "", bakeEndText, "99", 0, dateTime, true)
                                }
                                i2.id          = UUID().uuidString
                                i2.instruction = bakeEndText
                                i2.step        = 99
                                i2.startTime   = recipeFB.prepTime
                                i2.duration    = 0
                                recipeFB.instructions.append(i2)
                                
                                if dateTimeStartSelection == 0 {
                                    uploadNextSteps(recipeFB: recipeFB, date: dateTime)
                                }
                                else {
                                    dateTime = Calendar.current.date(byAdding: .minute, value: -recipeFB.prepTime, to: dateTime) ?? dateTime
                                    uploadNextSteps(recipeFB: recipeFB, date: dateTime)
                                }
                                
                                if let ix = recipeFB.instructions.firstIndex(where: { $0.instruction == startHeatingText }) {
                                    recipeFB.instructions.remove(at: ix)
                                }
                                if let i2x = recipeFB.instructions.firstIndex(where: { $0.instruction == bakeEndText }) {
                                    recipeFB.instructions.remove(at: i2x)
                                }
                                
                                let bakeHistoryFB     = BakeHistoryFB()
                                bakeHistoryFB.date    = dateTime
                                bakeHistoryFB.comment = "<kein Kommentar erfasst>"
                                bakeHistoryFB.images  = [GlobalVariables.noImage]
                                recipeFB.bakeHistories.append(bakeHistoryFB)
                                
                                recipeFB.bakeHistoryFlag   = true

                                _ = model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipeFB, context: viewContext, recipeImage: UIImage())

                                // Build a human-readable summary of what was scheduled.
                                let timeFormatter  = TimeCalculation()
                                reminderCount      = originalStepCount + 2
                                reminderOvenOnText = timeFormatter.calculateTime(t: ovenOnDate)
                                reminderFinishText = timeFormatter.calculateTime(t: finishDate)
                                showingAlert       = true

                                showingNotificationMessage = false
                        }
                        .padding()
                        .alert("Reminder wurden gesetzt", isPresented: $showingAlert) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text("\(reminderCount) Erinnerungen gesetzt.\nBackofen anstellen um \(reminderOvenOnText) Uhr.\nFertig um \(reminderFinishText) Uhr.")
                        }

                        if changeDurationsFlag {
                            
                            IconActionButton(systemImage: "checkmark", style: .primary, accessibilityLabel: "Dauer übernehmen", title: "Dauer übernehmen", controlSize: .regular) {
                                
                                for i in 0..<min(recipeFB.instructions.count, durations.count) {

                                    let cleanedDuration = durations[i].trimmingCharacters(in: .whitespacesAndNewlines)
                                    if Int(cleanedDuration) ?? 0 > 0 { recipeFB.instructions[i].duration = Int(cleanedDuration) ?? 0}
                                }
                                recipeFB.instructions = Rational.calculateStartTimes(recipeFB.instructions, dateTime)
                                
                                if let lastInstruction = recipeFB.instructions.last {
                                    recipeFB.prepTime = (lastInstruction.startTime ?? 0) + lastInstruction.duration
                                }
                                
                                changeDurationsFlag = false
                            }
                            .padding()
                        }
                    }
                }.padding()
            }
            .warmBackground()
            .navigationTitle(recipeFB.name)
        }
    }
    
    func uploadNextSteps(recipeFB: RecipeFB, date: Date) {

        // Same as in InstructionsView: reminders are replaced per recipe and
        // step, so the previous plan's steps have to go as well instead of
        // piling up next to the new ones.
        removeNextSteps(recipeName: recipeFB.name)

        for iFB in recipeFB.instructions {
            
            let n = NextStep(context: viewContext)
            
            n.id          = UUID()
            n.recipeName  = recipeFB.name
            n.instruction = iFB.instruction
            n.step        = iFB.step
            n.duration    = iFB.duration
            n.startTime   = iFB.startTime ?? 0
            n.date = Calendar.current.date(byAdding: .minute, value: iFB.startTime ?? 0, to: date) ?? date
            
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
    
    /// Deletes the scheduled steps of an earlier plan for the same recipe.
    /// Steps reference their recipe by name, as everywhere else in the app.
    func removeNextSteps(recipeName: String) {

        let request = NextStep.fetchRequest()
        request.predicate = NSPredicate(format: "recipeName == %@", recipeName)

        guard let previousSteps = try? viewContext.fetch(request) else { return }

        for step in previousSteps {
            viewContext.delete(step)
        }
    }

    func showNotificationMessage() {
        showingNotificationMessage = true
    }
    
    func setGlobalDateTime(_ date: Date) {
        GlobalVariables.dateTimePicker = date
    }
}
