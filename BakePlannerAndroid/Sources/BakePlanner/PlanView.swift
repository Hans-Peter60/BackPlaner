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
    /// 0 "Starten ab", 1 "Fertig bis". Starting now, as on the iPhone.
    @State var anchorSelection = 0
    @State var date = Date()
    // Kept apart from the dialogs' visibility: Android closes a dialog
    // before it runs the chosen button.
    @State var showsOverlap = false
    @State var showsPlanChoice = false
    @State var showsSaved = false
    @State var outcome: AppModel.PlanOutcome = .saved
    @Environment(\.dismiss) var dismiss

    private var plan: BakePlan {
        AppModel.plan(of: recipe, anchor: PlanAnchor(selection: anchorSelection), date: date)
    }

    var body: some View {
        let plan = self.plan
        let issues = model.issues(of: plan)
        let suggestions = model.nightFreeDates(for: plan)
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
                        .font(.caption)
                }
            }

            if !issues.isEmpty || !suggestions.isEmpty {
                Section {
                    ForEach(issues) { issue in
                        Text(verbatim: issue.message)
                            .foregroundStyle(issue.severity == .error ? Color.red : Color.primary)
                    }
                    if !suggestions.isEmpty {
                        Text("So beginnt kein Schritt in der Nacht:")
                            .font(.caption)
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

            Section {
                ForEach(Array(plan.allSteps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: PlanText.dateTime(plan.date(of: step)))
                            .font(.caption)
                            .frame(width: 110, alignment: .leading)
                        Text(verbatim: step.instruction)
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
                save(replacing: false)
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Du kannst den bestehenden Plan ersetzen oder beide behalten – etwa für zwei Backtage.")
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
            }
        }
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

    private func save(replacing: Bool) {
        let plan = self.plan
        Task {
            outcome = await model.putIntoEffect(plan, recipeID: recipe.id, servingScale: scale, replacing: replacing)
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
