import BakePlannerCore
import SwiftUI

/// A dish being written or changed, as on the iPhone (DishEditorView.swift
/// there): name and servings, the ingredients, the steps with what they
/// wait for, and below the verdict the plan would give. Steps and
/// ingredients open on pages of their own inside the editor.
struct DishEditorView: View {
    let library: CookLibrary
    let onSave: (KitchenDish) -> Void
    @State var dish: KitchenDish
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    init(library: CookLibrary, dish: KitchenDish, onSave: @escaping (KitchenDish) -> Void) {
        self.library = library
        self.onSave = onSave
        _dish = State(initialValue: dish)
    }

    var canSave: Bool {
        !dish.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !dish.tasks.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Gericht", bundle: .module)) {
                    TextField(String(localized: "Name", bundle: .module), text: $dish.name)
                    Stepper(servingsText,
                            value: Binding(get: { dish.servings ?? 0 }, set: { dish.servings = $0 == 0 ? nil : $0 }),
                            in: 0...12)
                }

                Section {
                    ForEach(dish.ingredients, id: \.id) { ingredient in
                        NavigationLink {
                            IngredientEditorView(draft: IngredientDraft(ingredient: ingredient, isNew: false),
                                                 components: dish.components,
                                                 onSave: { keepIngredient($0) },
                                                 onDelete: { removeIngredient(id: ingredient.id) })
                        } label: {
                            IngredientRow(ingredient: ingredient)
                        }
                    }
                    NavigationLink {
                        IngredientEditorView(draft: IngredientDraft(ingredient: nil, isNew: true,
                                                                    component: dish.ingredients.last?.component ?? dish.tasks.last?.component ?? ""),
                                             components: dish.components,
                                             onSave: { keepIngredient($0) },
                                             onDelete: {})
                    } label: {
                        Label(String(localized: "Zutat hinzufügen", bundle: .module), systemImage: "plus")
                    }
                } header: {
                    Text(String(localized: "Zutaten", bundle: .module))
                } footer: {
                    Text(String(localized: "Für die Einkaufsliste; im Schritt wählst Du, was dort in die Hand genommen wird.", bundle: .module))
                }

                Section {
                    ForEach(dish.tasks, id: \.id) { task in
                        NavigationLink {
                            StepEditorView(draft: StepDraft(task: task, isNew: false), components: dish.components,
                                           earlierSteps: earlierSteps(before: task.id), ingredients: dish.ingredients,
                                           onSave: { keepTask($0) },
                                           onDelete: { dish = dish.removingTasks(ids: [task.id]) })
                        } label: {
                            StepSummaryRow(task: task)
                        }
                    }
                    NavigationLink {
                        StepEditorView(draft: StepDraft(task: nil, isNew: true, component: dish.tasks.last?.component ?? ""),
                                       components: dish.components, earlierSteps: dish.tasks, ingredients: dish.ingredients,
                                       onSave: { keepTask($0) }, onDelete: {})
                    } label: {
                        Label(String(localized: "Schritt hinzufügen", bundle: .module), systemImage: "plus")
                    }
                } header: {
                    Text(String(localized: "Schritte", bundle: .module))
                } footer: {
                    Text(String(localized: "Jeder Schritt wartet nur auf die Schritte, die bei ihm angegeben sind; ohne Angabe kann er sofort beginnen.", bundle: .module))
                }

