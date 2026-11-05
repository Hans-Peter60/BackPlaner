//
//  StarterFeedingLogView.swift
//  BackPlaner
//
//  The "+ Fütterung" tab of a recipe that refreshes on a schedule: a quick
//  form to log how a feeding went, and the feedings logged so far. A
//  feeding the plan wrote (planning a starter feeds it, see
//  BakePlanScheduler) has no result yet; tapping it enters one. The
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
    @State private var roomText = ""
    @State private var floatTest = FloatTestChoice.notChecked
    @State private var note = ""
    /// Today's room temperature for the ripeness estimate; starts at the
    /// last one noted in the diary.
    @State private var todayTemperature = 22
    /// The feeding whose result is being entered.
    @State private var entryForResult: StarterFeedingLog?

    private enum Field: Hashable {
        case peakMinutes, roomTemperature, note
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

    /// When the starter is ripe at today's temperature, from the feedings
    /// that noted both peak time and temperature (StarterRipeness).
    private var ripenessEstimate: StarterRipeness.Estimate? {
        StarterRipeness.estimate(from: StarterFeedingFacts.ripenessObservations(entries.map(\.facts)),
                                 at: Double(todayTemperature))
    }

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
                if let estimate = ripenessEstimate {
                    Text("Bei \(BakeHistoryFacts.temperatureText(Double(todayTemperature), locale: AppSettings.locale)) reif nach etwa \(BakeHistoryFacts.durationText(estimate.minutes))")
                        .font(Theme.bodyFont(16))
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        if estimate.observations == 1 {
                            Text("aus einer Fütterung")
                        } else {
                            Text("aus \(estimate.observations) Fütterungen")
                        }
                    }
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                } else {
                    Text("Trage bei Deinen Fütterungen Reifezeit und Raumtemperatur ein, dann schätzt die App, wann das Anstellgut bei der heutigen Temperatur reif ist.")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Stepper(value: $todayTemperature, in: 10...35) {
                    LabeledContent("Raumtemperatur heute", value: "\(todayTemperature) °C")
                }
            } header: {
                Text("Reifezeit-Schätzung")
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

                HStack {
                    Text("Raumtemperatur")
                    Spacer()
                    TextField("", text: $roomText, prompt: Text(verbatim: "–"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 50, maxWidth: 70)
                        .focused($focusedField, equals: .roomTemperature)
                        .accessibilityLabel(Text("Raumtemperatur"))
                    Text("°C")
                        .foregroundColor(Theme.subtitle)
                    if focusedField == .roomTemperature {
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
                        Button {
                            entryForResult = entry
                        } label: {
                            entryRow(entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Ergebnis eintragen")
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
        .sheet(item: $entryForResult) { entry in
            ResultSheet(entry: entry) {
                load()
            }
            .environment(\.managedObjectContext, viewContext)
        }
    }

    private func entryRow(_ entry: StarterFeedingLog) -> some View {
        let facts = entry.facts
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(dateFormat.calculateDate(dT: entry.date))
                    .font(Theme.brandFont(15))
                if entry.date > Date() {
                    Text("geplant")
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.subtitle)
                }
            }

            HStack(spacing: 10) {
                if let peakMinutes = facts.peakMinutes {
                    Label(BakeHistoryFacts.durationText(peakMinutes), systemImage: "hourglass")
                }
                if let roomTemperature = facts.roomTemperature {
                    Label(BakeHistoryFacts.temperatureText(roomTemperature, locale: AppSettings.locale),
                          systemImage: "thermometer.medium")
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
        if let lastNoted = entries.compactMap(\.facts.roomTemperature).first {
            todayTemperature = Int(lastNoted.rounded())
        }
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
                                           note: note,
                                           roomTemperature: BakeHistoryFacts.parseTemperature(roomText))
        recipe.addToStarterFeedingLogs(entry)

        do {
            try viewContext.save()
        } catch {
            return
        }

        date             = Date()
        peakMinutesText  = ""
        roomText         = ""
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

// MARK: - Result

extension StarterFeedingLogView {

    /// Enters how a feeding went — time to peak, float test, note — into an
    /// existing entry, typically the one the plan wrote at its start. The
    /// date stays.
    private struct ResultSheet: View {
        @ObservedObject var entry: StarterFeedingLog
        var onSave: () -> Void

        @Environment(\.dismiss) private var dismiss
        @Environment(\.managedObjectContext) private var viewContext

        @State private var peakMinutesText: String
        @State private var roomText: String
        @State private var floatTest: FloatTestChoice
        @State private var note: String

        private let dateFormat = DateFormat()

        init(entry: StarterFeedingLog, onSave: @escaping () -> Void) {
            self.entry = entry
            self.onSave = onSave
            let facts = entry.facts
            _peakMinutesText = State(initialValue: StarterFeedingFacts.minutesInput(facts.peakMinutes))
            _roomText = State(initialValue: BakeHistoryFacts.temperatureInput(facts.roomTemperature))
            _floatTest = State(initialValue: FloatTestChoice(facts.floatTestPassed))
            _note = State(initialValue: facts.note)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Text(dateFormat.calculateDate(dT: entry.date))
                            .font(Theme.brandFont(16))

                        HStack {
                            Text("Reifezeit bis zum Höhepunkt")
                            Spacer()
                            TextField("", text: $peakMinutesText, prompt: Text(verbatim: "–"))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 50, maxWidth: 70)
                                .accessibilityLabel(Text("Reifezeit bis zum Höhepunkt"))
                            Text("Min")
                                .foregroundColor(Theme.subtitle)
                        }

                        HStack {
                            Text("Raumtemperatur")
                            Spacer()
                            TextField("", text: $roomText, prompt: Text(verbatim: "–"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 50, maxWidth: 70)
                                .accessibilityLabel(Text("Raumtemperatur"))
                            Text("°C")
                                .foregroundColor(Theme.subtitle)
                        }

                        Picker("Schwimmtest", selection: $floatTest) {
                            ForEach(FloatTestChoice.allCases, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }

                        TextField("Notiz", text: $note, prompt: Text("Beobachtungen, Geruch, Konsistenz …"), axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .clearScrollBackground()
                .warmBackground()
                .navigationTitle(Text("Ergebnis eintragen"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { save() }
                    }
                }
            }
        }

        private func save() {
            entry.facts = StarterFeedingFacts(peakMinutes: StarterFeedingFacts.parseMinutes(peakMinutesText),
                                              floatTestPassed: floatTest.floatTestPassed,
                                              note: note,
                                              roomTemperature: BakeHistoryFacts.parseTemperature(roomText))
            do {
                try viewContext.save()
            } catch {
                AppLog.persistence.error("The feeding's result could not be saved: \(error.localizedDescription)")
            }
            onSave()
            dismiss()
        }
    }
}
