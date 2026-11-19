//
//  DishEditorView.swift
//  CookPlanner
//
//  A dish typed in or corrected by the cook: name, servings, the steps in
//  order, and the plan that follows every change. Each step opens its own
//  sheet. Dependencies left empty are filled by the defaults when the
//  dish is kept: a step follows its component's previous step, the last
//  step waits for every component.
//

import BakePlannerCore
import SwiftUI

struct DishEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens

    @State private var dish: KitchenDish
    @State private var editingStep: StepDraft?
    let onSave: (KitchenDish) -> Void

    init(dish: KitchenDish, onSave: @escaping (KitchenDish) -> Void) {
        _dish = State(initialValue: dish)
        self.onSave = onSave
    }

    /// The dish as it would be kept: dependencies filled in.
    private var resolved: KitchenDish {
        var result = dish
        result.tasks = KitchenDishDefaults.withDependencies(dish.tasks)
        return result
    }

    private var canSave: Bool {
        !dish.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !dish.tasks.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gericht") {
                    TextField("Name", text: $dish.name, axis: .vertical)
                    Stepper(value: Binding(get: { dish.servings ?? 0 }, set: { dish.servings = $0 == 0 ? nil : $0 }),
                            in: 0...12) {
                        if let servings = dish.servings {
                            Text("Für \(servings) Personen")
                        } else {
                            Text("Portionen nicht angegeben")
                        }
                    }
                }

                Section {
                    ForEach(dish.tasks) { task in
                        Button {
                            editingStep = StepDraft(task: task, isNew: false)
                        } label: {
                            StepSummaryRow(task: task)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in dish.tasks.remove(atOffsets: offsets) }
                    .onMove { source, destination in dish.tasks.move(fromOffsets: source, toOffset: destination) }
                    Button {
                        editingStep = StepDraft(task: nil, isNew: true, component: dish.tasks.last?.component ?? "")
                    } label: {
                        Label("Schritt hinzufügen", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Schritte")
                } footer: {
                    Text("Ohne Angabe folgt ein Schritt dem vorherigen Schritt seiner Komponente; der letzte Schritt wartet auf alle Komponenten.")
                }

                if !dish.tasks.isEmpty {
                    Section("Plan") {
                        planSummary
                    }
                }
            }
            .navigationTitle(dish.name.isEmpty ? Text("Neues Gericht") : Text(verbatim: dish.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        onSave(resolved)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(item: $editingStep) { draft in
                StepEditorView(draft: draft, components: dish.components, earlierSteps: earlierSteps(for: draft)) { task in
                    if let index = dish.tasks.firstIndex(where: { $0.id == task.id }) {
                        dish.tasks[index] = task
                    } else {
                        dish.tasks.append(task)
                    }
                } onDelete: {
                    dish.tasks.removeAll { $0.id == draft.id }
                }
            }
        }
    }

    /// The steps a step may wait for: the ones before it in the list.
    private func earlierSteps(for draft: StepDraft) -> [KitchenTask] {
        guard let index = dish.tasks.firstIndex(where: { $0.id == draft.id }) else { return dish.tasks }
        return Array(dish.tasks[..<index])
    }

    @ViewBuilder
    private var planSummary: some View {
        if let plan = DishPlan(dish: resolved, budget: budget, burners: burners, ovens: ovens) {
            Text(plan.verdict)
                .font(Theme.bodyFont(17).weight(.semibold))
                .foregroundColor(plan.fits ? Theme.good : Theme.danger)
            Text(plan.reason)
                .font(.footnote)
                .foregroundColor(.secondary)
            if !plan.fits, plan.schedule.limit != .hands,
               let fit = try? KitchenScheduler.fit(resolved.tasks, kitchen: plan.schedule.kitchen, budget: budget),
               !fit.shortenings.isEmpty {
                ForEach(fit.shortenings, id: \.task) { cut in
                    if let task = resolved.tasks.first(where: { $0.id == cut.task }) {
                        Text("\(task.name): \(cut.to) statt \(cut.from) Minuten")
                            .font(.footnote)
                    }
                }
            }
        } else {
            Text("Der Plan geht nicht auf: Ein Schritt wartet auf sich selbst, oder ein Gerät fehlt in der Küche.")
                .font(.footnote)
                .foregroundColor(Theme.danger)
        }
    }
}

/// A step as the list shows it: name, component, hands, unattended, station.
private struct StepSummaryRow: View {
    let task: KitchenTask

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: task.name)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if !task.component.isEmpty {
                    Text(verbatim: task.component)
                }
                Label("\(task.handsMinutes)", systemImage: "hand.raised")
                if task.unattendedMinutes > 0 {
                    if let window = task.unattendedWindow {
                        Label("\(window.lowerBound)–\(window.upperBound)", systemImage: "hourglass")
                    } else {
                        Label("\(task.unattendedMinutes)", systemImage: "hourglass")
                    }
                }
                if let symbol = task.stationSymbol {
                    Image(systemName: symbol)
                }
                if let temperature = task.ovenTemperature {
                    Text(verbatim: "\(temperature) °C")
                }
                if let wait = task.maxWait {
                    Label("\(wait)", systemImage: "timer")
                }
            }
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }
}

/// A step while it is edited: every field a KitchenTask has, mutable.
struct StepDraft: Identifiable {
    var id: String
    var isNew: Bool
    var name: String
    var component: String
    var handsMinutes: Int
    var unattendedMinutes: Int
    var hasWindow: Bool
    var windowMinimum: Int
    var windowMaximum: Int
    var station: StationChoice
    var ovenTemperature: Int
    var hasMaxWait: Bool
    var maxWait: Int
    var after: [String]