                if !dish.tasks.isEmpty {
                    Section(String(localized: "Plan", bundle: .module)) {
                        planSummary
                    }
                }
            }
            .navigationTitle(dish.name.isEmpty ? String(localized: "Neues Gericht", bundle: .module) : dish.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen", bundle: .module)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sichern", bundle: .module)) {
                        onSave(dish.consistent())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var servingsText: String {
        if let servings = dish.servings {
            return String(localized: "Für \(servings) Personen", bundle: .module)
        }
        return String(localized: "Portionen nicht angegeben", bundle: .module)
    }

    @ViewBuilder
    private var planSummary: some View {
        if let plan = library.plan(for: dish) {
            Text(plan.verdict)
                .fontWeight(.semibold)
                .foregroundStyle(plan.fits ? Palette.good(colorScheme) : Palette.danger(colorScheme))
            Text(plan.reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let failure = library.failure(for: dish) {
            Text(failure)
                .font(.footnote)
                .foregroundStyle(Palette.danger(colorScheme))
        }
    }

    private func keepTask(_ task: KitchenTask) {
        if let index = dish.tasks.firstIndex(where: { $0.id == task.id }) {
            dish.tasks[index] = task
        } else {
            dish.tasks.append(task)
        }
    }

    private func keepIngredient(_ ingredient: KitchenIngredient) {
        if let index = dish.ingredients.firstIndex(where: { $0.id == ingredient.id }) {
            dish.ingredients[index] = ingredient
        } else {
            dish.ingredients.append(ingredient)
        }
    }

    /// An ingredient leaves the dish and every step that named it.
    private func removeIngredient(id: String) {
        dish.ingredients.removeAll { $0.id == id }
        dish.tasks = dish.tasks.map { $0.withIngredientIDs($0.ingredientIDs.filter { $0 != id }) }
    }

    /// The steps a step may wait for: the ones before it in the list.
    private func earlierSteps(before id: String) -> [KitchenTask] {
        guard let index = dish.tasks.firstIndex(where: { $0.id == id }) else { return dish.tasks }
        return Array(dish.tasks[..<index])
    }
}

struct IngredientRow: View {
    let ingredient: KitchenIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ingredient.line(locale: AppSettings.locale))
            if !ingredient.component.isEmpty {
                Text(ingredient.component)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A step as the editor lists it: name, component and its minutes.
struct StepSummaryRow: View {
    let task: KitchenTask

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.name)
            Text(details)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var details: String {
        var parts: [String] = []
        if !task.component.isEmpty { parts.append(task.component) }
        parts.append(String(localized: "Hände \(task.handsMinutes) Min.", bundle: .module))
        if task.unattendedMinutes > 0 {
            parts.append(String(localized: "allein \(task.unattendedMinutes) Min.", bundle: .module))
        }
        switch task.station {
        case .burner: parts.append(String(localized: "Herd", bundle: .module))
        case .oven:
            if let temperature = task.ovenTemperature {
                parts.append(String(localized: "Ofen \(temperature) °C", bundle: .module))
            } else {
                parts.append(String(localized: "Ofen", bundle: .module))
            }
        case nil: break
        }
        return parts.joined(separator: " · ")
    }
}

/// A step while it is edited: every field a KitchenTask has, mutable.
struct StepDraft {
    var id: String
    var isNew: Bool
    var name: String
    var component: String
    var handsMinutes: Int
    var unattendedMinutes: Int
    var hasWindow: Bool
    var windowMinimum: Int
    var windowMaximum: Int
    var station: Int
    var ovenTemperature: Int
    var hasMaxWait: Bool
    var maxWait: Int
    var after: [String]
    var ingredientIDs: [String]

    /// 0 none, 1 burner, 2 oven — a plain number, which Skip's Picker takes.
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
        case .burner: station = 1
        case .oven: station = 2
        case nil: station = 0
        }
        ovenTemperature = task?.ovenTemperature ?? 180
        hasMaxWait = task?.maxWait != nil
        maxWait = task?.maxWait ?? 0
        after = task?.after ?? []
        ingredientIDs = task?.ingredientIDs ?? []
    }

    var task: KitchenTask {
        let kitchenStation: KitchenStation? = station == 1 ? .burner : station == 2 ? .oven : nil
        let window: ClosedRange<Int>? = hasWindow && unattendedMinutes > 0
            ? min(windowMinimum, windowMaximum)...max(windowMinimum, windowMaximum) : nil
        return KitchenTask(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                           component: component.trimmingCharacters(in: .whitespacesAndNewlines),
                           hands: handsMinutes, unattended: unattendedMinutes, station: kitchenStation, after: after,
                           maxWait: hasMaxWait ? maxWait : nil, window: window,
                           ovenTemperature: station == 2 ? ovenTemperature : nil,
                           ingredientIDs: ingredientIDs)
    }
}

