//
//  InstructionsView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 08.12.21.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct InstructionsView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var model: RecipeModel

    /// Shown as a sheet over the recipe's page (RecipePageView): the date
    /// and mode, the plan's findings, the steps with their start times, and
    /// "Erinnerungen setzen". Picture, ingredients and the earlier bakes
    /// are on the page.
    var recipe: Recipe
    
    @State private var dateTime                   = GlobalVariables.dateTimePicker
    // 0 = "Starten ab", 1 = "Fertig bis"; the UI tests may ask for the latter.
    @State private var dateTimeStartSelection     = UITestSupport.plansToFinish ? 1 : 0
    /// Owned by RecipePageView and chosen on the page, so the plan's
    /// reminders carry the amounts shown there.
    @Binding var         selectedServingSize: Int
    /// A target dough weight in grams; overrides the serving-size factor.
    @Binding var         targetWeight: Int?
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

    /// The two halves of the step table's header row; see the ViewThatFits
    /// in body for how they are arranged.
    private var instructionsHeader: some View {
        Text("Verarbeitungsschritte")
            .font(Theme.brandFont(16))
            .foregroundColor(Theme.title)
            .padding([.bottom, .top], 5)
    }

    private var processingTimeText: some View {
        Text("Bearbeitungsdauer: \(Rational.displayHoursMinutes(planPrepTime))")
            .font(Theme.bodyFont(16))
            .padding([.trailing], 5)
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
    @State private var planHasOvenConflict = false
    @State private var ovenFreeDates = [PlanDateSuggestion]()
    // How the plan fits by stretching or shortening steps with a time window.
    @State private var windowSuggestion: PlanWindowSuggestion?
    @State private var showingPlanError           = false
    @State private var planErrorMessage           = ""
    @State private var pendingReplaceExisting     = false
    @State private var reminderHintText           = ""
    
    @State private var durations: [String] = []
    /// Today's room temperature for the ripeness estimate of a starter
    /// recipe; starts at the last one noted in its diary.
    @State private var ripenessTemperature = 22
    /// Today's room temperature for a bread's proofing steps; starts at
    /// the one noted with its last bake.
    @State private var proofTemperature = 22
    /// The steps as this plan uses them once the proof was adjusted for
    /// today: the durations by step index, and the steps with their start
    /// times worked out again. The recipe keeps its own durations — they
    /// are what the next adjustment starts from. Empty while the plan uses
    /// the recipe's durations.
    @State private var adjustedDurations: [Int: Int] = [:]
    @State private var adjustedSteps: [PlanStep] = []
    @State private var adjustedPrepTime = 0

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

                // The amount the plan is made for, chosen on the recipe's page.
                Text("Gewicht: \(scaledRecipeWeight) g")
                    .font(Theme.bodyFont(15))
                    .foregroundColor(Theme.subtitle)

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
                                   hasOvenConflict: planHasOvenConflict,
                                   ovenSuggestions: ovenFreeDates,
                                   anchor: PlanAnchor(selection: dateTimeStartSelection),
                                   onApply: { dateTime = $0 },
                                   windowSuggestion: windowSuggestion,
                                   onApplyDurations: applyPlanDurations)

                // MARK: Ripeness today — a starter whose diary knows how it ripens
                if let estimate = ripenessEstimate, let stepIndex = ripeningStepIndex {
                    let plannedMinutes = recipe.instructionsArray[stepIndex].duration
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reifezeit heute")
                            .font(Theme.bodyFont(14).weight(.semibold))
                            .foregroundColor(Theme.cardTitle)
                        Text("Bei \(BakeHistoryFacts.temperatureText(Double(ripenessTemperature), locale: AppSettings.locale)) reif nach etwa \(BakeHistoryFacts.durationText(estimate.minutes))")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.cardTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Geplante Dauer: \(Rational.displayHoursMinutes(plannedMinutes))")
                            .font(Theme.bodyFont(13))
                            .foregroundColor(Theme.subtitle)
                        Stepper(value: $ripenessTemperature, in: 10...35) {
                            LabeledContent("Raumtemperatur heute", value: "\(ripenessTemperature) °C")
                                .font(Theme.bodyFont(14))
                        }
                        if plannedMinutes != estimate.minutes {
                            Button {
                                applyDurations([stepIndex: estimate.minutes])
                            } label: {
                                Label("Reifezeit als Dauer übernehmen", systemImage: "hourglass")
                                    .font(Theme.bodyFont(14).weight(.semibold))
                            }
                            .accessibilityIdentifier("plan.applyRipeness")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .onAppear {
                        if let lastNoted = recipe.starterFeedingLogsArray.compactMap(\.facts.roomTemperature).first {
                            ripenessTemperature = Int(lastNoted.rounded())
                        }
                    }
                }

                // MARK: Proof today — a bread's fermentation steps at today's temperature
                if !proofAdjustments.isEmpty {
                    ProofTodayCardView(temperature: $proofTemperature,
                                       adjustments: proofAdjustments,
                                       isApplied: isProofApplied,
                                       isAdjusted: !adjustedSteps.isEmpty,
                                       recipeDurations: proofRecipeDurations,
                                       onApplyToday: applyProofToday,
                                       onReset: resetAdjustedDurations,
                                       onApplyHistory: applyProofHistory)
                    .onAppear {
                        if let lastNoted = completedBakeFacts.compactMap(\.roomTemperature).first {
                            proofTemperature = Int(lastNoted.rounded())
                        }
                    }
                }


                // MARK: Instructions
                VStack(alignment: .leading) {
                    // Side by side only while both fit on one line each; on an
                    // iPhone "Verarbeitungsschritte:" next to "Bearbeitungsdauer:
                    // 18h 56m" used to break both, leaving the colon on a line
                    // of its own.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            instructionsHeader
                            Spacer()
                            processingTimeText
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            instructionsHeader
                            processingTimeText
                        }
                    }

                    LazyVGrid(columns: gridItemLayoutInstructions, spacing: 6) {

                        Text("Nr.").bold()
                        Text("Beschreibung").bold()
                        // The fixed columns are sized for the German words;
                        // "Duration" shrinks a little instead of breaking mid-word.
                        Text("Dauer").bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Group {

                            // MARK: Change Durations
                            if changeDurationsFlag {

                                Text("Dauer").bold()

                                ForEach(recipe.instructionsArray.indices, id: \.self) { index in

                                    let step = Rational.decimalPlace(recipe.instructionsArray[index].step, 10)

                                    Text(step)
                                    Text(recipe.instructionsArray[index].instruction)
                                    Text(Rational.displayHoursMinutes(recipe.instructionsArray[index].duration))
                                    TextField(String(recipe.instructionsArray[index].duration), text: durationBinding(index))
                                        // Minutes, "1:30" or "1h 30" — see DurationInput.
                                        .keyboardType(.numbersAndPunctuation)
                                        .autocorrectionDisabled()
                                        // The placeholder is the current number
                                        // of minutes, which says nothing on its
                                        // own when read aloud.
                                        .accessibilityLabel("Dauer")

                                }
                                .font(Theme.bodyFont(15))
                            }
                        
                            else {

                                Text("Beginn").bold()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                // The steps as the plan uses them: the recipe's, or
                                // with the proof adjusted for today.
                                let steps = planSteps
                                ForEach(steps.indices, id: \.self) { index in

                                    let step = Rational.decimalPlace(steps[index].step, 10)

                                    Text(step)
                                        .font(Theme.bodyFont(15))
                                    Text(steps[index].instruction)
                                        .font(Theme.bodyFont(15))
                                    Text(Rational.displayHoursMinutes(steps[index].duration))
                                        .font(Theme.bodyFont(15))

                                    if dateTimeStartSelection == 0 {
                                        let date = manager.setNotification(recipe.reminderId, steps[index].instruction, step, steps[index].startTime, dateTime, false)
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                    else {
                                        let date = manager.setNotification(recipe.reminderId, steps[index].instruction, step, steps[index].startTime - planPrepTime, dateTime, false)
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                }

                                // Guard against an empty instructions array (count - 1 would be out of range)
                                if let lastInstruction = steps.last {
                                    Text(String(Int(lastInstruction.step + 1)))
                                    Text("Fertig")
                                    Text(verbatim: "")
                                    if dateTimeStartSelection == 0 {
                                        let date = Calendar.current.date(byAdding: .minute, value: planPrepTime, to: dateTime) ?? dateTime
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
                
                // MARK: Reminder setzen
                HStack {
                    IconActionButton(systemImage: "bell.badge", style: .primary, accessibilityLabel: "Erinnerungen setzen", title: "Erinnerungen setzen", controlSize: .regular) {
                        if hasExistingPlan {
                            showingPlanChoice = true
                        } else {
                            scheduleReminders(replaceExisting: true)
                        }
                    }
                    .accessibilityIdentifier("plan.setReminders")
                    .padding()
                    .confirmationDialog("Für dieses Rezept gibt es schon einen Plan", isPresented: $showingPlanChoice, titleVisibility: .visible) {
                        Button("Bestehenden Plan ersetzen", role: .destructive) {
                            scheduleReminders(replaceExisting: true)
                        }
                        .accessibilityIdentifier("plan.replace")
                        Button("Zusätzlich planen") {
                            scheduleReminders(replaceExisting: false)
                        }
                        Button("Abbrechen", role: .cancel) { }
                    } message: {
                        Text("Du kannst den bestehenden Plan ersetzen oder beide behalten – etwa für zwei Backtage.")
                    }
                    .alert("Erinnerungen wurden gesetzt", isPresented: $showingAlert) {
                        // The plan is set; the page behind shows it under
                        // "Letztes Mal" and "Bisherige Backvorgänge".
                        Button("OK", role: .cancel) { dismiss() }
                    } message: {
                        ReminderSummary.text(count: reminderCount, ovenOn: reminderOvenOnText,
                                             temperature: reminderOvenTemperature,
                                             finish: reminderFinishText, hints: reminderHintText)
                    }
                    .confirmationDialog("Backzeiten überschneiden sich", isPresented: $showingPlanError, titleVisibility: .visible) {
                        Button("Trotzdem planen") {
                            scheduleReminders(replaceExisting: pendingReplaceExisting, ignoringOverlap: true)
                        }
                        Button("Abbrechen", role: .cancel) { }
                    } message: {
                        Text(planErrorMessage)
                    }

                    // MARK: Change Duration Flag bearbeiten
                    if changeDurationsFlag {

                        IconActionButton(systemImage: "checkmark", style: .primary, accessibilityLabel: "Dauer übernehmen", title: "Dauer übernehmen", controlSize: .regular) {
                            applyDurations(typedDurations())
                        }
                        .padding()
                    }
                }
            }
            .padding()
            .frame(width: fullView.size.width, alignment: .leading)
        }
        .warmBackground()
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") {
                    dismiss()
                }
                .accessibilityIdentifier("plan.close")
            }
        }
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
                 steps: planSteps,
                 prepTime: planPrepTime,
                 anchor: PlanAnchor(selection: dateTimeStartSelection),
                 date: dateTime,
                 languageCode: locale.identifier,
                 isStarterFeeding: StarterRecipe.isStarterFeeding(recipe))
    }

    /// The recipe's steps as this plan uses them: with the proof adjusted
    /// for today when it was, else as stored.
    private var planSteps: [PlanStep] {
        guard adjustedSteps.isEmpty else { return adjustedSteps }
        return recipe.instructionsArray.map { planStep(for: $0, startTime: $0.startTime, duration: $0.duration) }
    }

    /// A plan step of a stored one, with the component and the duration
    /// window the advisor needs.
    private func planStep(for stored: Instruction, startTime: Int, duration: Int) -> PlanStep {
        PlanStep(instruction: stored.instruction, step: stored.step, startTime: startTime, duration: duration,
                 componentName: stored.componentName, durationWindow: stored.planDurationWindow, oven: stored.oven)
    }

    private var planPrepTime: Int {
        adjustedSteps.isEmpty ? recipe.prepTime : adjustedPrepTime
    }

    // MARK: Durations

    /// The durations typed under "Dauer ändern", by step index; an empty
    /// field or a value of no length keeps the step's own.
    private func typedDurations() -> [Int: Int] {
        var minutesByIndex: [Int: Int] = [:]
        for i in 0..<recipe.instructionsArray.count {
            let cleaned = (i < durations.count ? durations[i] : "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let minutes = DurationInput.minutes(from: cleaned), minutes > 0 {
                minutesByIndex[i] = minutes
            }
        }
        return minutesByIndex
    }

    /// Writes `minutesByIndex` into the recipe's steps, works the start
    /// times and the total out again and saves — "Dauer übernehmen", and
    /// the ripeness estimate's way into the plan.
    private func applyDurations(_ minutesByIndex: [Int: Int]) {
        var instructionsFB = [InstructionFB]()
        for i in 0..<recipe.instructionsArray.count {
            if let minutes = minutesByIndex[i] { recipe.instructionsArray[i].duration = minutes }

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
        // The recipe's durations changed; an adjustment for today was made
        // from the old ones.
        resetAdjustedDurations()
    }

    // MARK: Proof today

    /// The recipe's fermentation steps — none for a starter, whose
    /// ripening the diary estimates.
    private var proofSteps: [ProofTiming.Step] {
        guard !StarterRecipe.isStarterFeeding(recipe) else { return [] }
        return ProofTiming.steps(instructions: recipe.instructionsArray.map(\.instruction),
                                 durations: recipe.instructionsArray.map(\.duration))
    }

    /// The facts of the recipe's bakes that already took place, newest
    /// first; a plan's entry lies in the future and measured nothing yet.
    private var completedBakeFacts: [BakeHistoryFacts] {
        let now = Date()
        return recipe.bakeHistoriesArray.filter { $0.date <= now }.map(\.facts)
    }

    private var proofAdjustments: [ProofTiming.Adjustment] {
        ProofTiming.adjustments(steps: proofSteps, history: completedBakeFacts, at: Double(proofTemperature))
    }

    /// What the bakes say the recipe's durations should be, where that
    /// differs from the recipe.
    private var proofRecipeDurations: [ProofTiming.RecipeDurations] {
        ProofTiming.recipeDurations(steps: proofSteps, history: completedBakeFacts).filter(\.differs)
    }

    private func isProofApplied(_ adjustment: ProofTiming.Adjustment) -> Bool {
        adjustment.minutesByIndex.allSatisfy { adjustedDurations[$0.key] == $0.value }
    }

    /// Gives this plan the durations of today's proof; the recipe stays as
    /// it is.
    private func applyProofToday() {
        var byIndex = [Int: Int]()
        for adjustment in proofAdjustments {
            byIndex.merge(adjustment.minutesByIndex) { _, new in new }
        }
        applyPlanDurations(byIndex)
    }

    /// Gives this plan new durations for the steps in `byIndex`, on top of
    /// the ones adjusted before, start times worked out again; the recipe
    /// stays as it is. Today's proof and the advisor's window suggestion
    /// both come in here.
    private func applyPlanDurations(_ byIndex: [Int: Int]) {
        adjustedDurations.merge(byIndex) { _, new in new }
        var instructionsFB = [InstructionFB]()
        for (index, stored) in recipe.instructionsArray.enumerated() {
            let instruction = InstructionFB()
            instruction.instruction = stored.instruction
            instruction.step        = stored.step
            instruction.startTime   = stored.startTime
            instruction.duration    = adjustedDurations[index] ?? stored.duration
            instruction.componentName = stored.componentName
            instructionsFB.append(instruction)
        }
        instructionsFB = Rational.calculateStartTimes(
            instructionsFB,
            dateTime,
            dependencies: Rational.ComponentDependency.from(recipe.componentsArray)
        )
        adjustedSteps = zip(recipe.instructionsArray, instructionsFB).map { stored, instructionFB in
            planStep(for: stored, startTime: instructionFB.startTime ?? 0, duration: instructionFB.duration)
        }
        adjustedPrepTime = instructionsFB.last.map { ($0.startTime ?? 0) + $0.duration } ?? recipe.prepTime
        refreshPlanIssues()
    }

    /// Back to the recipe's durations for this plan.
    private func resetAdjustedDurations() {
        adjustedDurations = [:]
        adjustedSteps = []
        adjustedPrepTime = 0
        refreshPlanIssues()
    }

    /// Writes the durations the bakes measured into the recipe, brought to
    /// its reference temperature — "Dauer übernehmen" with those values.
    private func applyProofHistory() {
        var byIndex = [Int: Int]()
        for durations in proofRecipeDurations {
            byIndex.merge(durations.minutesByIndex) { _, new in new }
        }
        guard !byIndex.isEmpty else { return }
        applyDurations(byIndex)
    }

    // MARK: Ripeness

    /// The step whose duration is the ripening: a starter recipe's longest.
    private var ripeningStepIndex: Int? {
        StarterRipeness.ripeningStepIndex(durations: recipe.instructionsArray.map(\.duration))
    }

    /// When a starter is ripe at today's temperature, from its diary; nil
    /// for a bread, or a starter whose diary measured nothing yet.
    private var ripenessEstimate: StarterRipeness.Estimate? {
        guard StarterRecipe.isStarterFeeding(recipe) else { return nil }
        return StarterRipeness.estimate(
            from: StarterFeedingFacts.ripenessObservations(recipe.starterFeedingLogsArray.map(\.facts)),
            at: Double(ripenessTemperature)
        )
    }

    private func refreshPlanIssues() {
        let plan = bakePlan
        planIssues = plan.issues(in: viewContext)
        planHasNightSteps = BakePlanAdvisor.hasNightSteps(plan)
        nightFreeDates = planHasNightSteps ? BakePlanAdvisor.nightFreeDates(for: plan, in: viewContext) : []
        planHasOvenConflict = BakePlanAdvisor.hasOvenConflict(plan, in: viewContext)
        ovenFreeDates = planHasOvenConflict ? BakePlanAdvisor.ovenFreeDates(for: plan, in: viewContext) : []
        windowSuggestion = BakePlanAdvisor.windowSuggestion(
            for: plan, dependencies: Rational.ComponentDependency.from(recipe.componentsArray), in: viewContext)
    }

    /// Sets the reminders and the planned steps for the date chosen above.
    /// `replaceExisting` drops the recipe's earlier plans first; otherwise
    /// the new plan stands beside them — Saturday's and Sunday's loaf.
    private func scheduleReminders(replaceExisting: Bool, ignoringOverlap: Bool = false) {
        // Check the plan before anything changes: overlapping bakes are an
        // error and stop the scheduling (and leave an existing plan alone);
        // the remaining findings are hints and travel with the summary. The
        // user can accept the overlap and proceed anyway — several doughs
        // sharing one oven at a low proofing temperature is a valid case.
        let plan = bakePlan
        // Planned in addition, the recipe's earlier plans stay and need an
        // oven too, so they count; a replaced plan does not.
        let issues = replaceExisting ? plan.issues(in: viewContext) : plan.additionalPlanIssues(in: viewContext)
        planIssues = issues

        let planErrors = issues.filter { $0.severity == .error }
        if !planErrors.isEmpty && !ignoringOverlap {
            planErrorMessage = planErrors.map(\.message).joined(separator: "\n\n")
            pendingReplaceExisting = replaceExisting
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
            // The replaced plan's history entry goes with it; the new plan
            // writes its own below.
            BakePlanScheduler.removePlannedBakeEntries(of: recipe, in: viewContext)
        }

        showingNotificationMessage = true

        // A step that mixes a component carries that component's
        // ingredients in its reminder, in the serving size chosen above.
        let result = BakePlanScheduler.putIntoEffect(plan, for: recipe, planID: planID,
                                                      servingScale: servingScale, manager: manager,
                                                      in: viewContext)

        // A human-readable summary of what was scheduled.
        let timeFormatter  = TimeCalculation()
        reminderCount      = result.reminderCount
        reminderOvenOnText = result.ovenOnDate.map { timeFormatter.calculateTime(t: $0) } ?? ""
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
/// A plan without a bake (feeding a starter) has no oven time and gets no
/// oven line.
enum ReminderSummary {
    static func text(count: Int, ovenOn: String, temperature: String,
                     finish: String, hints: String) -> Text {
        if ovenOn.isEmpty {
            return hints.isEmpty
                ? Text("\(count) Erinnerungen gesetzt.\nFertig um \(finish) Uhr.")
                : Text("\(count) Erinnerungen gesetzt.\nFertig um \(finish) Uhr.\n\n\(hints)")
        }
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
