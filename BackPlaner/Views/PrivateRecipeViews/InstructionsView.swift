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
    @State var         selectedServingSize        = AppSettings.storedServingSize
    /// A target dough weight in grams; overrides the serving-size factor.
    @State private var targetWeight: Int?
    @State private var showingNotificationMessage = false
    @State private var changeDurationsFlag        = false
    @State private var showingAlert               = false
    // Summary shown after reminders are scheduled, so the action is no longer opaque.
    @State private var reminderCount              = 0
    @State private var reminderOvenOnText         = ""
    @State private var reminderOvenTemperature    = ""
    @State private var reminderFinishText         = ""
    @State private var instructions = [Instruction]()
    /// Asks whether a new plan replaces the recipe's existing one or joins it.
    @State private var showingPlanChoice = false

    /// Whether the recipe already has planned steps.
    private var hasExistingPlan: Bool {
        BakePlanScheduler.hasPlan(recipeName: recipe.name, in: viewContext)
    }

    /// 1.0 is the recipe as stored.
    private var servingScale: Double {
        ServingScale.factor(servingSize: selectedServingSize, targetWeight: targetWeight, baseWeight: recipe.totalWeight)
    }
    // Findings of the bake-plan check (day window, overlapping bakes, bake pause).
    @State private var planIssues                 = [BakePlanIssue]()
    // Dates at which no step falls into the night (BakePlanAdvisor).
    @State private var planHasNightSteps          = false
    @State private var nightFreeDates             = [NightFreeDate]()
    @State private var showingPlanError           = false
    @State private var planErrorMessage           = ""
    @State private var reminderHintText           = ""
    
    @State private var durations: [String] = []

    // Narrow the step ("S."), duration and start columns so the description column stays as wide as possible.
    var gridItemLayoutInstructions = [GridItem(scaledColumnSize(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(60), alignment: .trailing), GridItem(scaledColumnSize(90), alignment: .trailing)]

    let dateRange: ClosedRange<Date> = GlobalVariables.planningDateRange()
    
    var manager:LocalNotificationManager = LocalNotificationManager()
    var dateFormat:DateFormat            = DateFormat()

    /// The minutes typed into the duration field of step `index`. The list
    /// grows with the first entry into a field instead of having a fixed
    /// length: at 24 (own recipes) and 34 (public ones) entries, longer
    /// recipes lost their duration fields, and the public screen hid every
    /// step after the 34th.
    private func durationBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < durations.count ? durations[index] : "" },
            set: { value in
                if durations.count <= index {
                    durations.append(contentsOf: Array(repeating: "", count: index - durations.count + 1))
                }
                durations[index] = value
            }
        )
    }
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)])
    private var ingredients: FetchedResults<Ingredient>
    
    var body: some View {

        // Reads the width available so the content below can be pinned to it —
        // see InstructionsFBView for why a vertical ScrollView otherwise grows
        // past both screen edges at the large text sizes.
        GeometryReader { fullView in

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
                
                // MARK: Serving size or target dough weight
                ServingScaleControl(selectedServingSize: $selectedServingSize,
                                    targetWeight: $targetWeight,
                                    baseWeight: recipe.totalWeight)

                PortraitAdaptiveStack(spacing: 12) {
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
                    scale: servingScale
                )

                // MARK: Components
                ComponentColumnsView(components: ComponentColumn.columns(of: recipe.componentsArray),
                                     scale: servingScale)

                // MARK: Last time
                // How the last bake of this recipe went, right where the
                // next one is planned. Only a bake that already happened:
                // setting reminders creates an entry dated at the planned
                // end, which has nothing to say yet.
                if let lastBake = recipe.lastCompletedBakeHistory() {
                    LastBakeCardView(bakeHistory: lastBake, recipeName: recipe.name)
                }

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

                BakePlanIssuesView(issues: planIssues,
                                   hasNightSteps: planHasNightSteps,
                                   suggestions: nightFreeDates,
                                   anchor: PlanAnchor(selection: dateTimeStartSelection),
                                   onApply: { dateTime = $0 })


                // MARK: Instructions
                VStack(alignment: .leading) {
                    HStack {
                        Text("Verarbeitungsschritte:")
                            .font(Theme.brandFont(16))
                            .foregroundColor(Theme.title)
                            .padding([.bottom, .top], 5)
                        
                        Spacer()
                        
                        Text("Bearbeitungsdauer: \(Rational.displayHoursMinutes(recipe.prepTime))")
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
                                    TextField(String(recipe.instructionsArray[index].duration), text: durationBinding(index))
                                        // The placeholder is the current number
                                        // of minutes, which says nothing on its
                                        // own when read aloud.
                                        .accessibilityLabel("Dauer in Minuten")

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

                // Every bake of this recipe, newest first: the date, the
                // recorded facts in one line, and the comment. An entry still
                // ahead is the one just planned and is marked as such.
                if !recipe.bakeHistoriesArray.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {

                        Text("Bisherige Backvorgänge")
                            .font(Theme.brandFont(16))
                            .foregroundColor(Theme.title)

                        ForEach(recipe.bakeHistoriesArray) { bakeHistory in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(dateFormat.calculateDate(dT: bakeHistory.date))
                                        .font(Theme.brandFont(15))
                                        .foregroundColor(Theme.cardTitle)
                                    if bakeHistory.date > Date() {
                                        Text("geplant")
                                            .font(Theme.bodyFont(13))
                                            .foregroundColor(Theme.subtitle)
                                    }
                                }

                                BakeHistoryFactsLineView(facts: bakeHistory.facts)
                                    .font(Theme.bodyFont(14))
                                    .foregroundColor(Theme.subtitle)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !BakeHistoryFacts.isPlaceholderComment(bakeHistory.comment) {
                                    Text(bakeHistory.comment)
                                        .font(Theme.bodyFont(15))
                                        .foregroundColor(Theme.cardTitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if !bakeHistory.hasNotes && bakeHistory.date <= Date() {
                                    Text("Noch nichts notiert")
                                        .font(Theme.bodyFont(14))
                                        .foregroundColor(Theme.subtitle)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                // MARK: Reminder setzen
                HStack {
                    IconActionButton(systemImage: "bell.badge", style: .primary, accessibilityLabel: "Reminder setzen", title: "Reminder setzen", controlSize: .regular) {
                        if hasExistingPlan {
                            showingPlanChoice = true
                        } else {
                            scheduleReminders(replaceExisting: true)
                        }
                    }
                    .padding()
                    .confirmationDialog("Für dieses Rezept gibt es schon einen Plan", isPresented: $showingPlanChoice, titleVisibility: .visible) {
                        Button("Bestehenden Plan ersetzen", role: .destructive) {
                            scheduleReminders(replaceExisting: true)
                        }
                        Button("Zusätzlich planen") {
                            scheduleReminders(replaceExisting: false)
                        }
                        Button("Abbrechen", role: .cancel) { }
                    } message: {
                        Text("Du kannst den bestehenden Plan ersetzen oder beide behalten – etwa für zwei Backtage.")
                    }
                    .alert("Reminder wurden gesetzt", isPresented: $showingAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        ReminderSummary.text(count: reminderCount, ovenOn: reminderOvenOnText,
                                             temperature: reminderOvenTemperature,
                                             finish: reminderFinishText, hints: reminderHintText)
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
            }
            .padding()
            .frame(width: fullView.size.width, alignment: .leading)
        }
        .warmBackground()
        .navigationTitle("Backanleitung für " + recipe.name)
        .onAppear {
            refreshPlanIssues()
        }

        }
    }

    private var scaledRecipeWeight: Int {
        Int((recipe.totalWeight * servingScale).rounded())
    }

    // MARK: - Backplanung

    /// The plan for the date and mode chosen above. Worked out in BakePlan,
    /// which the baking view of public recipes shares.
    private var bakePlan: BakePlan {
        BakePlan(recipeName: recipe.name,
                 steps: recipe.instructionsArray.map {
                     PlanStep(instruction: $0.instruction, step: $0.step,
                              startTime: $0.startTime, duration: $0.duration)
                 },
                 prepTime: recipe.prepTime,
                 anchor: PlanAnchor(selection: dateTimeStartSelection),
                 date: dateTime,
                 languageCode: locale.identifier)
    }

    private func refreshPlanIssues() {
        let plan = bakePlan
        planIssues = plan.issues(in: viewContext)
        planHasNightSteps = BakePlanAdvisor.hasNightSteps(plan)
        nightFreeDates = planHasNightSteps ? BakePlanAdvisor.nightFreeDates(for: plan, in: viewContext) : []
    }

    /// Sets the reminders and the planned steps for the date chosen above.
    /// `replaceExisting` drops the recipe's earlier plans first; otherwise
    /// the new plan stands beside them — Saturday's and Sunday's loaf.
    private func scheduleReminders(replaceExisting: Bool) {
        // Check the plan before anything changes: overlapping bakes are an
        // error and stop the scheduling (and leave an existing plan alone);
        // the remaining findings are hints and travel with the summary.
        let plan = bakePlan
        let issues = plan.issues(in: viewContext)
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

        let planID = UUID()
        if replaceExisting {
            BakePlanScheduler.removePlans(recipeName: recipe.name, reminderPrefix: recipe.reminderId,
                                          keeping: planID, in: viewContext)
        }

        showingNotificationMessage = true
        recipe.bakeHistoryFlag = true

        // A step that mixes a component carries that component's
        // ingredients in its reminder, in the serving size chosen above.
        let instructions = recipe.instructionsArray
        let scheduler = BakePlanScheduler(plan: plan,
                                          reminderID: "\(recipe.reminderId)-\(planID.uuidString)",
                                          manager: manager)
        let result = scheduler.scheduleReminders { index in
            let instruction = instructions[index]
            return ScheduledStepComponent.column(for: recipe,
                                                 instruction: instruction,
                                                 instructionText: instruction.instruction)
                .flatMap { ScheduledStepComponent.ingredientsText(for: $0, scale: servingScale) }
        }
        scheduler.writeScheduledSteps(planID: planID, in: viewContext)

        // The bake history gets an entry for the end of this bake.
        let bakeHistory     = BakeHistory(context: viewContext)
        bakeHistory.date    = result.finishDate
        bakeHistory.comment = AppSettings.generatedRecipeTexts().missingComment
        recipe.addToBakeHistories(bakeHistory)
        viewContext.performAndWait {
            try? viewContext.save()
        }

        // A human-readable summary of what was scheduled.
        let timeFormatter  = TimeCalculation()
        reminderCount      = result.reminderCount
        reminderOvenOnText = timeFormatter.calculateTime(t: result.ovenOnDate)
        reminderOvenTemperature = result.ovenTemperature ?? ""
        reminderFinishText = timeFormatter.calculateTime(t: result.finishDate)
        showingAlert       = true

        showingNotificationMessage = false
    }

    func setGlobalDateTime(_ date: Date) {

        GlobalVariables.dateTimePicker = date
        refreshPlanIssues()
    }

    func showNotificationMessage() {
        showingNotificationMessage = true
    }
}

/// The message after reminders were set, shared by both baking views. A
/// function returning `Text` rather than a view: an alert shows nothing else.
enum ReminderSummary {
    static func text(count: Int, ovenOn: String, temperature: String,
                     finish: String, hints: String) -> Text {
        switch (temperature.isEmpty, hints.isEmpty) {
        case (true, true):
            return Text("\(count) Erinnerungen gesetzt.\nBackofen anstellen um \(ovenOn) Uhr.\nFertig um \(finish) Uhr.")
        case (true, false):
            return Text("\(count) Erinnerungen gesetzt.\nBackofen anstellen um \(ovenOn) Uhr.\nFertig um \(finish) Uhr.\n\n\(hints)")
        case (false, true):
            return Text("\(count) Erinnerungen gesetzt.\nBackofen anstellen um \(ovenOn) Uhr (\(temperature)).\nFertig um \(finish) Uhr.")
        case (false, false):
            return Text("\(count) Erinnerungen gesetzt.\nBackofen anstellen um \(ovenOn) Uhr (\(temperature)).\nFertig um \(finish) Uhr.\n\n\(hints)")
        }
    }
}
