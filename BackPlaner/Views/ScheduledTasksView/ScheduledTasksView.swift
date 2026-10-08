//
//  ScheduledTasksView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 03.12.21.
//

import SwiftUI
import CoreData
import Foundation
import os

struct ScheduledTasksView: View {
    
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.locale) private var locale
    // At the accessibility text sizes the recipe name and its three buttons
    // no longer share a row, and the time pill, date and duration stack.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // The round done / ingredients / shift buttons grow with the text, so
    // their symbols are not left as 15 pt dots inside large-text cards.
    @ScaledMetric(relativeTo: .subheadline) private var actionButtonSize: CGFloat = 32
    
    @EnvironmentObject var model:RecipeModel

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    let date = Date() - 60
    
    let dateRange: ClosedRange<Date> = GlobalVariables.planningDateRange()
    
    var nextStepsRequest: FetchRequest<NextStep>
    var nextSteps: FetchedResults<NextStep> { nextStepsRequest.wrappedValue }
    
    @State private var name = ""
    
    init() {
        self.nextStepsRequest = FetchRequest(entity: NextStep.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    }

    @State private var confirmationShown = false
    @State private var dateTime          = GlobalVariables.dateTimePicker
    @State private var deleteHaptic      = false
    @State private var doneHaptic        = false
    @State private var showingBakeMode   = false
    @State private var shiftSelection: ScheduledStepShiftSelection?
    @State private var ingredientsSelection: ScheduledStepIngredientsSelection?
    @State private var showingShiftError = false
    @State private var shiftErrorMessage = ""

    /// The plan the list is narrowed down to; `nil` shows every planned step.
    @State private var planFilter: PlanKey?

    /// The distinct recipes that currently have planned steps.
    private var plannedRecipeNames: [String] {
        var seen = Set<String>()
        return nextSteps
            .compactMap { seen.insert($0.recipeName).inserted ? $0.recipeName : nil }
            .sorted()
    }

    /// The distinct plans — a recipe planned for two days is two of them —
    /// in the order of their first step, the choices of the filter bar.
    private var plannedPlans: [PlanKey] {
        var seen = Set<PlanKey>()
        return nextSteps
            .compactMap { seen.insert($0.planKey).inserted ? $0.planKey : nil }
            .sorted { a, b in
                a.recipeName == b.recipeName
                    ? firstDate(of: a) < firstDate(of: b)
                    : a.recipeName < b.recipeName
            }
    }

    private func firstDate(of plan: PlanKey) -> Date {
        nextSteps.first { $0.planKey == plan }?.date ?? .distantFuture
    }

    /// The steps shown in the list: all of them, or only those of the plan
    /// selected in the filter bar.
    private var visibleSteps: [NextStep] {
        guard let planFilter else { return Array(nextSteps) }
        return nextSteps.filter { $0.planKey == planFilter }
    }

    var body: some View {
 
        VStack(spacing: 0) {

        if nextSteps.isEmpty {
            ContentUnavailableView(
                "Keine geplanten Schritte",
                systemImage: "calendar",
                description: Text("Setze Erinnerungen in der Backanleitung eines Rezepts.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {

            // Only worth showing once more than one plan exists.
            if plannedPlans.count > 1 {
                recipeFilterBar
            }

            if visibleSteps.isEmpty {
                ContentUnavailableView {
                    Label("Keine Schritte für dieses Rezept", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Wähle „Alle“, um alle geplanten Schritte zu sehen.")
                } actions: {
                    Button("Filter aufheben") { planFilter = nil }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {

            ForEach(changedRecipes, id: \.objectID) { recipe in
                recipeChangedBanner(recipe)
            }

            bakeModeButton

            List {

            ForEach(visibleSteps, id: \.objectID) { nextStep in

                // Each step is a card: the start time and duration share the top
                // line, and the full instruction wraps freely underneath. This
                // reads well in portrait and no longer needs fixed-width columns
                // or forced landscape.
                HStack(alignment: .top, spacing: 12) {

                    // Recipe thumbnail
                    Group {
                        if let dataImage = fetchRecipeImage(name: nextStep.recipeName) {
                            let image = UIImage(data: dataImage) ?? UIImage()
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        else {
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Theme.subtitle)
                        }
                    }
                    .frame(width: 52, height: 52, alignment: .center)
                    .clipped()
                    .cornerRadius(8)
                    // Decorative: the recipe name is right next to it.
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {

                        let topRowLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

                        topRowLayout {
                            Text(nextStep.recipeName)
                                .font(Theme.bodyFont(15))
                                .foregroundColor(Theme.subtitle)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer(minLength: 8)
                            }

                            HStack(spacing: 8) {
                            // Done, right on the card. Swiping left deletes,
                            // which reads as discarding; this is the same
                            // removal, named for what it means mid-bake.
                            Button {
                                markDone(nextStep)
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.accentText)
                                    .frame(width: actionButtonSize, height: actionButtonSize)
                                    .background(.thinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Schritt als erledigt markieren")
                            // A checkmark symbol makes VoiceOver call the
                            // button "selected"; it is an action, not a state.
                            .accessibilityRemoveTraits(.isSelected)

                            // Only a step that prepares a component has
                            // ingredients of its own to show.
                            if let component = component(for: nextStep) {
                                Button {
                                    ingredientsSelection = ScheduledStepIngredientsSelection(
                                        id: nextStep.objectID,
                                        recipeName: nextStep.recipeName,
                                        instruction: nextStep.instruction,
                                        component: component
                                    )
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(Theme.accentText)
                                        .frame(width: actionButtonSize, height: actionButtonSize)
                                        .background(.thinMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Zutaten der Komponente anzeigen")
                            }

                            Button {
                                beginShifting(nextStep)
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.accentText)
                                    .frame(width: actionButtonSize, height: actionButtonSize)
                                    .background(.thinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Schritt zeitlich verschieben")
                            }
                        }

                        // Every part keeps its natural width. These used to be
                        // `Label`s, which are greedy horizontally: with layout
                        // priorities the two of them shared the row and the
                        // date in between was squeezed to "09…" as soon as a
                        // 12-hour time like "12:34 AM" got wide. Plain stacks
                        // of icon and text have no such appetite, and
                        // `fixedSize()` on a `Label` collapses its title
                        // instead of protecting it.
                        let timeRowLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                            : AnyLayout(HStackLayout(spacing: 6))

                        timeRowLayout {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                Text(nextStep.date, style: .time)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .font(Theme.brandFont(15))
                            // The foreground accent, not the gradient one: this
                            // text also has to clear 4.5:1 against its own tint.
                            .foregroundColor(Theme.accentText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.accentText.opacity(0.12), in: Capsule())

                            Text(shortDate(nextStep.date))
                                .font(Theme.bodyFont(15))
                                .foregroundColor(Theme.subtitle)
                                .lineLimit(1)
                                .fixedSize()

                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                Text(Rational.displayHoursMinutes(nextStep.duration))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .font(Theme.bodyFont(13))
                            .foregroundColor(Theme.subtitle)

                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer(minLength: 0)
                            }
                        }

                        Text(nextStep.instruction)
                            .font(Theme.brandFont(16))
                            .foregroundColor(Theme.cardTitle)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
                // NavigationLink in the background keeps the whole row tappable
                // without adding a disclosure chevron.
                .background(
                    NavigationLink(
                        "",
                        destination: ScheduledTaskDetailView(index: index(for: nextStep))
                    )
                    .opacity(0)
                    // The link carries no title of its own, so VoiceOver would
                    // otherwise announce an unnamed link behind every card.
                    .accessibilityLabel("Details zu \(nextStep.recipeName)")
                )
                // Swiping right marks the step done, mirroring the reminder's
                // "Erledigt" action. The tint is the app accent, not green:
                // the label carries the meaning, not the colour.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        markDone(nextStep)
                    } label: {
                        Label("Erledigt", systemImage: "checkmark")
                    }
                    .tint(Theme.accentText)
                }
            }
            // The index set refers to the visible (possibly filtered) rows, not
            // to the full fetch result.
            .onDelete { indexSet in
                guard let index = indexSet.first, visibleSteps.indices.contains(index) else { return }
                remove(visibleSteps[index])
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        }
        .clearScrollBackground()
        .sensoryFeedback(.success, trigger: doneHaptic)
        // Compact, floating delete button so it takes no layout space of its own.
        .overlay(alignment: .bottomTrailing) {
            IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Geplante Schritte löschen", controlSize: .large) {
                confirmationShown = true
            }
            .background(.thinMaterial, in: Circle())
            .padding()
            .confirmationDialog("Geplante Schritte löschen?", isPresented: $confirmationShown, titleVisibility: .visible) {
                // With an active filter the user can restrict the deletion to
                // the selected recipe instead of clearing the whole plan.
                if let planFilter {
                    Button("Nur „\(planFilter.recipeName)“ löschen", role: .destructive) {
                        deleteNextSteps(of: planFilter)
                    }
                }
                Button("Alle löschen", role: .destructive) {
                    deleteNextSteps(of: nil)
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                if let planFilter {
                    Text("Entferne nur die geplanten Schritte von „\(planFilter.recipeName)“ samt Erinnerungen – oder alle geplanten Schritte.")
                } else {
                    Text("Dies entfernt alle geplanten Schritte und die zugehörigen Erinnerungen.")
                }
            }
            .sensoryFeedback(.success, trigger: deleteHaptic)
        }
        }
        }
        }
        .warmBackground()
        .navigationTitle("Liste der nächsten Schritte")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $shiftSelection) { selection in
            ScheduledStepShiftSheet(
                recipeName: selection.recipeName,
                instruction: selection.instruction
            ) { minutes, includeFollowing in
                shiftSelection = nil
                performShift(
                    stepID: selection.id,
                    byMinutes: minutes,
                    includeFollowing: includeFollowing
                )
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showingBakeMode) {
            BakeModeView(planFilter: planFilter)
                .environment(\.managedObjectContext, managedObjectContext)
                .environmentObject(model)
        }
        .sheet(item: $ingredientsSelection) { selection in
            ScheduledStepIngredientsSheet(
                recipeName: selection.recipeName,
                instruction: selection.instruction,
                component: selection.component
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Verschieben nicht möglich", isPresented: $showingShiftError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shiftErrorMessage)
        }
        // Once the filtered recipe has no planned steps left, fall back to
        // showing everything instead of an empty list.
        .onChange(of: plannedPlans) { _, plans in
            if let planFilter, !plans.contains(planFilter) {
                self.planFilter = nil
            }
        }
        .onAppear() {  }
    }

    /// The user's own recipes whose planned steps no longer match the recipe:
    /// a step's text or duration was edited, or a step was removed, after the
    /// reminders were set. Planned steps are a snapshot, so the plan keeps
    /// the old state until it is set again — this makes that visible instead
    /// of leaving it to be discovered mid-bake.
    ///
    /// A step marked done is simply missing from the plan and does not count;
    /// a step added to the recipe afterwards is not detected either.
    private var changedRecipes: [Recipe] {
        let names = planFilter.map { [$0.recipeName] } ?? plannedRecipeNames
        return names.compactMap { name in
            guard let recipe = recipes.first(where: { $0.name == name }) else { return nil }
            let instructions = recipe.instructionsArray
            // The oven, turn-down and finish steps are generated at planning
            // time and live only in the plan, never in the recipe.
            let planned = nextSteps.filter {
                $0.recipeName == name
                    && $0.step < 99
                    && !BakePlanValidator.isPreheatInstruction($0.instruction)
                    && !BakePlan.isTurnDownInstruction($0.instruction)
            }
            let unchanged = planned.allSatisfy { step in
                instructions.contains {
                    $0.step == step.step && $0.instruction == step.instruction && $0.duration == step.duration
                }
            }
            return unchanged ? nil : recipe
        }
    }

    private func recipeChangedBanner(_ recipe: Recipe) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(Theme.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("„\(recipe.name)“ wurde seit der Planung geändert. Der Plan zeigt noch den alten Stand.")
                    .font(Theme.bodyFont(14))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink {
                    TabsView(recipe: recipe, startsInBakingView: true)
                } label: {
                    Label("Neu planen", systemImage: "arrow.clockwise")
                        .font(Theme.brandFont(14))
                        .foregroundColor(Theme.accentText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle(cornerRadius: 14)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Opens the kitchen view of the plan — one step at a time in large type.
    /// Respects the recipe filter above it.
    private var bakeModeButton: some View {
        Button {
            showingBakeMode = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "oven.fill")
                    .font(.system(size: 17, weight: .semibold))
                Text("Backmodus starten")
                    .font(Theme.brandFont(16))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Horizontal chips to narrow the list down to a single planned recipe.
    /// Deliberately part of the view instead of the navigation bar: this screen
    /// lives inside a `TabView`, where toolbars of the tab children stay hidden.
    private var recipeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {

                filterChip(Text("Alle"), plan: nil)

                ForEach(plannedPlans, id: \.self) { plan in
                    filterChip(chipLabel(for: plan), plan: plan)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// The recipe name — and, when the recipe is planned more than once, the
    /// start of this plan to tell them apart.
    private func chipLabel(for plan: PlanKey) -> Text {
        let siblings = plannedPlans.filter { $0.recipeName == plan.recipeName }
        guard siblings.count > 1 else { return Text(verbatim: plan.recipeName) }
        return Text("\(plan.recipeName) · \(firstDate(of: plan), format: .dateTime.day().month().hour().minute())")
    }

    private func filterChip(_ label: Text, plan: PlanKey?) -> some View {
        let isSelected = planFilter == plan

        return Button {
            planFilter = plan
        } label: {
            label
                .font(Theme.bodyFont(14))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : Theme.subtitle)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.card))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = locale.identifier.lowercased().hasPrefix("en")
            ? "MM-dd"
            : "dd.MM."
        return formatter.string(from: date)
    }

    private func index(for step: NextStep) -> Int {
        nextSteps.firstIndex(where: { $0.objectID == step.objectID }) ?? 0
    }

    /// Done and deleted are the same removal; done just says so and confirms
    /// with a tap of haptics.
    private func markDone(_ step: NextStep) {
        remove(step)
        doneHaptic.toggle()
    }

    /// Removes one planned step together with its pending reminder.
    private func remove(_ step: NextStep) {
        // Cancel the matching reminder first, so it cannot fire for a step
        // that no longer exists. The delete dialog does the same for a whole
        // recipe or for every step at once.
        NotificationActions.cancelPendingNotification(for: step)

        managedObjectContext.delete(step)

        do {
            try managedObjectContext.save()
        } catch {
            managedObjectContext.rollback()
            AppLog.persistence.error("Could not delete next step")
        }
    }

    /// The component a planned step mixes, with its ingredients — or `nil` for
    /// every other step.
    ///
    /// A planned step stores neither its instruction nor its component, only
    /// the recipe name and the step number. The user's own recipes are tried
    /// first, then the public ones, since a plan can come from either.
    private func component(for nextStep: NextStep) -> ComponentColumn? {
        if let recipe = recipes.first(where: { $0.name == nextStep.recipeName }) {
            return ScheduledStepComponent.column(for: recipe, step: nextStep.step, instructionText: nextStep.instruction)
        }
        if let recipeFB = model.recipesFB.first(where: { $0.name == nextStep.recipeName }) {
            return ScheduledStepComponent.column(for: recipeFB, step: nextStep.step, instructionText: nextStep.instruction)
        }
        return nil
    }

    private func beginShifting(_ step: NextStep) {
        shiftSelection = ScheduledStepShiftSelection(
            id: step.objectID,
            recipeName: step.recipeName,
            instruction: step.instruction
        )
    }

    private func performShift(
        stepID: NSManagedObjectID,
        byMinutes minutes: Int,
        includeFollowing: Bool
    ) {
        guard let step = nextSteps.first(where: { $0.objectID == stepID }) else {
            presentShiftError("Der ausgewählte Schritt wurde nicht gefunden.")
            return
        }

        NotificationActions.shiftScheduledStep(
            step,
            byMinutes: minutes,
            includeFollowing: includeFollowing
        ) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    shiftErrorMessage = error.localizedDescription
                    showingShiftError = true
                }
            }
        }
    }

    private func presentShiftError(_ message: String) {
        shiftErrorMessage = message
        DispatchQueue.main.async {
            showingShiftError = true
        }
    }

    /// Deletes the planned steps of a single plan, or all of them when `plan`
    /// is `nil`, together with their pending reminders.
    func deleteNextSteps(of plan: PlanKey?) {
        let stepsToDelete = plan == nil
            ? Array(nextSteps)
            : nextSteps.filter { $0.planKey == plan }

        guard !stepsToDelete.isEmpty else { return }

        // Reminders are matched by instruction and date, so this has to run
        // while the steps still exist.
        NotificationActions.cancelPendingNotifications(for: stepsToDelete)

        do {
            for nextStep in stepsToDelete {
                managedObjectContext.delete(nextStep)
            }
            try managedObjectContext.save()
            deleteHaptic.toggle()
        } catch {
            managedObjectContext.rollback()
            AppLog.persistence.error("Could not delete next steps")
            return
        }

        if plan == nil {
            // Clearing the whole plan also drops reminders whose step was
            // already gone — those cannot be matched individually any more.
            NotificationActions.cancelAllReminders()
        }

        planFilter = nil
    }

    func fetchRecipeImage(name: String) -> Data? {

        let recipes = fetchRecipes(name: name)

        if recipes.count > 0 {

            return recipes[0].image
        }
        else {
            return nil
        }
    }

    func fetchRecipes(name: String) -> [Recipe] {

        return recipes.filter { r in
            return r.name.contains(name)
        }
    }
}

/// One planning run of one recipe. Steps planned before `planID` existed
/// have none and form a single plan per recipe.
struct PlanKey: Hashable {
    let recipeName: String
    let planID: UUID?

    /// Matches exactly the steps of this plan.
    var predicate: NSPredicate {
        if let planID {
            return NSPredicate(format: "recipeName == %@ AND planID == %@", recipeName, planID as CVarArg)
        }
        return NSPredicate(format: "recipeName == %@ AND planID == nil", recipeName)
    }
}

extension NextStep {
    var planKey: PlanKey { PlanKey(recipeName: recipeName, planID: planID) }
}

private struct ScheduledStepShiftSelection: Identifiable {
    let id: NSManagedObjectID
    let recipeName: String
    let instruction: String
}

private struct ScheduledStepIngredientsSelection: Identifiable {
    let id: NSManagedObjectID
    let recipeName: String
    let instruction: String
    let component: ComponentColumn
}

/// The ingredients of the component a planned mixing step prepares, so they
/// can be weighed out straight from the plan without opening the recipe.
private struct ScheduledStepIngredientsSheet: View {

    @Environment(\.dismiss) private var dismiss

    let recipeName: String
    let instruction: String
    let component: ComponentColumn

    /// The serving size the recipe screens default to, so the amounts here
    /// match what the user saw when planning.
    private let servingSize = AppSettings.storedServingSize

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(recipeName)
                        .font(.headline)
                    Text(instruction)
                        .foregroundColor(Theme.subtitle)
                }

                Section {
                    if component.ingredients.isEmpty {
                        Text("Keine Zutaten vorhanden")
                            .foregroundColor(Theme.subtitle)
                    } else {
                        ForEach(Array(component.ingredients.enumerated()), id: \.offset) { _, ingredient in
                            Text(
                                Rational.getPortion(unit: ingredient.unit,
                                                    weight: ingredient.weight,
                                                    num: ingredient.numerator,
                                                    denom: ingredient.denominator,
                                                    targetServings: servingSize)
                                + ingredient.name
                            )
                            .font(Theme.bodyFont(15))
                        }
                    }
                } header: {
                    Text("Zutaten für „\(component.name)“")
                }
            }
            .navigationTitle(Text(verbatim: component.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ScheduledStepShiftSheet: View {
    enum Direction: String, CaseIterable, Identifiable {
        case earlier
        case later

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .earlier: "Früher"
            case .later: "Später"
            }
        }

        var multiplier: Int {
            self == .earlier ? -1 : 1
        }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case current
        case following

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .current: "Nur dieser Schritt"
            case .following: "Alle nachfolgenden"
            }
        }

        var includesFollowing: Bool {
            self == .following
        }
    }

    @Environment(\.dismiss) private var dismiss

    let recipeName: String
    let instruction: String
    let onApply: (_ minutes: Int, _ includeFollowing: Bool) -> Void

    @State private var minutesText = ""
    @State private var direction = Direction.later
    @State private var scope = Scope.current

    private var minutes: Int? {
        guard let value = Int(minutesText), value > 0 else { return nil }
        return min(value, 1_440)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(recipeName)
                        .font(.headline)
                    Text(instruction)
                        .foregroundColor(Theme.subtitle)
                }

                Section("Zeitverschiebung") {
                    TextField("Minuten", text: $minutesText)
                        .keyboardType(.numberPad)

                    Picker("Richtung", selection: $direction) {
                        ForEach(Direction.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Betroffene Schritte") {
                    Picker("Umfang", selection: $scope) {
                        ForEach(Scope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Schritt verschieben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        guard let minutes else { return }
                        onApply(
                            minutes * direction.multiplier,
                            scope.includesFollowing
                        )
                    }
                    .disabled(minutes == nil)
                }
            }
        }
    }
}
