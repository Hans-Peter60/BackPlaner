//
//  DishEditorView.swift
//  CookPlanner
//
//  A dish typed in or corrected by the cook: name, servings, the steps in
//  order, and the plan that follows every change. Each step opens its own
//  sheet. Dependencies are taken as they stand — an imported dish brings
//  them complete; a new step typed in gets its component's previous step
//  proposed, which the cook may change.
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
    @FocusState private var nameFocused: Bool
    let onSave: (KitchenDish) -> Void

    init(dish: KitchenDish, onSave: @escaping (KitchenDish) -> Void) {
        _dish = State(initialValue: dish)
        self.onSave = onSave
    }

    private var canSave: Bool {
        !dish.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !dish.tasks.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gericht") {
                    TextField("Name", text: $dish.name, axis: .vertical)
                        .focused($nameFocused)
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
                    HStack {
                        Text("Schritte")
                        Spacer()
                        if dish.tasks.count > 1 {
                            EditButton()
                                .font(.footnote)
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text("Jeder Schritt wartet nur auf die Schritte, die bei ihm angegeben sind; ohne Angabe kann er sofort beginnen.")
                }

                if !dish.tasks.isEmpty {
                    Section("Plan") {
                        planSummary
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(dish.name.isEmpty ? Text("Neues Gericht") : Text(verbatim: dish.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { nameFocused = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        onSave(dish)
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
        // A swipe must not throw an imported or half-typed dish away;
        // "Abbrechen" is the way out.
        .interactiveDismissDisabled()
    }

    /// The steps a step may wait for: the ones before it in the list.
    private func earlierSteps(for draft: StepDraft) -> [KitchenTask] {
        guard let index = dish.tasks.firstIndex(where: { $0.id == draft.id }) else { return dish.tasks }
        return Array(dish.tasks[..<index])
    }

    @ViewBuilder
    private var planSummary: some View {
        if let plan = DishPlan(dish: dish, budget: budget, burners: burners, ovens: ovens) {
            Text(plan.verdict)
                .font(Theme.bodyFont(17).weight(.semibold))
                .foregroundColor(plan.fits ? Theme.good : Theme.danger)
            Text(plan.reason)
                .font(.footnote)
                .foregroundColor(.secondary)
            if !plan.fits, plan.schedule.limit != .hands,
               let fit = try? KitchenScheduler.fit(dish.tasks, kitchen: plan.schedule.kitchen, budget: budget),
               !fit.shortenings.isEmpty {
                ForEach(fit.shortenings, id: \.task) { cut in
                    if let task = dish.tasks.first(where: { $0.id == cut.task }) {
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
            if !task.component.isEmpty {
                Text(verbatim: task.component)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            // The numbers on a line of their own, as plain icon–text pairs:
            // Labels dropped their titles here, and a long component name
            // used to squeeze "20–25" into one character a line.
            HStack(spacing: 10) {
                pair("hand.raised", "\(task.handsMinutes)")
                if task.unattendedMinutes > 0 {
                    if let window = task.unattendedWindow {
                        pair("hourglass", "\(window.lowerBound)–\(window.upperBound)")
                    } else {
                        pair("hourglass", "\(task.unattendedMinutes)")
                    }
                }
                if let symbol = task.stationSymbol {
                    Image(systemName: symbol)
                }
                if let temperature = task.ovenTemperature {
                    Text(verbatim: "\(temperature) °C")
                }
                if let wait = task.maxWait {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                        if wait == 0 {
                            Text("sofort")
                        } else {
                            Text(verbatim: "\(wait)")
                        }
                    }
                }
            }
            .lineLimit(1)
            .font(.footnote)
            .foregroundColor(.secondary)
        }
    }

    private func pair(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(verbatim: value)
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
    /// Whether the cook has chosen the dependencies; until then a new
    /// step follows its component's previous step.
    @State private var dependenciesChosen: Bool
    @FocusState private var focusedField: Field?
    let components: [String]

    private enum Field { case name, component }
    let earlierSteps: [KitchenTask]
    let onSave: (KitchenTask) -> Void
    let onDelete: () -> Void

    init(draft: StepDraft, components: [String], earlierSteps: [KitchenTask],
         onSave: @escaping (KitchenTask) -> Void, onDelete: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        _dependenciesChosen = State(initialValue: !draft.isNew)
        self.components = components
        self.earlierSteps = earlierSteps
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// Until the cook chooses, a new step follows the previous step of
    /// its component (none for the first step of a component).
    private func proposeDependencies() {
        guard !dependenciesChosen else { return }
        let component = draft.component.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = component.isEmpty ? nil : earlierSteps.last { $0.component == component }
        draft.after = previous.map { [$0.id] } ?? []
    }

    /// The last step of every component so far, in order of appearance —
    /// what the plating waits for.
    private var lastStepOfEachComponent: [String] {
        var order = [String]()
        var last = [String: String]()
        for step in earlierSteps {
            if last[step.component] == nil { order.append(step.component) }
            last[step.component] = step.id
        }
        return order.compactMap { last[$0] }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schritt") {
                    TextField("Was zu tun ist", text: $draft.name, axis: .vertical)
                        .focused($focusedField, equals: .name)
                    HStack {
                        TextField("Komponente", text: $draft.component)
                            .focused($focusedField, equals: .component)
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
                            .onChange(of: draft.hasWindow) { _, on in
                                // Around the minutes given, not around nothing.
                                if on {
                                    draft.windowMinimum = max(0, draft.unattendedMinutes - 2)
                                    draft.windowMaximum = draft.unattendedMinutes + 3
                                }
                            }
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
                                dependenciesChosen = true
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
                                // The whole row takes the tap, not just the text.
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            dependenciesChosen = true
                            draft.after = lastStepOfEachComponent
                        } label: {
                            Label("Auf alle Komponenten warten", systemImage: "checkmark.circle")
                        }
                    } header: {
                        Text("Wartet auf")
                    } footer: {
                        Text("Ein neuer Schritt folgt dem vorherigen Schritt seiner Komponente, bis Du die Auswahl änderst. Das Anrichten wartet auf den letzten Schritt jeder Komponente.")
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
            .scrollDismissesKeyboard(.interactively)
            .onAppear(perform: proposeDependencies)
            .onChange(of: draft.component) { proposeDependencies() }
            .navigationTitle(draft.isNew ? "Neuer Schritt" : "Schritt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focusedField = nil }
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
