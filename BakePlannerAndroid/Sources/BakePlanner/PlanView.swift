import BakePlannerCore
import SwiftUI

/// Plans a recipe at the amount chosen in it: from a start or towards a
/// finish, with the steps and their times, what speaks against the plan
/// (ovens busy, steps in the night) and dates without night steps — as the
/// iPhone's baking view does. Planning sets a reminder for every step ahead.
struct PlanView: View {
    let model: AppModel
    let recipe: StoredRecipe
    /// The factor chosen in the recipe: 1 is the recipe as stored.
    let scale: Double
    /// For a public recipe: the own copy the plan is kept for, made only
    /// when the plan is saved (as on the iPhone), nil when it could not be.
    var takeOver: (() async -> StoredRecipe?)? = nil
    /// 0 "Starten ab", 1 "Fertig bis". Starting now, as on the iPhone.
    @State var anchorSelection = 0
    @State var date = Date()
    // Kept apart from the dialogs' visibility: Android closes a dialog
    // before it runs the chosen button.
    @State var showsOverlap = false
    @State var showsPlanChoice = false
    @State var showsSaved = false
    /// What speaks against keeping the plan beside the recipe's earlier
    /// ones, for the second overlap question.
    @State var additionalOverlap = ""
    @State var showsAdditionalOverlap = false
    @State var outcome: AppModel.PlanOutcome = .saved
    /// What was scheduled, for the confirmation: reminders, oven time with
    /// temperature, finish, and the plan's hints — as the iPhone's alert.
    @State var summary: Text?
    /// The recipe as planned, with the durations changed here; an own
    /// recipe keeps them, as on the iPhone.
    @State var workingRecipe: StoredRecipe
    /// "Dauer ändern": a field per step, applied with "Dauer übernehmen".
    @State var editsDurations = false
    @State var durationTexts: [String] = []
    /// The starter's diary, for the ripeness estimate; empty for a bread.
    @State var feedingFacts: [StarterFeedingFacts] = []
    @State var ripenessTemperature = 22
    /// The facts of the recipe's bakes that took place, newest first, for
    /// the proof estimate; empty for a public recipe.
    @State var bakeFacts: [BakeHistoryFacts] = []
    @State var proofTemperature = 22
    /// The durations the proof estimate starts from: the recipe's as
    /// stored, or as last taken over with "Dauer übernehmen". "Gare an
    /// heutige Temperatur anpassen" changes the working recipe only, as
    /// on the iPhone.
    @State var baselineDurations: [Int]
    @Environment(\.dismiss) var dismiss

    /// The step whose duration is the ripening: a starter recipe's longest.
    private var ripeningStepIndex: Int? {
        StarterRipeness.ripeningStepIndex(durations: workingRecipe.content.instructions.map { $0.duration })
    }

    /// When the starter is ripe at today's temperature, from its diary.
    private var ripenessEstimate: StarterRipeness.Estimate? {
        guard StarterRecipe.isStarterFeeding(workingRecipe.content) else { return nil }
        return StarterRipeness.estimate(from: StarterFeedingFacts.ripenessObservations(feedingFacts),
                                        at: Double(ripenessTemperature))
    }

    init(model: AppModel, recipe: StoredRecipe, scale: Double, takeOver: (() async -> StoredRecipe?)? = nil) {
        self.model = model
        self.recipe = recipe
        self.scale = scale
        self.takeOver = takeOver
        _workingRecipe = State(initialValue: recipe)
        _durationTexts = State(initialValue: recipe.content.instructions.map { DurationInput.text(forMinutes: $0.duration) })
        _baselineDurations = State(initialValue: recipe.content.instructions.map { $0.duration })
    }

    // MARK: Proof today

    /// The recipe's fermentation steps; none for a starter, whose
    /// ripening the diary estimates.
    private var proofSteps: [ProofTiming.Step] {
        guard !StarterRecipe.isStarterFeeding(workingRecipe.content) else { return [] }
        return ProofTiming.steps(instructions: workingRecipe.content.instructions.map { $0.instruction },
                                 durations: baselineDurations)
    }

    private var proofAdjustments: [ProofTiming.Adjustment] {
        ProofTiming.adjustments(steps: proofSteps, history: bakeFacts, at: Double(proofTemperature))
    }

    /// What the bakes say the recipe's durations should be, where that
    /// differs from the recipe.
    private var proofRecipeDurations: [ProofTiming.RecipeDurations] {
        ProofTiming.recipeDurations(steps: proofSteps, history: bakeFacts).filter { $0.differs }
    }

    private var proofIsAdjusted: Bool {
        workingRecipe.content.instructions.map { $0.duration } != baselineDurations
    }