/// One step's page.
struct StepEditorView: View {
    @State var draft: StepDraft
    /// Until the cook chooses, a new step follows its component's
    /// previous step.
    @State var dependenciesChosen: Bool
    let components: [String]
    let earlierSteps: [KitchenTask]
    let ingredients: [KitchenIngredient]
    let onSave: (KitchenTask) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    init(draft: StepDraft, components: [String], earlierSteps: [KitchenTask], ingredients: [KitchenIngredient],
         onSave: @escaping (KitchenTask) -> Void, onDelete: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        _dependenciesChosen = State(initialValue: !draft.isNew)
        self.components = components
        self.earlierSteps = earlierSteps
        self.ingredients = ingredients
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private func proposeDependencies() {
        guard !dependenciesChosen else { return }
        let component = draft.component.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = component.isEmpty ? nil : earlierSteps.last { $0.component == component }
        draft.after = previous.map { [$0.id] } ?? []
    }

    /// The last step of every component so far — what the plating waits for.
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
        Form {
            Section(String(localized: "Schritt", bundle: .module)) {
                TextField(String(localized: "Was zu tun ist", bundle: .module), text: $draft.name, axis: .vertical)
                TextField(String(localized: "Komponente", bundle: .module), text: $draft.component)
                if !components.isEmpty {
                    Menu {
                        ForEach(components, id: \.self) { component in
                            Button(component) { draft.component = component }
                        }
                    } label: {
                        Label(String(localized: "Komponente wählen", bundle: .module), systemImage: "chevron.down")
                    }
                }
            }

            Section {
                Stepper(String(localized: "Hände: \(draft.handsMinutes) Min.", bundle: .module),
                        value: $draft.handsMinutes, in: 0...120)
                Stepper(String(localized: "Danach allein: \(draft.unattendedMinutes) Min.", bundle: .module),
                        value: $draft.unattendedMinutes, in: 0...600)
                if draft.unattendedMinutes > 0 {
                    Toggle(String(localized: "Zeitspanne", bundle: .module), isOn: $draft.hasWindow)
                    if draft.hasWindow {
                        Stepper(String(localized: "Mindestens \(draft.windowMinimum) Min.", bundle: .module),
                                value: $draft.windowMinimum, in: 0...600)
                        Stepper(String(localized: "Höchstens \(draft.windowMaximum) Min.", bundle: .module),
                                value: $draft.windowMaximum, in: 0...600)
                    }
                }
            } header: {
                Text(String(localized: "Dauer", bundle: .module))
            } footer: {
                Text(String(localized: "Hände: Minuten, in denen der Koch gebunden ist. Danach allein: kochen, backen, ruhen ohne Koch.", bundle: .module))
            }

            Section(String(localized: "Gerät", bundle: .module)) {
                Picker(String(localized: "Gerät", bundle: .module), selection: $draft.station) {
                    Text(String(localized: "Keins", bundle: .module)).tag(0)
                    Text(String(localized: "Platte", bundle: .module)).tag(1)
                    Text(String(localized: "Ofen", bundle: .module)).tag(2)
                }
                .pickerStyle(.segmented)
                if draft.station == 2 {
                    Stepper(String(localized: "Ofen \(draft.ovenTemperature) °C", bundle: .module),
                            value: $draft.ovenTemperature, in: 50...300, step: 10)
                }
            }

            Section {
                Toggle(String(localized: "Muss bald weitergehen", bundle: .module), isOn: $draft.hasMaxWait)
                if draft.hasMaxWait {
                    Stepper(String(localized: "Liegt höchstens \(draft.maxWait) Min.", bundle: .module),
                            value: $draft.maxWait, in: 0...60)
                }
            } footer: {
                Text(String(localized: "0 Minuten für Wenden nach dem Anbraten, 3 für geruhtes Fleisch, 10 für eine warm gestellte Sauce.", bundle: .module))
            }

            if !ingredients.isEmpty {
                Section {
                    ForEach(ingredients, id: \.id) { ingredient in
                        Button {
                            if let index = draft.ingredientIDs.firstIndex(of: ingredient.id) {
                                draft.ingredientIDs.remove(at: index)
                            } else {
                                draft.ingredientIDs.append(ingredient.id)
                            }
                        } label: {
                            CheckRow(title: ingredient.line(locale: AppSettings.locale), subtitle: ingredient.component,
                                     checked: draft.ingredientIDs.contains(ingredient.id))
                        }
                    }
                } header: {
                    Text(String(localized: "Zutaten dieses Schritts", bundle: .module))
                } footer: {
                    Text(String(localized: "Was in diesem Schritt in die Hand genommen wird; im Kochmodus steht es unter dem Schritt.", bundle: .module))
                }
            }

            if !earlierSteps.isEmpty {
                Section {
                    ForEach(earlierSteps, id: \.id) { step in
                        Button {
                            dependenciesChosen = true
                            if let index = draft.after.firstIndex(of: step.id) {
                                draft.after.remove(at: index)
                            } else {
                                draft.after.append(step.id)
                            }
                        } label: {
                            CheckRow(title: step.name, subtitle: step.component, checked: draft.after.contains(step.id))
                        }
                    }
                    Button(String(localized: "Auf alle Komponenten warten", bundle: .module)) {
                        dependenciesChosen = true
                        draft.after = lastStepOfEachComponent
                    }
                } header: {
                    Text(String(localized: "Wartet auf", bundle: .module))
                } footer: {
                    Text(String(localized: "Ein neuer Schritt folgt dem vorherigen Schritt seiner Komponente, bis Du die Auswahl änderst. Das Anrichten wartet auf den letzten Schritt jeder Komponente.", bundle: .module))
                }
            }

            if !draft.isNew {
                Section {
                    Button(String(localized: "Schritt löschen", bundle: .module), role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { proposeDependencies() }
        .onChange(of: draft.component) { _, _ in proposeDependencies() }
        .navigationTitle(draft.isNew ? String(localized: "Neuer Schritt", bundle: .module) : String(localized: "Schritt", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Fertig", bundle: .module)) {
                    onSave(draft.task)
                    dismiss()
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

/// A row that can be ticked: a title, a smaller line, a checkmark.
struct CheckRow: View {
    let title: String
    let subtitle: String
    let checked: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Palette.title(colorScheme))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if checked {
                Image(systemName: "checkmark")
                    .foregroundStyle(Palette.accentText(colorScheme))
            }
        }
    }
}

/// An ingredient while it is edited, the amount as text.
struct IngredientDraft {
    let id: String
    let isNew: Bool
    var name: String
    var amountText: String
    var unit: String
    var component: String
    var note: String

    init(ingredient: KitchenIngredient?, isNew: Bool, component: String = "") {
        id = ingredient?.id ?? UUID().uuidString
        self.isNew = isNew
        name = ingredient?.name ?? ""
        amountText = ingredient?.amount.map { Self.text(for: $0) } ?? ""
        unit = ingredient?.unit ?? ""
        self.component = ingredient?.component ?? component
        note = ingredient?.note ?? ""
    }

    /// "250", "0,5" – up to two decimals, the comma of the app's language.
    static func text(for amount: Double) -> String {
        // An amount from a file or an old build may be anything; Int() of
        // a huge or infinite value traps.
        guard amount.isFinite, abs(amount) < 1e15 else { return "" }
        let rounded = (amount * 100).rounded() / 100
        var text = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        if AppSettings.locale.decimalSeparator == "," { text = text.replacingOccurrences(of: ".", with: ",") }
        return text
    }

    var amount: Double? {
        let text = amountText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty, let value = Double(text), value.isFinite, value > 0, value <= 1_000_000 else { return nil }
        return value
    }

    var ingredient: KitchenIngredient {
        KitchenIngredient(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount,
                          unit: unit.trimmingCharacters(in: .whitespaces),
                          component: component.trimmingCharacters(in: .whitespacesAndNewlines),
                          note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// One ingredient's page.
struct IngredientEditorView: View {
    @State var draft: IngredientDraft
    let components: [String]
    let onSave: (KitchenIngredient) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss

    /// The units a recipe uses most, one tap each.
    static let units = ["g", "ml", "EL", "TL", "Stück", "Zweig", "Bund", "Prise"]

    init(draft: IngredientDraft, components: [String],
         onSave: @escaping (KitchenIngredient) -> Void, onDelete: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.components = components
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Name", bundle: .module), text: $draft.name)
                TextField(String(localized: "Menge", bundle: .module), text: $draft.amountText)
                    .keyboardType(.decimalPad)
                TextField(String(localized: "Einheit", bundle: .module), text: $draft.unit)
                Menu {
                    ForEach(Self.units, id: \.self) { unit in
                        Button(unit) { draft.unit = unit }
                    }
                    Button(String(localized: "Ohne Einheit", bundle: .module)) { draft.unit = "" }
                } label: {
                    Label(String(localized: "Einheit wählen", bundle: .module), systemImage: "chevron.down")
                }
                TextField(String(localized: "Komponente", bundle: .module), text: $draft.component)
                if !components.isEmpty {
                    Menu {
                        ForEach(components, id: \.self) { component in
                            Button(component) { draft.component = component }
                        }
                    } label: {
                        Label(String(localized: "Komponente wählen", bundle: .module), systemImage: "chevron.down")
                    }
                }
                TextField(String(localized: "Hinweis", bundle: .module), text: $draft.note)
            } header: {
                Text(String(localized: "Zutat", bundle: .module))
            } footer: {
                Text(String(localized: "Menge und Einheit wie im Rezept; ohne Menge für „Salz“ oder „Pfeffer“.", bundle: .module))
            }
            if !draft.isNew {
                Section {
                    Button(String(localized: "Zutat löschen", bundle: .module), role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(draft.isNew ? String(localized: "Neue Zutat", bundle: .module) : String(localized: "Zutat", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Fertig", bundle: .module)) {
                    onSave(draft.ingredient)
                    dismiss()
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
