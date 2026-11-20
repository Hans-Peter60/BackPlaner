//
//  DishListView.swift
//  CookPlanner
//
//  The cook's own dishes and the examples, each with its verdict for the
//  current budget and kitchen. Own dishes can be edited and removed; an
//  example can be taken as a template.
//

import BakePlannerCore
import SwiftUI

struct DishListView: View {

    @Environment(DishLibrary.self) private var library
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens
    @State private var showsSettings = false
    /// The dish being edited in the sheet: a new one, a copy of an
    /// example, or one of the cook's own.
    @State private var editing: KitchenDish?
    @State private var importing = false
    /// The dish the import handed over, opened in the editor once the
    /// import sheet is gone.
    @State private var pendingImport: KitchenDish?

    private func plan(for dish: KitchenDish) -> DishPlan? {
        DishPlan(dish: dish, budget: budget, burners: burners, ovens: ovens)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Ein Gericht, eine Person, \(budget) Minuten")
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.subtitle)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !library.dishes.isEmpty {
                    Section {
                        ForEach(library.dishes) { dish in
                            row(dish)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        library.delete(id: dish.id)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        editing = dish
                                    } label: {
                                        Label("Bearbeiten", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        library.delete(id: dish.id)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        sectionTitle("Meine Gerichte")
                    }
                }
                Section {
                    ForEach(KitchenSampleDishes.all) { dish in
                        row(dish)
                            .contextMenu {
                                Button {
                                    editing = dish.duplicate()
                                } label: {
                                    Label("Als Vorlage übernehmen", systemImage: "doc.on.doc")
                                }
                            }
                    }
                } header: {
                    sectionTitle("Beispiele")
                }
            }
            .listStyle(.plain)
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle("Gerichte")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editing = KitchenDish(name: "", createdAt: .now, tasks: [])
                        } label: {
                            Label("Neues Gericht", systemImage: "square.and.pencil")
                        }
                        Button {
                            importing = true
                        } label: {
                            Label("Aus Text importieren", systemImage: "text.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Hinzufügen")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showsSettings) {
                KitchenSettingsView()
            }
            .sheet(item: $editing) { dish in
                DishEditorView(dish: dish) { saved in
                    library.save(saved)
                }
            }
            .sheet(isPresented: $importing, onDismiss: {
                if let pendingImport {
                    editing = pendingImport
                    self.pendingImport = nil
                }
            }) {
                DishTextImportView { dish in
                    pendingImport = dish
                }
            }
            .alert("Speichern fehlgeschlagen",
                   isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(library.lastError ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(_ dish: KitchenDish) -> some View {
        if let plan = plan(for: dish) {
            NavigationLink {
                DishPlanView(dish: dish)
            } label: {
                DishRow(plan: plan)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.brandFont(18))
            .foregroundColor(Theme.title)
            .textCase(nil)
    }
}

private struct DishRow: View {
    let plan: DishPlan

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: plan.fits ? "checkmark.circle" : "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: plan.dish.name)
                    .font(Theme.bodyFont(16).weight(.semibold))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if !plan.dish.components.isEmpty {
                    Text(verbatim: plan.dish.components.joined(separator: " · "))
                        .font(Theme.bodyFont(13))
                        .foregroundColor(Theme.subtitle)
                }
                if plan.dish.tasks.isEmpty {
                    Text("Noch keine Schritte")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                        .padding(.top, 2)
                } else {
                    Text(plan.verdict)
                        .font(Theme.bodyFont(14).weight(.semibold))
                        .foregroundColor(plan.fits ? Theme.good : Theme.danger)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// Budget and kitchen, the few numbers a plan depends on.
struct KitchenSettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens

    var body: some View {
        NavigationStack {
            Form {
                Section("Zeitbudget") {
                    Stepper(value: $budget, in: 10...180, step: 5) {
                        Text("\(budget) Minuten")
                    }
                }
                Section("Küche") {
                    Stepper(value: $burners, in: 1...8) {
                        Text("Platten: \(burners)")
                    }
                    Stepper(value: $ovens, in: 0...3) {
                        Text("Öfen: \(ovens)")
                    }
                    Text("Die Öfen sind vorgeheizt, wenn die Uhr startet.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DishListView()
        .environment(DishLibrary(store: InMemoryKitchenDishStore()))
}
