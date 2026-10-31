import BakePlannerCore
import SwiftUI

/// The starter feeding diary of a recipe that feeds a starter: the feeding
/// ratio taken from the recipe, a button that records a feeding, and the
/// feedings so far — as the iPhone's "Anstellgut-Tagebuch" tab.
struct StarterFeedingSection: View {
    let model: AppModel
    let recipeID: String
    let ratio: StarterFeedingRatio.Ratio?
    @State var feedings: [StoredStarterFeeding] = []
    @State var addsFeeding = false
    /// The feeding waiting for the user to confirm its removal. Kept apart
    /// from the dialog's visibility: Android closes the dialog before it
    /// runs the chosen button.
    @State var feedingToDelete: StoredStarterFeeding?
    @State var confirmsDeletion = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anstellgut-Tagebuch")
                .font(.title3)
                .bold()
                .foregroundStyle(Palette.accent(colorScheme))

            if let ratio {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fütterungsverhältnis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Anstellgut \(ratio.starter) : Mehl \(ratio.flour) : Wasser \(ratio.water)")
                    Text("Aus dem Rezept übernommen — hier nicht änderbar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                addsFeeding = true
            } label: {
                Label("Neue Fütterung erfassen", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .tint(Palette.accent(colorScheme))

            if !feedings.isEmpty {
                Text("Bisherige Fütterungen")
                    .font(.headline)
                ForEach(feedings, id: \.id) { feeding in
                    HStack(alignment: .top) {
                        StarterFeedingRow(feeding: feeding)
                        Spacer()
                        Button {
                            feedingToDelete = feeding
                            confirmsDeletion = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .task {
            feedings = model.feedings(ofRecipe: recipeID)
        }
        .sheet(isPresented: $addsFeeding) {
            NavigationStack {
                StarterFeedingEditor { date, facts in
                    if model.addFeeding(toRecipe: recipeID, date: date, facts: facts) {
                        feedings = model.feedings(ofRecipe: recipeID)
                    }
                }
            }
        }
        .alert("Fütterung löschen?", isPresented: $confirmsDeletion) {
            Button("Löschen", role: .destructive) {
                if let feeding = feedingToDelete {
                    model.deleteFeeding(id: feeding.id)
                    feedings = model.feedings(ofRecipe: recipeID)
                }
                feedingToDelete = nil
            }
            Button("Abbrechen", role: .cancel) {
                feedingToDelete = nil
            }
        } message: {
            if let feeding = feedingToDelete {
                Text(verbatim: BakeHistoryText.date(feeding.date))
            }
        }
    }
}

/// One feeding: when, how long to the peak, the float test, the note.
struct StarterFeedingRow: View {
    let feeding: StoredStarterFeeding

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: BakeHistoryText.date(feeding.date))
                .bold()
            HStack(spacing: 10) {
                if let peakMinutes = feeding.facts.peakMinutes {
                    Text(verbatim: "⏳ " + BakeHistoryFacts.durationText(peakMinutes))
                }
                if let passed = feeding.facts.floatTestPassed {
                    Text(passed ? LocalizedStringKey("Schwimmt") : LocalizedStringKey("Schwimmt nicht"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !feeding.facts.note.isEmpty {
                Text(verbatim: feeding.facts.note)
            }
        }
    }
}

/// Records a feeding: when, the time to the peak, the float test and a
/// note, as on the iPhone. A feeding is never changed afterwards, only
/// removed.
struct StarterFeedingEditor: View {
    let onSave: (Date, StarterFeedingFacts) -> Void
    @State var date = Date()
    @State var peakText = ""
    /// 0 not checked, 1 floats, 2 does not float.
    @State var floatTest = 0
    @State var note = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                DatePicker("Datum", selection: $date, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Text("Reifezeit bis zum Höhepunkt")
                    Spacer()
                    TextField("", text: $peakText)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                    Text(verbatim: "min")
                        .foregroundStyle(.secondary)
                }
                Picker("Schwimmtest", selection: $floatTest) {
                    Text("Nicht geprüft").tag(0)
                    Text("Schwimmt").tag(1)
                    Text("Schwimmt nicht").tag(2)
                }
                TextField("Notiz", text: $note, prompt: Text("Beobachtungen, Geruch, Konsistenz …"), axis: .vertical)
            } header: {
                Text("Neue Fütterung erfassen")
            }
        }
        .navigationTitle("Anstellgut-Tagebuch")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    onSave(date, StarterFeedingFacts(peakMinutes: StarterFeedingFacts.parseMinutes(peakText),
                                                     floatTestPassed: floatTest == 0 ? nil : floatTest == 1,
                                                     note: note))
                    dismiss()
                }
            }
        }
    }
}