    private func isProofApplied(_ adjustment: ProofTiming.Adjustment) -> Bool {
        adjustment.minutesByIndex.allSatisfy { index, minutes in
            index < workingRecipe.content.instructions.count && workingRecipe.content.instructions[index].duration == minutes
        }
    }

    /// Gives the working recipe the durations of today's proof, start
    /// times worked out again; nothing is saved.
    private func applyProofToday() {
        var content = workingRecipe.content
        for (index, minutes) in baselineDurations.enumerated() where index < content.instructions.count {
            content.instructions[index].duration = minutes
        }
        for adjustment in proofAdjustments {
            for (index, minutes) in adjustment.minutesByIndex where index < content.instructions.count {
                content.instructions[index].duration = minutes
            }
        }
        workingRecipe.content = content.recalculated()
    }

    /// Back to the recipe's durations.
    private func resetProof() {
        var content = workingRecipe.content
        for (index, minutes) in baselineDurations.enumerated() where index < content.instructions.count {
            content.instructions[index].duration = minutes
        }
        workingRecipe.content = content.recalculated()
    }

    /// Writes the durations the bakes measured into the recipe, brought to
    /// its reference temperature — "Dauer übernehmen" with those values.
    private func applyProofHistory() {
        for durations in proofRecipeDurations {
            for (index, minutes) in durations.minutesByIndex where index < durationTexts.count {
                durationTexts[index] = DurationInput.text(forMinutes: minutes)
            }
        }
        applyDurations()
    }

    private var plan: BakePlan {
        AppModel.plan(of: workingRecipe, anchor: PlanAnchor(selection: anchorSelection), date: date)
    }

    /// Every field holds a duration (empty keeps the step's own).
    private var durationsAreValid: Bool {
        durationTexts.allSatisfy { DurationInput.minutes(from: $0) != nil }
    }

    /// Writes the typed durations into the recipe and works the start
    /// times out again; an own recipe is saved with them, a public one
    /// keeps them for this plan only — as on the iPhone.
    private func applyDurations() {
        var content = workingRecipe.content
        for (index, text) in durationTexts.enumerated() where index < content.instructions.count {
            if let minutes = DurationInput.minutes(from: text), minutes > 0 {
                content.instructions[index].duration = minutes
            }
        }
        workingRecipe.content = content.recalculated()
        durationTexts = workingRecipe.content.instructions.map { DurationInput.text(forMinutes: $0.duration) }
        baselineDurations = workingRecipe.content.instructions.map { $0.duration }
        if takeOver == nil {
            _ = model.save(workingRecipe)
        }
        editsDurations = false
    }

