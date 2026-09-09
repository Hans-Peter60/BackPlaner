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
    
    @EnvironmentObject var model:RecipeModel

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    let date = Date() - 60
    
    let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents = DateComponents(year: GlobalVariables.year! + 1, month: GlobalVariables.month, day: GlobalVariables.day)
        return calendar.date(from:startComponents)!
        ...
        calendar.date(from:endComponents)!
    }()
    
    var nextStepsRequest: FetchRequest<NextStep>
    var nextSteps: FetchedResults<NextStep> { nextStepsRequest.wrappedValue }
    
    @State private var name = ""
    
    init() {
        self.nextStepsRequest = FetchRequest(entity: NextStep.entity(), sortDescriptors: [NSSortDescriptor(key: "date", ascending: true)])
    }

    @State private var confirmationShown = false
    @State private var dateTime          = GlobalVariables.dateTimePicker
    @State private var deleteHaptic      = false
    @State private var shiftSelection: ScheduledStepShiftSelection?
    @State private var showingShiftError = false
    @State private var shiftErrorMessage = ""

    /// The recipe the list is narrowed down to; `nil` shows every planned step.
    @State private var recipeFilter: String?

    /// The distinct recipes that currently have planned steps — the choices of
    /// the filter bar.
    private var plannedRecipeNames: [String] {
        var seen = Set<String>()
        return nextSteps
            .compactMap { seen.insert($0.recipeName).inserted ? $0.recipeName : nil }
            .sorted()
    }

    /// The steps shown in the list: all of them, or only those of the recipe
    /// selected in the filter bar.
    private var visibleSteps: [NextStep] {
        guard let recipeFilter else { return Array(nextSteps) }
        return nextSteps.filter { $0.recipeName == recipeFilter }
    }

    var body: some View {
 
        VStack(spacing: 0) {

        if nextSteps.isEmpty {
            ContentUnavailableView(
                "Keine geplanten Schritte",
                systemImage: "calendar",
                description: Text("Setze einen Reminder in der Backanleitung eines Rezepts.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {

            // Only worth showing once more than one recipe is planned.
            if plannedRecipeNames.count > 1 {
                recipeFilterBar
            }

            if visibleSteps.isEmpty {
                ContentUnavailableView {
                    Label("Keine Schritte für dieses Rezept", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Wähle „Alle“, um alle geplanten Schritte zu sehen.")
                } actions: {
                    Button("Filter aufheben") { recipeFilter = nil }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {

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
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 52, height: 52, alignment: .center)
                    .clipped()
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 6) {

                        HStack(alignment: .top, spacing: 8) {
                            Text(nextStep.recipeName)
                                .font(Theme.bodyFont(15))
                                .foregroundColor(Theme.subtitle)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            Button {
                                beginShifting(nextStep)
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Theme.accentBottom)
                                    .frame(width: 32, height: 32)
                                    .background(.thinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Schritt zeitlich verschieben")
                        }

                        HStack(spacing: 6) {
                            Label {
                                Text(nextStep.date, style: .time)
                            } icon: {
                                Image(systemName: "clock.fill")
                            }
                            .font(Theme.brandFont(15))
                            .foregroundColor(Theme.accentBottom)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.accentBottom.opacity(0.12), in: Capsule())
                            .layoutPriority(1)

                            Text(shortDate(nextStep.date))
                                .font(Theme.bodyFont(15))
                                .foregroundColor(Theme.subtitle)
                                .lineLimit(1)

                            Label(Rational.displayHoursMinutes(nextStep.duration),
                                  systemImage: "hourglass")
                                .font(Theme.bodyFont(13))
                                .foregroundColor(Theme.subtitle)
                                .lineLimit(1)
                                .layoutPriority(1)
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
                )
            }
            // The index set refers to the visible (possibly filtered) rows, not
            // to the full fetch result.
            .onDelete { indexSet in
                guard let index = indexSet.first, visibleSteps.indices.contains(index) else { return }
                let deleteNextStep = visibleSteps[index]

                // Cancel the matching reminder first, so it cannot fire for a step
                // that no longer exists. The delete dialog below does the same for
                // a whole recipe or for every step at once.
                NotificationActions.cancelPendingNotification(for: deleteNextStep)

                self.managedObjectContext.delete(deleteNextStep)

                do {
                    try managedObjectContext.save()
                }
                catch {
                    managedObjectContext.rollback()
                    AppLog.persistence.error("Could not delete next step")
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        }
        .clearScrollBackground()
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
                if let recipeFilter {
                    Button("Nur „\(recipeFilter)“ löschen", role: .destructive) {
                        deleteNextSteps(ofRecipe: recipeFilter)
                    }
                }
                Button("Alle löschen", role: .destructive) {
                    deleteNextSteps(ofRecipe: nil)
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                if let recipeFilter {
                    Text("Entferne nur die geplanten Schritte von „\(recipeFilter)“ samt Erinnerungen – oder alle geplanten Schritte.")
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
        .alert("Verschieben nicht möglich", isPresented: $showingShiftError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shiftErrorMessage)
        }
        // Once the filtered recipe has no planned steps left, fall back to
        // showing everything instead of an empty list.
        .onChange(of: plannedRecipeNames) { _, names in
            if let recipeFilter, !names.contains(recipeFilter) {
                self.recipeFilter = nil
            }
        }
        .onAppear() {  }
    }

    /// Horizontal chips to narrow the list down to a single planned recipe.
    /// Deliberately part of the view instead of the navigation bar: this screen
    /// lives inside a `TabView`, where toolbars of the tab children stay hidden.
    private var recipeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {

                filterChip(Text("Alle"), recipeName: nil)

                ForEach(plannedRecipeNames, id: \.self) { name in
                    filterChip(Text(verbatim: name), recipeName: name)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(_ label: Text, recipeName: String?) -> some View {
        let isSelected = recipeFilter == recipeName

        return Button {
            recipeFilter = recipeName
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

    /// Deletes the planned steps of a single recipe, or all of them when
    /// `recipeName` is `nil`, together with their pending reminders.
    func deleteNextSteps(ofRecipe recipeName: String?) {
        let stepsToDelete = recipeName == nil
            ? Array(nextSteps)
            : nextSteps.filter { $0.recipeName == recipeName }

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

        if recipeName == nil {
            // Clearing the whole plan also drops reminders whose step was
            // already gone — those cannot be matched individually any more.
            UNUserNotificationCenter.current().getPendingNotificationRequests { notificationRequests in
                let identifiers = notificationRequests
                    .map(\.identifier)
                    .filter { $0.contains("Recipe-") }
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }

        recipeFilter = nil
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

private struct ScheduledStepShiftSelection: Identifiable {
    let id: NSManagedObjectID
    let recipeName: String
    let instruction: String
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
                        .foregroundColor(.secondary)
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
