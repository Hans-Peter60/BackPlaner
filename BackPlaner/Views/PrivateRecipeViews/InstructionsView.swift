//
//  InstructionsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 08.12.21.
//

import SwiftUI
import CoreData

struct InstructionsView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.locale) private var locale
    
    @EnvironmentObject var model: RecipeModel
   
    var recipe: Recipe
    
    @State private var dateTime                   = GlobalVariables.dateTimePicker
    @State private var dateTimeStartSelection     = 0
    @State private var endDate                    = Date()
    @State var         selectedServingSize        = AppSettings.storedServingSize
    @State private var showingNotificationMessage = false
    @State private var changeDurationsFlag        = false
    @State private var showingAlert               = false
    // Summary shown after reminders are scheduled, so the action is no longer opaque.
    @State private var reminderCount              = 0
    @State private var reminderOvenOnText         = ""
    @State private var reminderFinishText         = ""
    @State private var instructions = [Instruction]()
    // Findings of the bake-plan check (day window, overlapping bakes, bake pause).
    @State private var planIssues                 = [BakePlanIssue]()
    @State private var showingPlanError           = false
    @State private var planErrorMessage           = ""
    @State private var reminderHintText           = ""
    
    @State private var durations = ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]

    // Narrow the step ("S."), duration and start columns so the description column stays as wide as possible.
    var gridItemLayoutInstructions = [GridItem(scaledColumnSize(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(60), alignment: .trailing), GridItem(scaledColumnSize(90), alignment: .trailing)]
    var gridItemLayoutHistories = [GridItem(scaledColumnSize(60), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading)]
    
    let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents = DateComponents(year: GlobalVariables.year! + 1, month: GlobalVariables.month, day: GlobalVariables.day)
        return calendar.date(from:startComponents)!
        ...
        calendar.date(from:endComponents)!
    }()
    
    var manager:LocalNotificationManager = LocalNotificationManager()
    var dateFormat:DateFormat            = DateFormat()
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)])
    private var ingredients: FetchedResults<Ingredient>
    
    var body: some View {
        
        ScrollView(.vertical, showsIndicators: false) {

            VStack (alignment: .leading) {

                PortraitAdaptiveStack(spacing: 12) {
                    NavigationLink(
                        destination: ShowBigImageView(image: recipe.image)
                    ) {
                        let image = UIImage(data: recipe.image) ?? UIImage()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                            .cornerRadius(5)
                    }
                    // The image is the link's only content, so without this the
                    // link would be announced with no name at all.
                    .accessibilityLabel("Rezeptbild vergrößern")

                    Text(recipe.name)
                        .font(Theme.brandFont(18))
                        .foregroundColor(Theme.title)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                PortraitAdaptiveStack(spacing: 12) {
                    // MARK: Serving size picker
                    PortraitAdaptiveStack(spacing: 6) {
                        Text("Portionsgröße")
                            .font(Theme.bodyFont(15))
                            // No lineLimit/fixedSize: at accessibility sizes a
                            // forced single line pushes the whole row off screen.
                            .fixedSize(horizontal: false, vertical: true)
                        ServingSizePicker(selection: $selectedServingSize)
                    }
                    
                    Text("Gewicht: \(scaledRecipeWeight) g")
                            .font(Theme.bodyFont(15))
                    
                    // MARK: Url-Link
                    Link("Link zum Rezept",
                         destination: URL(string: (recipe.urlLink ?? "")) ?? URL(string: "https://")!)
                        .padding(.top, 2)
                        .font(Theme.brandFont(15))
                }

                TotalIngredientsView(
                    ingredients: recipe.componentsArray.flatMap(\.ingredientsArray).map {
                        TotalIngredientData(
                            name: $0.name,
                            unit: $0.unit ?? "",
                            weight: $0.weight,
                            numerator: $0.num,
                            denominator: $0.denom
                        )
                    },
                    componentNames: recipe.componentsArray.map(\.name),
                    selectedServingSize: selectedServingSize
                )

                // MARK: Components
                ComponentColumnsView(components: ComponentColumn.columns(of: recipe.componentsArray),
                                     selectedServingSize: selectedServingSize)

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
                .onChange(of: dateTimeStartSelection) { _, _ in
                    refreshPlanIssues()
                }

                BakePlanIssuesView(issues: planIssues)


                // MARK: Instructions
                VStack(alignment: .leading) {
                    HStack {
                        Text("Verarbeitungsschritte:")
                            .font(Theme.brandFont(16))
                            .foregroundColor(Theme.title)
                            .padding([.bottom, .top], 5)
                        
                        Spacer()
                        
                        Text("Bearbeitungsdauer: " + Rational.displayHoursMinutes(recipe.prepTime))
                            .font(Theme.bodyFont(16))
                            .padding([.trailing], 5)
                    }
 
                    LazyVGrid(columns: gridItemLayoutInstructions, spacing: 6) {

                        Text("S.").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                        
                        Group {

                            // MARK: Change Durations
                            if changeDurationsFlag {

                                Text("Dauer [Min]").bold()

                                ForEach(recipe.instructionsArray.indices, id: \.self) { index in

                                    let step = Rational.decimalPlace(recipe.instructionsArray[index].step, 10)

                                    Text(step)
                                    Text(recipe.instructionsArray[index].instruction)
                                    Text(Rational.displayHoursMinutes(recipe.instructionsArray[index].duration))
                                    if index < durations.count {
                                        TextField(String(recipe.instructionsArray[index].duration), text: $durations[index])
                                            // The placeholder is the current number
                                            // of minutes, which says nothing on its
                                            // own when read aloud.
                                            .accessibilityLabel("Dauer in Minuten")
                                    }

                                }
                                .font(Theme.bodyFont(15))
                            }
                        
                            else {

                                Text("Beginn").bold()
                                
                                ForEach(recipe.instructionsArray.indices, id: \.self) { index in

                                    let step = Rational.decimalPlace(recipe.instructionsArray[index].step, 10)

                                    Text(step)
                                        .font(Theme.bodyFont(15))
                                    Text(recipe.instructionsArray[index].instruction)
                                        .font(Theme.bodyFont(15))
                                    Text(Rational.displayHoursMinutes(recipe.instructionsArray[index].duration))
                                        .font(Theme.bodyFont(15))

                                    if dateTimeStartSelection == 0 {
                                        let date = manager.setNotification(recipe.reminderId, recipe.instructionsArray[index].instruction, step, recipe.instructionsArray[index].startTime, dateTime, false)
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                    else {
                                        let date = manager.setNotification(recipe.reminderId, recipe.instructionsArray[index].instruction, step, recipe.instructionsArray[index].startTime - recipe.prepTime, dateTime, false)
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                }

                                // Guard against an empty instructions array (count - 1 would be out of range)
                                if let lastInstruction = recipe.instructionsArray.last {
                                    Text(String(Int(lastInstruction.step + 1)))
                                    Text("Fertig")
                                    Text(verbatim: "")
                                    if dateTimeStartSelection == 0 {
                                        let date = Calendar.current.date(byAdding: .minute, value: recipe.prepTime, to: dateTime) ?? dateTime
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                    else {
                                        StackedDateTime(date: dateTime, alignment: .trailing)
                                    }
                                }
                            }
                        }
                    }
                    .scrollsSidewaysAtLargeText()
                    .font(Theme.bodyFont(15))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
                
                // MARK: Histories
                
                VStack(alignment: .leading) {
                    
                    Text("Back-Kommentare")
                        .font(Theme.brandFont(16))
                        .foregroundColor(Theme.title)
                    
                    LazyVGrid(columns: gridItemLayoutHistories, spacing: 6) {
                        
                        Text("Dauer").bold()
                        Text("Kommentar").bold()
                        
                        ForEach(recipe.bakeHistoriesArray) { bakeHistory in

                            Text(dateFormat.calculateDate(dT: bakeHistory.date))
                            Text(bakeHistory.comment)
                        }
                    }
                    .scrollsSidewaysAtLargeText()

                }
                .font(Theme.bodyFont(15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // MARK: Reminder setzen
                HStack {
                    IconActionButton(systemImage: "bell.badge", style: .primary, accessibilityLabel: "Reminder setzen", title: "Reminder setzen", controlSize: .regular) {

                        // Check the plan before anything is generated. Overlapping
                        // bakes are an error and stop the scheduling; the remaining
                        // findings are hints and travel with the summary alert.
                            let issues = currentPlanIssues()
                            planIssues = issues

                            let planErrors = issues.filter { $0.severity == .error }
                            if !planErrors.isEmpty {
                                planErrorMessage = planErrors.map(\.message).joined(separator: "\n\n")
                                showingPlanError = true
                                return
                            }

                            reminderHintText = issues
                                .filter { $0.severity == .hint }
                                .map(\.message)
                                .joined(separator: "\n\n")

                        // Reminders are set whenever the button is pressed
                            let originalStepCount = recipe.instructionsArray.count

                            recipe.bakeHistoryFlag = true

                            var bakeStartTime = 0
                            let explicitPreheatInstruction = recipe.instructionsArray.first {
                                isExplicitPreheatInstruction($0.instruction)
                            }
                            let bakingInstructionIndex = recipe.instructionsArray.firstIndex {
                                isBakingStartInstruction($0.instruction)
                            } ?? max(recipe.instructionsArray.count - 1, 0)
                            let bakingInstructionText = recipe.instructionsArray.indices.contains(bakingInstructionIndex)
                                ? recipe.instructionsArray[bakingInstructionIndex].instruction
                                : ""
                            let preheatDuration = explicitPreheatInstruction == nil
                                ? effectivePreheatTime(for: bakingInstructionText)
                                : 0

                            // MARK: Notifications einsetzen
                            for i in 0..<recipe.instructionsArray.count {
                                
                                if dateTimeStartSelection == 0 {
                                    // Start
                                    let _ = manager.setNotification(recipe.reminderId,
                                                                    recipe.instructionsArray[i].instruction,
                                                                    Rational.decimalPlace(recipe.instructionsArray[i].step, 10),
                                                                    recipe.instructionsArray[i].startTime, dateTime, true)
                                }
                                else {
                                    // Ende
                                    let _ = manager.setNotification(recipe.reminderId,
                                                                    recipe.instructionsArray[i].instruction,
                                                                    Rational.decimalPlace(recipe.instructionsArray[i].step, 10),
                                                                    recipe.instructionsArray[i].startTime - recipe.prepTime, dateTime, true)
                                }

                                // Baking may have multiple phases (for example, covered and
                                // uncovered). The first actual oven step defines its start.
                                if i == bakingInstructionIndex {
                                    
                                    if dateTimeStartSelection == 0 {

                                        bakeStartTime = (recipe.instructionsArray[i].startTime) - preheatDuration
                                    }
                                    else {
                                        bakeStartTime = (recipe.instructionsArray[i].startTime) - preheatDuration - recipe.prepTime
                                    }
                                }
                            }
                            showingNotificationMessage = true

                            let generatedStepTexts = AppSettings.generatedStepTexts(languageCode: locale.identifier)
                            let startHeatingText = ovenStartText(
                                baseText: generatedStepTexts.startHeating,
                                bakingInstruction: bakingInstructionText
                            )
                            let bakeEndText = generatedStepTexts.bakeEnd

                            // MARK: Step und Notification für das Einschalten des Backofens einstellen
                            let generatedOvenInstruction: Instruction?
                            let ovenOnDate: Date
                            if let explicitPreheatInstruction {
                                generatedOvenInstruction = nil
                                let offset = dateTimeStartSelection == 0
                                    ? explicitPreheatInstruction.startTime
                                    : explicitPreheatInstruction.startTime - recipe.prepTime
                                ovenOnDate = Calendar.current.date(
                                    byAdding: .minute,
                                    value: offset,
                                    to: dateTime
                                ) ?? dateTime
                            } else {
                                let ovenInstruction = Instruction(context: viewContext)
                                ovenInstruction.id = UUID()
                                ovenInstruction.instruction = startHeatingText
                                for index in 0..<recipe.instructionsArray.count {
                                    if bakeStartTime < recipe.instructionsArray[index].startTime {
                                        ovenInstruction.step = recipe.instructionsArray[index].step - 0.1
                                    }
                                }

                                ovenOnDate = manager.setNotification(
                                    recipe.reminderId,
                                    startHeatingText,
                                    String(ovenInstruction.step),
                                    bakeStartTime,
                                    dateTime,
                                    true
                                )
                                ovenInstruction.startTime = dateTimeStartSelection == 0
                                    ? bakeStartTime
                                    : bakeStartTime + recipe.prepTime
                                ovenInstruction.duration = preheatDuration
                                generatedOvenInstruction = ovenInstruction
                            }

                            // MARK: Step und Notification für das Ende des Backens einstellen
                            let i2         = Instruction(context: viewContext)
                            i2.id          = UUID()
                            i2.instruction = bakeEndText
                            i2.step        = 99
                            i2.duration    = 0
                            
                            // The finish step always sits prepTime after the plan's
                            // start. uploadNextSteps moves the base date back by
                            // prepTime for "Fertig bis", so this single value gives
                            // the correct scheduled step in both modes. The reminder
                            // is relative to the unshifted date and therefore needs
                            // its own offset — using i2.startTime for both put the
                            // step prepTime minutes ahead of its own reminder.
                            i2.startTime = recipe.prepTime

                            let bakeEndOffset = dateTimeStartSelection == 0 ? recipe.prepTime : 0
                            endDate = manager.setNotification(recipe.reminderId, bakeEndText, "99", bakeEndOffset, dateTime, true)

                            if let generatedOvenInstruction {
                                recipe.addToInstructions(generatedOvenInstruction)
                            }
                            recipe.addToInstructions(i2)

                            // Save to core data
                            viewContext.performAndWait {
                                
                                try? viewContext.save()
                            }

                            // MARK: NextSteps sichern
                            // planBaseDate already moves "Fertig bis" back by
                            // prepTime, so the picker keeps showing the date the
                            // user chose and the plan check stays in sync with it.
                            uploadNextSteps(recipe: recipe, date: planBaseDate)

                            // MARK: BakeHistory sichern
                            let bakeHistory     = BakeHistory(context: viewContext)
                            bakeHistory.date    = endDate
                            bakeHistory.comment = AppSettings.generatedRecipeTexts().missingComment
                            
                            recipe.addToBakeHistories(bakeHistory)

                            // Save to core data
                            viewContext.performAndWait {
                                
                                try? viewContext.save()
                            }

                            if let generatedOvenInstruction {
                                viewContext.delete(generatedOvenInstruction)
                            }
                            viewContext.delete(i2)
                            try? viewContext.save()

                            // Build a human-readable summary of what was scheduled.
                            let timeFormatter  = TimeCalculation()
                            reminderCount = originalStepCount
                                + (generatedOvenInstruction == nil ? 1 : 2)
                            reminderOvenOnText = timeFormatter.calculateTime(t: ovenOnDate)
                            reminderFinishText = timeFormatter.calculateTime(t: endDate)
                            showingAlert       = true

                            showingNotificationMessage = false
                    }
                    .padding()
                    .alert("Reminder wurden gesetzt", isPresented: $showingAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        if reminderHintText.isEmpty {
                            Text("\(reminderCount) Erinnerungen gesetzt.\nBackofen anstellen um \(reminderOvenOnText) Uhr.\nFertig um \(reminderFinishText) Uhr.")
                        }
                        else {
                            Text("\(reminderCount) Erinnerungen gesetzt.\nBackofen anstellen um \(reminderOvenOnText) Uhr.\nFertig um \(reminderFinishText) Uhr.\n\n\(reminderHintText)")
                        }
                    }
                    .alert("Backzeiten überschneiden sich", isPresented: $showingPlanError) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(planErrorMessage)
                    }

                    // MARK: Change Duration Flag bearbeiten
                    if changeDurationsFlag {

                        IconActionButton(systemImage: "checkmark", style: .primary, accessibilityLabel: "Dauer übernehmen", title: "Dauer übernehmen", controlSize: .regular) {

                            var instructionsFB = [InstructionFB]()
                            
                            for i in 0..<recipe.instructionsArray.count {

                                let cleanedDuration = (i < durations.count ? durations[i] : "").trimmingCharacters(in: .whitespacesAndNewlines)
                                if Int(cleanedDuration) ?? 0 > 0 { recipe.instructionsArray[i].duration = Int(cleanedDuration) ?? 0}
                                
                                let instruction = InstructionFB()
                                instruction.instruction = recipe.instructionsArray[i].instruction
                                instruction.step        = recipe.instructionsArray[i].step
                                instruction.startTime   = recipe.instructionsArray[i].startTime
                                instruction.duration    = recipe.instructionsArray[i].duration
                                instruction.componentName = recipe.instructionsArray[i].componentName
                                instructionsFB.append(instruction)

                            }
                            instructionsFB = Rational.calculateStartTimes(
                                instructionsFB,
                                dateTime,
                                dependencies: Rational.ComponentDependency.from(recipe.componentsArray)
                            )
                            
                            for i in 0..<recipe.instructionsArray.count {
                                recipe.instructionsArray[i].instruction = instructionsFB[i].instruction
                                recipe.instructionsArray[i].step        = instructionsFB[i].step
                                recipe.instructionsArray[i].startTime   = instructionsFB[i].startTime ?? 0
                                recipe.instructionsArray[i].duration    = instructionsFB[i].duration
                            }
                            if let last = recipe.instructionsArray.last {
                                recipe.prepTime = last.startTime + last.duration
                            }
                            
                            changeDurationsFlag = false
                            try? viewContext.save()
                            refreshPlanIssues()
                        }
                        .padding()
                    }
                }
            }.padding()
        }
        .warmBackground()
        .navigationTitle("Backanleitung für " + recipe.name)
        .onAppear {
            refreshPlanIssues()
        }
    }

    private var scaledRecipeWeight: Int {
        Int(recipe.totalWeight * Double(selectedServingSize) / 2.0)
    }

    // MARK: - Backplanung prüfen

    /// The plan's base date. The picker holds the start in "Starten ab" mode and
    /// the finish in "Fertig bis" mode, where the plan starts `prepTime` earlier.
    private var planBaseDate: Date {
        dateTimeStartSelection == 0
            ? dateTime
            : Calendar.current.date(byAdding: .minute, value: -recipe.prepTime, to: dateTime) ?? dateTime
    }

    /// Every step the reminder button would generate, including the two steps the
    /// app adds itself: switching the oven on and the end of the bake.
    private func plannedSteps() -> [PlannedStep] {

        let calendar     = Calendar.current
        let base         = planBaseDate
        let instructions = recipe.instructionsArray

        var steps = instructions.map { instruction in
            PlannedStep(
                instruction: instruction.instruction,
                step: instruction.step,
                date: calendar.date(byAdding: .minute, value: instruction.startTime, to: base) ?? base
            )
        }

        guard let bakingInstruction = instructions.first(where: {
            isBakingStartInstruction($0.instruction)
        }) ?? instructions.last else { return steps }

        let generatedStepTexts = AppSettings.generatedStepTexts(languageCode: locale.identifier)

        let hasExplicitPreheatStep = instructions.contains {
            isExplicitPreheatInstruction($0.instruction)
        }
        if !hasExplicitPreheatStep {
            steps.append(
                PlannedStep(
                    instruction: ovenStartText(
                        baseText: generatedStepTexts.startHeating,
                        bakingInstruction: bakingInstruction.instruction
                    ),
                    step: bakingInstruction.step - 0.1,
                    date: calendar.date(
                        byAdding: .minute,
                        value: bakingInstruction.startTime
                            - effectivePreheatTime(for: bakingInstruction.instruction),
                        to: base
                    ) ?? base
                )
            )
        }

        steps.append(
            PlannedStep(
                instruction: generatedStepTexts.bakeEnd,
                step: 99,
                date: calendar.date(byAdding: .minute, value: recipe.prepTime, to: base) ?? base
            )
        )

        return steps
    }

    /// The oven phase of the plan: the last processing step puts the dough into
    /// the oven, the plan ends when baking is finished.
    private func plannedBakeWindow() -> BakeWindow? {

        guard let bakingInstruction = recipe.instructionsArray.first(where: {
            isBakingStartInstruction($0.instruction)
        }) ?? recipe.instructionsArray.last else { return nil }

        let calendar = Calendar.current
        let base     = planBaseDate

        guard let start = calendar.date(byAdding: .minute, value: bakingInstruction.startTime, to: base),
              let end   = calendar.date(byAdding: .minute, value: recipe.prepTime, to: base),
              end >= start else {
            return nil
        }

        return BakeWindow(recipeName: recipe.name, start: start, end: end)
    }

    // Both live in BakePlanValidator, so the plan check and the reminders agree
    // on which step puts the dough into the oven.
    private func isExplicitPreheatInstruction(_ instruction: String) -> Bool {
        BakePlanValidator.isPreheatInstruction(instruction)
    }

    private func isBakingStartInstruction(_ instruction: String) -> Bool {
        BakePlanValidator.isBakingStartInstruction(instruction)
    }

    private func ovenStartText(
        baseText: String,
        bakingInstruction: String
    ) -> String {
        // "at" covers the English baking step the import writes; without it the
        // preheating reminder would name no temperature at all in English.
        let pattern = #"(?:bei|auf|at|à|a)\s+(\d{2,3})\s*(?:°\s*C|Grad)?"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ),
        let match = expression.firstMatch(
            in: bakingInstruction,
            range: NSRange(bakingInstruction.startIndex..., in: bakingInstruction)
        ),
        let temperatureRange = Range(match.range(at: 1), in: bakingInstruction) else {
            return baseText
        }

        return "\(baseText) (\(bakingInstruction[temperatureRange]) °C)"
    }

    private func effectivePreheatTime(for bakingInstruction: String) -> Int {
        let text = bakingInstruction.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "de_DE")
        )
        let coldOvenPhrases = [
            "kalten backofen", "kalten ofen", "nicht vorheizen",
            "ohne vorheizen", "ohne vorzuheizen"
        ]
        return coldOvenPhrases.contains(where: text.contains)
            ? 0
            : GlobalVariables.preheatTime
    }

    private func currentPlanIssues() -> [BakePlanIssue] {
        BakePlanValidator.issues(
            for: plannedSteps(),
            bakeWindow: plannedBakeWindow(),
            existingWindows: BakePlanValidator.scheduledBakeWindows(
                excluding: recipe.name,
                in: viewContext
            )
        )
    }

    private func refreshPlanIssues() {
        planIssues = currentPlanIssues()
    }


    // MARK: uploadNextSteps
    func uploadNextSteps(recipe: Recipe, date: Date) {

        // A recipe has one plan at a time: its reminders share the identifier
        // "Recipe-<recipe>-<step>", so iOS replaces them when the recipe is
        // planned again. Drop the previous plan's steps as well — otherwise the
        // list would show the old and the new schedule side by side while only
        // the new reminders exist.
        removeNextSteps(recipeName: recipe.name)

        for i in recipe.instructionsArray {

            let n = NextStep(context: viewContext)

            n.id          = UUID()
            n.recipeName  = recipe.name
            n.instruction = i.instruction
            n.step        = i.step
            n.duration    = i.duration
            n.startTime   = i.startTime
            n.date = Calendar.current.date(byAdding: .minute, value: i.startTime, to: date) ?? date

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

    func setGlobalDateTime(_ date: Date) {

        GlobalVariables.dateTimePicker = date
        refreshPlanIssues()
    }

    func showNotificationMessage() {
        showingNotificationMessage = true
    }
}

// MARK: CheckBoxStyle
struct CheckboxStyle: ToggleStyle {

    func makeBody(configuration: Self.Configuration) -> some View {

        return HStack {

            configuration.label

            Spacer()

            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .resizable()
                .frame(width: 24, height: 24)
                // The tick carries the step's state on its own, so it is a
                // control and not decoration. System .gray managed 3.3:1 on a
                // white card — just over the 3:1 line, and off the app's
                // palette besides, which made the purple read as a leftover.
                .foregroundColor(configuration.isOn ? Theme.accentText : Theme.subtitle)
                .font(.system(size: 20, weight: .bold, design: .default))
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
        // The tick is drawn by hand and toggled with a tap gesture, so it has
        // none of the semantics a real Toggle would have. Expose the whole row
        // as one switch: the step text names it, the tick is its value, and the
        // action lets VoiceOver activate it without aiming at the icon.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        // Distinct keys on purpose: the bare "Erledigt" key is already the title
        // of the notification action ("Mark as Done"), which is an instruction,
        // not a state.
        .accessibilityValue(configuration.isOn ? "Schritt erledigt" : "Schritt offen")
        .accessibilityAction {
            configuration.isOn.toggle()
        }
    }
}