    var body: some View {
        let plan = self.plan
        let issues = model.issues(of: plan)
        let suggestions = model.nightFreeDates(for: plan)
        let ovenSuggestions = model.ovenFreeDates(for: plan)
        return Form {
            Section {
                Picker("Startzeit", selection: $anchorSelection) {
                    Text("Starten ab").tag(0)
                    Text("Fertig bis").tag(1)
                }
                .pickerStyle(.segmented)
                DatePicker("Datum", selection: $date, displayedComponents: [.date, .hourAndMinute])
                if scale != 1 {
                    Text("Die Mengen entsprechen dem Faktor \(RecipeDetailView.factorText(scale)).")
                        .font(AppFont.caption)
                }
            }

            if !issues.isEmpty || !suggestions.isEmpty || !ovenSuggestions.isEmpty {
                Section {
                    ForEach(issues) { issue in
                        Text(verbatim: issue.message)
                            .foregroundStyle(issue.severity == .error ? Color.red : Color.primary)
                    }
                    if !ovenSuggestions.isEmpty {
                        Text("So werden die Backöfen nacheinander frei:")
                            .font(AppFont.caption)
                        ForEach(ovenSuggestions) { suggestion in
                            HStack {
                                Text(verbatim: PlanText.dateTime(suggestion.start) + " – " + PlanText.dateTime(suggestion.finish))
                                Spacer()
                                Button("Übernehmen") {
                                    date = suggestion.date
                                }
                            }
                        }
                    }
                    if !suggestions.isEmpty {
                        Text("So beginnt kein Schritt in der Nacht:")
                            .font(AppFont.caption)
                        ForEach(suggestions) { suggestion in
                            HStack {
                                Text(verbatim: PlanText.dateTime(suggestion.start) + " – " + PlanText.dateTime(suggestion.finish))
                                Spacer()
                                Button("Übernehmen") {
                                    date = suggestion.date
                                }
                            }
                        }
                    }
                }
            }

            if let estimate = ripenessEstimate, let stepIndex = ripeningStepIndex {
                let plannedMinutes = workingRecipe.content.instructions[stepIndex].duration
                Section {
                    Text("Bei \(BakeHistoryFacts.temperatureText(Double(ripenessTemperature), locale: AppSettings.locale)) reif nach etwa \(BakeHistoryFacts.durationText(estimate.minutes))")
                    Text("Geplante Dauer: \(Rational.displayHoursMinutes(plannedMinutes))")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                    Stepper(value: $ripenessTemperature, in: 10...35) {
                        ValueLabel(title: "Raumtemperatur heute", value: "\(ripenessTemperature) °C")
                    }
                    if plannedMinutes != estimate.minutes {
                        Button("Reifezeit als Dauer übernehmen") {
                            if stepIndex < durationTexts.count {
                                durationTexts[stepIndex] = DurationInput.text(forMinutes: estimate.minutes)
                                applyDurations()
                            }
                        }
                    }
                } header: {
                    Text("Reifezeit heute")
                }
            }

            // A bread's fermentation steps at today's temperature, as the
            // iPhone's card "Gare heute".
            if !proofAdjustments.isEmpty {
                Section {
                    Stepper(value: $proofTemperature, in: ProofTiming.temperatureRange) {
                        ValueLabel(title: "Raumtemperatur heute", value: "\(proofTemperature) °C")
                    }
                    ForEach(Array(proofAdjustments.enumerated()), id: \.offset) { _, adjustment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(adjustment.phase.title()): geplant \(BakeHistoryFacts.durationText(adjustment.plannedMinutes)) · heute etwa \(BakeHistoryFacts.durationText(adjustment.minutes))")
                            Text(verbatim: adjustment.sourceText())
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if proofAdjustments.contains(where: { !isProofApplied($0) }) {
                        Button("Gare an heutige Temperatur anpassen") {
                            applyProofToday()
                        }
                    }
                    if proofIsAdjusted {
                        Text("Für diesen Plan angepasst; das Rezept bleibt unverändert.")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                        Button("Dauern des Rezepts verwenden") {
                            resetProof()
                        }
                    }
                    if !proofRecipeDurations.isEmpty {
                        ForEach(Array(proofRecipeDurations.enumerated()), id: \.offset) { _, durations in
                            Text("\(durations.phase.title()): \(BakeHistoryFacts.durationText(durations.minutes)) bei \(BakeHistoryFacts.temperatureText(durations.referenceTemperature, locale: AppSettings.locale)) \(ProofTiming.bakesText(durations.bakes)), im Rezept \(BakeHistoryFacts.durationText(durations.plannedMinutes))")
                        }
                        Button("Dauern aus den Backvorgängen ins Rezept übernehmen") {
                            applyProofHistory()
                        }
                    }
                } header: {
                    Text("Gare heute")
                }
            }

            Section {
                Toggle("Dauer ändern", isOn: $editsDurations)
                if editsDurations {
                    // The recipe's own steps with a field each; the steps the
                    // plan adds (oven on, bake end) have no duration to change.
                    ForEach(Array(workingRecipe.content.instructions.enumerated()), id: \.offset) { index, instruction in
                        HStack(alignment: .top, spacing: 8) {
                            Text(verbatim: instruction.instruction)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            TextField("Dauer", text: Binding(
                                get: { index < durationTexts.count ? durationTexts[index] : "" },
                                set: { value in
                                    if index < durationTexts.count { durationTexts[index] = value }
                                }))
                                .frame(width: 140)
                                .foregroundStyle(DurationInput.minutes(from: index < durationTexts.count ? durationTexts[index] : "") == nil
                                                 ? Color.red : Color.primary)
                        }
                    }
                    Button("Dauer übernehmen") {
                        applyDurations()
                    }
                    .disabled(!durationsAreValid)
                } else {
                    ForEach(Array(plan.allSteps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text(verbatim: PlanText.dateTime(plan.date(of: step)))
                                .font(AppFont.caption)
                                .frame(width: 110, alignment: .leading)
                            Text(verbatim: step.instruction)
                        }
                    }
                }
            } header: {
                Text("Verarbeitungsschritte")
            }
        }
        .navigationTitle(recipe.content.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Planen") {
                    if issues.contains(where: { $0.severity == .error }) {
                        showsOverlap = true
                    } else {
                        choosePlan()
                    }
                }
                .disabled(recipe.content.instructions.isEmpty)
            }
        }
        .alert("Backzeiten überschneiden sich", isPresented: $showsOverlap) {
            Button("Trotzdem planen") {
                choosePlan()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text(verbatim: issues.filter { $0.severity == .error }.map(\.message).joined(separator: "\n"))
        }
        .alert("Für dieses Rezept gibt es schon einen Plan", isPresented: $showsPlanChoice) {
            Button("Bestehenden Plan ersetzen", role: .destructive) {
                save(replacing: true)
            }
            Button("Zusätzlich planen") {
                planInAddition(alreadyAccepted: issues)
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Du kannst den bestehenden Plan ersetzen oder beide behalten – etwa für zwei Backtage.")
        }
        // Planned in addition, the recipe's earlier plans stay and need an
        // oven too. Asked only about what was not accepted above already.
        .alert("Backzeiten überschneiden sich", isPresented: $showsAdditionalOverlap) {
            Button("Trotzdem planen") {
                save(replacing: false)
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text(verbatim: additionalOverlap)
        }
        .task {
            feedingFacts = model.feedings(ofRecipe: recipe.id).map { $0.facts }
            if let lastNoted = feedingFacts.compactMap({ $0.roomTemperature }).first {
                ripenessTemperature = Int(lastNoted.rounded())
            }
            // The bakes that took place; a plan's entry lies in the future
            // and measured nothing yet. The model's list is newest first.
            let now = Date()
            bakeFacts = model.bakeHistory
                .filter { $0.recipeID == recipe.id && $0.date <= now }
                .map { $0.facts }
            if let lastNoted = bakeFacts.compactMap({ $0.roomTemperature }).first {
                proofTemperature = Int(lastNoted.rounded())
            }
        }
        .alert(outcomeTitle, isPresented: $showsSaved) {
            Button {
                if outcome != .failed { dismiss() }
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            if outcome == .savedWithoutReminders {
                Text("Der Plan steht in der Zeitleiste, aber ohne Erinnerungen: BakePlanner darf keine Benachrichtigungen senden. Das lässt sich in den Android-Einstellungen unter Apps ändern.")
            } else if outcome == .saved, let summary {
                summary
            }
        }
    }

    private func planInAddition(alreadyAccepted: [BakePlanIssue]) {
        let accepted = Set(alreadyAccepted.filter { $0.severity == .error }.map(\.message))
        let errors = model.additionalPlanIssues(of: plan)
            .filter { $0.severity == .error }
            .map(\.message)
        guard errors.contains(where: { !accepted.contains($0) }) else {
            save(replacing: false)
            return
        }
        additionalOverlap = errors.joined(separator: "\n")
        showsAdditionalOverlap = true
    }

    private func choosePlan() {
        if model.hasPlan(recipeName: recipe.content.name) {
            showsPlanChoice = true
        } else {
            save(replacing: false)
        }
    }

    private var outcomeTitle: LocalizedStringKey {
        switch outcome {
        case .saved: return "Erinnerungen wurden gesetzt"
        case .savedWithoutReminders: return "Plan gespeichert"
        case .failed: return "Die Änderung konnte nicht gespeichert werden."
        }
    }

    /// The confirmation's wording, the iPhone's ReminderSummary: no oven
    /// line for a plan without a bake (feeding a starter). Built line by
    /// line — the iPhone's whole-text keys would all get the same generated
    /// catalog symbol here, which Xcode refuses — and SkipFuseUI has no
    /// Text + Text, so the lines are joined as strings.
    private func summaryText(of plan: BakePlan, hints: String) -> Text {
        let count = plan.allSteps.count
        let finish = PlanText.time(plan.date(of: plan.endStep))
        var lines = [String(localized: "\(count) Erinnerungen gesetzt.", bundle: .module)]
        if let ovenStep = plan.ovenOnStep {
            let ovenOn = PlanText.time(plan.date(of: ovenStep))
            let temperature = plan.ovenTemperature ?? ""
            lines.append(temperature.isEmpty
                ? String(localized: "Backofen anstellen um \(ovenOn) Uhr.", bundle: .module)
                : String(localized: "Backofen anstellen um \(ovenOn) Uhr mit \(temperature).", bundle: .module))
        }
        lines.append(String(localized: "Fertig um \(finish) Uhr.", bundle: .module))
        var text = lines.joined(separator: "\n")
        if !hints.isEmpty {
            text += "\n\n" + hints
        }
        return Text(verbatim: text)
    }

    private func save(replacing: Bool) {
        let plan = self.plan
        let hints = model.issues(of: plan).filter { $0.severity == .hint }.map(\.message).joined(separator: "\n\n")
        summary = summaryText(of: plan, hints: hints)
        Task {
            var recipeID = recipe.id
            if let takeOver {
                guard let copy = await takeOver() else {
                    outcome = .failed
                    showsSaved = true
                    return
                }
                recipeID = copy.id
            }
            outcome = await model.putIntoEffect(plan, recipeID: recipeID, servingScale: scale, replacing: replacing)
            showsSaved = true
        }
    }
}

/// How plan dates read: "Sa., 1.11., 08:30" in the app's language.
enum PlanText {
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMHHmm")
        return formatter.string(from: date)
    }

    /// "Mi., 4.11." in the app's language.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdM")
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.locale
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter.string(from: date)
    }
}