    enum StationChoice: String, CaseIterable, Identifiable {
        case none, burner, oven
        var id: String { rawValue }
    }

    init(task: KitchenTask?, isNew: Bool, component: String = "") {
        id = task?.id ?? UUID().uuidString
        self.isNew = isNew
        name = task?.name ?? ""
        self.component = task?.component ?? component
        handsMinutes = task?.handsMinutes ?? 2
        unattendedMinutes = task?.unattendedMinutes ?? 0
        hasWindow = task?.unattendedWindow != nil
        windowMinimum = task?.unattendedWindow?.lowerBound ?? max(0, (task?.unattendedMinutes ?? 0) - 2)
        windowMaximum = task?.unattendedWindow?.upperBound ?? (task?.unattendedMinutes ?? 0) + 3
        switch task?.station {
        case .burner: station = .burner
        case .oven: station = .oven
        case nil: station = .none
        }
        ovenTemperature = task?.ovenTemperature ?? 180
        hasMaxWait = task?.maxWait != nil
        maxWait = task?.maxWait ?? 0
        after = task?.after ?? []
    }

    var task: KitchenTask {
        let kitchenStation: KitchenStation?
        switch station {
        case .none: kitchenStation = nil
        case .burner: kitchenStation = .burner
        case .oven: kitchenStation = .oven
        }
        return KitchenTask(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                           component: component.trimmingCharacters(in: .whitespacesAndNewlines),
                           hands: handsMinutes, unattended: unattendedMinutes, station: kitchenStation, after: after,
                           maxWait: hasMaxWait ? maxWait : nil,
                           window: hasWindow && unattendedMinutes > 0 ? min(windowMinimum, windowMaximum)...max(windowMinimum, windowMaximum) : nil,
                           ovenTemperature: station == .oven ? ovenTemperature : nil)
    }
}

/// One step's sheet.
struct StepEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var draft: StepDraft
    let components: [String]
    let earlierSteps: [KitchenTask]
    let onSave: (KitchenTask) -> Void
    let onDelete: () -> Void

    init(draft: StepDraft, components: [String], earlierSteps: [KitchenTask],
         onSave: @escaping (KitchenTask) -> Void, onDelete: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.components = components
        self.earlierSteps = earlierSteps
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schritt") {
                    TextField("Was zu tun ist", text: $draft.name, axis: .vertical)
                    HStack {
                        TextField("Komponente", text: $draft.component)
                        if !components.isEmpty {
                            Menu {
                                ForEach(components, id: \.self) { component in
                                    Button(component) { draft.component = component }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .accessibilityLabel("Komponente wählen")
                        }
                    }
                }

                Section {
                    Stepper(value: $draft.handsMinutes, in: 0...120) {
                        Text("Hände: \(draft.handsMinutes) Min.")
                    }
                    Stepper(value: $draft.unattendedMinutes, in: 0...600) {
                        Text("Danach allein: \(draft.unattendedMinutes) Min.")
                    }
                    if draft.unattendedMinutes > 0 {
                        Toggle("Zeitspanne", isOn: $draft.hasWindow)
                        if draft.hasWindow {
                            Stepper(value: $draft.windowMinimum, in: 0...600) {
                                Text("Mindestens \(draft.windowMinimum) Min.")
                            }
                            Stepper(value: $draft.windowMaximum, in: 0...600) {
                                Text("Höchstens \(draft.windowMaximum) Min.")
                            }
                        }
                    }
                } header: {
                    Text("Dauer")
                } footer: {
                    Text("Hände: Minuten, in denen der Koch gebunden ist. Danach allein: kochen, backen, ruhen ohne Koch.")
                }

                Section("Gerät") {
                    Picker("Gerät", selection: $draft.station) {
                        Text("Keins").tag(StepDraft.StationChoice.none)
                        Text("Platte").tag(StepDraft.StationChoice.burner)
                        Text("Ofen").tag(StepDraft.StationChoice.oven)
                    }
                    .pickerStyle(.segmented)
                    if draft.station == .oven {
                        Stepper(value: $draft.ovenTemperature, in: 50...300, step: 10) {
                            Text("Ofen \(draft.ovenTemperature) °C")
                        }
                    }
                }

                Section {
                    Toggle("Muss bald weitergehen", isOn: $draft.hasMaxWait)
                    if draft.hasMaxWait {
                        Stepper(value: $draft.maxWait, in: 0...60) {
                            Text("Liegt höchstens \(draft.maxWait) Min.")
                        }
                    }
                } footer: {
                    Text("0 Minuten für Wenden nach dem Anbraten, 3 für geruhtes Fleisch, 10 für eine warm gestellte Sauce.")
                }

                if !earlierSteps.isEmpty {
                    Section {
                        ForEach(earlierSteps) { step in
                            Button {
                                if let index = draft.after.firstIndex(of: step.id) {
                                    draft.after.remove(at: index)
                                } else {
                                    draft.after.append(step.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: step.name)
                                        if !step.component.isEmpty {
                                            Text(verbatim: step.component)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if draft.after.contains(step.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.accentText)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Wartet auf")
                    } footer: {
                        Text("Ohne Auswahl folgt der Schritt dem vorherigen Schritt seiner Komponente.")
                    }
                }

                if !draft.isNew {
                    Section {
                        Button("Schritt löschen", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.isNew ? "Neuer Schritt" : "Schritt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onSave(draft.task)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
