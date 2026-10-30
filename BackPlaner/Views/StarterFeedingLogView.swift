//
//  StarterFeedingLogView.swift
//  BackPlaner
//
//  The "+ Fütterung" tab of a recipe that refreshes on a schedule: a quick
//  form to log how a feeding went, and the feedings logged so far. The
//  feeding ratio itself is never typed in here — it is read off the
//  recipe's own ingredients (see StarterFeedingRatio), so it can never
//  drift out of sync with the recipe that defines it.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct StarterFeedingLogView: View {

    var recipeId: NSManagedObjectID?

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var model: RecipeModel

    @State private var recipeName = ""
    @State private var ratio: StarterFeedingRatio.Ratio?
    @State private var entries = [StarterFeedingLog]()

    @State private var date = Date()
    @State private var peakMinutesText = ""
    @State private var floatTest = FloatTestChoice.notChecked
    @State private var note = ""

    private enum Field: Hashable {
        case peakMinutes, note
    }

    // A keyboard toolbar never shows inside the recipe TabView (see
    // BakeHistoryFactsFormSection), so the "Fertig" button sits in the row
    // while the field is focused instead.
    @FocusState private var focusedField: Field?

    private enum FloatTestChoice: Hashable, CaseIterable {
        case notChecked, passed, failed

        var title: LocalizedStringKey {
            switch self {
            case .notChecked: return "Nicht geprüft"
            case .passed:     return "Schwimmt"
            case .failed:     return "Schwimmt nicht"
            }
        }

        var floatTestPassed: Bool? {
            switch self {
            case .notChecked: return nil
            case .passed:      return true
            case .failed:      return false
            }
        }

        init(_ floatTestPassed: Bool?) {
            switch floatTestPassed {
            case .none:        self = .notChecked
            case .some(true):  self = .passed
            case .some(false): self = .failed
            }
        }
    }

    var dateFormat: DateFormat = DateFormat()

    var body: some View {
        Form {
            Text(recipeName)
                .font(Theme.brandFont(18))

            if let ratio {
                Section {
                    Text("Anstellgut \(ratio.starter) : Mehl \(ratio.flour) : Wasser \(ratio.water)")
                        .font(Theme.bodyFont(16))
                } header: {
                    Text("Fütterungsverhältnis")
                } footer: {
                    Text("Aus dem Rezept übernommen — hier nicht änderbar.")
                }
            }

            Section {
                DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .environment(\.locale, AppSettings.locale)

                HStack {
                    Text("Reifezeit bis zum Höhepunkt")
                    Spacer()
                    TextField("", text: $peakMinutesText, prompt: Text(verbatim: "–"))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 50, maxWidth: 70)
                        .focused($focusedField, equals: .peakMinutes)
                        .accessibilityLabel(Text("Reifezeit bis zum Höhepunkt"))
                    Text("Min")
                        .foregroundColor(Theme.subtitle)
                    if focusedField == .peakMinutes {
                        Button("Fertig") { focusedField = nil }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Picker("Schwimmtest", selection: $floatTest) {
                    ForEach(FloatTestChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Notiz", text: $note, prompt: Text("Beobachtungen, Geruch, Konsistenz …"), axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .note)

                    if focusedField == .note {
                        Button("Fertig") { focusedField = nil }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Neue Fütterung erfassen")
            }

            IconActionButton(systemImage: "checkmark", style: .primary, accessibilityLabel: "Fütterung speichern", title: "Speichern", controlSize: .regular) {
                save()
            }
            .padding(.trailing)

            if !entries.isEmpty {
                Section {
                    ForEach(entries, id: \.objectID) { entry in
                        entryRow(entry)
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("Bisherige Fütterungen")
                }
            }
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Anstellgut-Tagebuch")
        .onAppear(perform: load)
    }

    private func entryRow(_ entry: StarterFeedingLog) -> some View {
        let facts = entry.facts
        return VStack(alignment: .leading, spacing: 4) {
            Text(dateFormat.calculateDate(dT: entry.date))
                .font(Theme.brandFont(15))

            HStack(spacing: 10) {
                if let peakMinutes = facts.peakMinutes {
                    Label(BakeHistoryFacts.durationText(peakMinutes), systemImage: "hourglass")
                }
                if let floatTestPassed = facts.floatTestPassed {
                    Label(floatTestPassed ? "Schwimmt" : "Schwimmt nicht",
                          systemImage: floatTestPassed ? "checkmark.circle" : "xmark.circle")
                }
            }
            .font(Theme.bodyFont(13))
            .foregroundColor(Theme.subtitle)

            if !facts.note.isEmpty {
                Text(facts.note)
                    .font(Theme.bodyFont(14))
            }
        }
    }

    private func load() {
        guard
            let objectId = recipeId,
            let recipe   = model.fetchRecipe(for: objectId, context: viewContext)
        else {
            return
        }
        recipeName = recipe.name
        ratio      = StarterFeedingRatio.ratio(for: recipe)
        entries    = recipe.starterFeedingLogsArray
    }

    private func save() {
        guard
            let objectId = recipeId,
            let recipe   = model.fetchRecipe(for: objectId, context: viewContext)
        else {
            return
        }

        let entry = StarterFeedingLog(context: viewContext)
        entry.id   = UUID()
        entry.date = date
        entry.facts = StarterFeedingFacts(peakMinutes: StarterFeedingFacts.parseMinutes(peakMinutesText),
                                           floatTestPassed: floatTest.floatTestPassed,
                                           note: note)
        recipe.addToStarterFeedingLogs(entry)

        do {
            try viewContext.save()
        } catch {
            return
        }

        date             = Date()
        peakMinutesText  = ""
        floatTest        = .notChecked
        note             = ""
        focusedField     = nil
        entries          = recipe.starterFeedingLogsArray
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            viewContext.delete(entries[index])
        }
        do {
            try viewContext.save()
        } catch {
            return
        }
        if let objectId = recipeId, let recipe = model.fetchRecipe(for: objectId, context: viewContext) {
            entries = recipe.starterFeedingLogsArray
        }
    }
}
