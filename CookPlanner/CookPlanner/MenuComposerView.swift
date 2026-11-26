//
//  MenuComposerView.swift
//  CookPlanner
//
//  Several dishes into one plan: pick the courses, name them, say how long
//  the guests eat between them, see whether it fits, keep it as a dish.
//  The combining is KitchenMenu's; what comes out is an ordinary dish in
//  "Meine Gerichte", planned and cooked like any other.
//

import BakePlannerCore
import SwiftUI

struct MenuComposerView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(DishLibrary.self) private var library
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens

    /// One course as it is being put together; the dish may still be unpicked.
    private struct Course: Identifiable {
        let id = UUID()
        var dishID: String?
        var label: String
        var gapAfterMinutes: Int
    }

    @State private var name = ""
    @State private var courses: [Course] = [Course(dishID: nil, label: "", gapAfterMinutes: 20),
                                            Course(dishID: nil, label: "", gapAfterMinutes: 0)]
    /// Called with the combined dish once it is kept.
    let onSave: (KitchenDish) -> Void

    private var choices: [KitchenDish] { library.dishes.filter { $0.source != .menu } + KitchenSampleDishes.all }

    private func dish(_ id: String?) -> KitchenDish? {
        id.flatMap { id in choices.first { $0.id == id } }
    }

    /// The default names: starter, main, dessert for up to three courses,
    /// numbered beyond that.
    private func defaultLabel(_ index: Int) -> String {
        switch (courses.count, index) {
        case (2, 0), (3, 0): return String(localized: "Vorspeise")
        case (2, 1), (3, 1): return String(localized: "Hauptgang")
        case (3, 2): return String(localized: "Dessert")
        default: return String(localized: "\(index + 1). Gang")
        }
    }

    private func label(_ index: Int) -> String {
        let typed = courses[index].label.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? defaultLabel(index) : typed
    }

    /// The menu as a dish, once every course has one.
    private var combined: KitchenDish? {
        var picked = [KitchenMenuCourse]()
        for (index, course) in courses.enumerated() {
            guard let dish = dish(course.dishID) else { return nil }
            picked.append(KitchenMenuCourse(dish: dish.scaled(by: CookSettings.portionFactor(for: dish.id)),
                                            label: label(index), gapAfterMinutes: course.gapAfterMinutes))
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return KitchenMenu.combined(name: title.isEmpty ? String(localized: "Menü") : title, courses: picked) { course in
            String(localized: "\(course) servieren")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name des Menüs", text: $name)
                        .submitLabel(.done)
                } footer: {
                    Text("Die Gänge werden zu einem Plan: Die Vorspeise kommt so viele Minuten vor dem Hauptgang auf den Tisch, wie Du angibst, und der Hauptgang wird gekocht, während die Gäste essen.")
                }
                ForEach(Array(courses.indices), id: \.self) { index in
                    Section {
                        Picker("Gericht", selection: $courses[index].dishID) {
                            Text("Bitte wählen").tag(String?.none)
                            ForEach(choices) { dish in
                                Text(verbatim: dish.name).tag(Optional(dish.id))
                            }
                        }
                        TextField(defaultLabel(index), text: $courses[index].label)
                        if index < courses.count - 1 {
                            Stepper(value: $courses[index].gapAfterMinutes, in: 0...90, step: 5) {
                                if courses[index].gapAfterMinutes == 0 {
                                    Text("Zusammen mit dem nächsten Gang")
                                } else {
                                    Text("\(courses[index].gapAfterMinutes) Min. bis zum nächsten Gang")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(verbatim: label(index))
                            Spacer()
                            if courses.count > 2 {
                                Button("Entfernen", role: .destructive) { courses.remove(at: index) }
                                    .font(.footnote)
                            }
                        }
                    }
                }
                if courses.count < 5 {
                    Section {
                        Button {
                            courses.append(Course(dishID: nil, label: "", gapAfterMinutes: 0))
                        } label: {
                            Label("Gang hinzufügen", systemImage: "plus.circle")
                        }
                    }
                }
                Section("Plan") {
                    if let combined {
                        if let plan = DishPlan(dish: combined, budget: budget, burners: burners, ovens: ovens) {
                            Text(plan.verdict)
                                .font(Theme.bodyFont(17).weight(.semibold))
                                .foregroundColor(plan.fits ? Theme.good : Theme.danger)
                            Text(plan.reason)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Text("\(combined.tasks.count) Schritte, \(combined.ingredients.count) Zutaten, Plan \(plan.schedule.makespan) Min.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        } else if let reason = DishPlan.failure(dish: combined, budget: budget, burners: burners, ovens: ovens) {
                            Text(reason)
                                .font(.footnote)
                                .foregroundColor(Theme.danger)
                        }
                    } else {
                        Text("Wähle für jeden Gang ein Gericht.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Menü zusammenstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if let combined {
                            onSave(combined)
                            dismiss()
                        }
                    }
                    .disabled(combined == nil)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
