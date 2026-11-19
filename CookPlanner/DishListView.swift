//
//  DishListView.swift
//  CookPlanner
//
//  The dishes with their verdict for the current budget and kitchen. Until
//  the app imports dishes of its own, these are the package's samples.
//

import BakePlannerCore
import SwiftUI

struct DishListView: View {

    @AppStorage(CookSettings.budgetKey) private var budget = CookSettings.defaultBudget
    @AppStorage(CookSettings.burnersKey) private var burners = CookSettings.defaultBurners
    @AppStorage(CookSettings.ovensKey) private var ovens = CookSettings.defaultOvens
    @State private var showsSettings = false

    private var plans: [DishPlan] {
        KitchenSampleDishes.all.compactMap { DishPlan(dish: $0, budget: budget, burners: burners, ovens: ovens) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ein Gericht, eine Person, \(budget) Minuten")
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.subtitle)
                        .padding(.horizontal, 4)

                    ForEach(plans, id: \.dish.id) { plan in
                        NavigationLink {
                            DishPlanView(dish: plan.dish)
                        } label: {
                            DishRow(plan: plan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .warmBackground()
            .navigationTitle("Gerichte")
            .toolbar {
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
        }
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
                Text(verbatim: plan.dish.components.joined(separator: " · "))
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                Text(plan.verdict)
                    .font(Theme.bodyFont(14).weight(.semibold))
                    .foregroundColor(plan.fits ? Theme.good : Theme.danger)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundColor(Theme.subtitle)
                .padding(.top, 14)
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
}
