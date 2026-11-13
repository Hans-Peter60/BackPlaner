import BakePlannerCore
import SwiftUI

/// "Rezept nach Bäckerprozent anlegen": the formula the baker's way — every
/// ingredient as a share of the flour, the flours together 100 % — plus the
/// flour weight or the dough weight wanted. "Weiter" turns it into a recipe
/// in grams and hands it to the editor, where the steps are added. The
/// arithmetic is BakersFormula in the package.
struct BakersFormulaView: View {
    /// Receives the recipe in grams for the editor.
    let onContinue: (RecipeExportData) -> Void
    @State var name = ""
    @State var formula = BakersFormula.template()
    /// Whether the dough weight is given instead of the flour.
    @State var givesDough = false
    @State var amountText = "500"
    @State var newComponentName = ""
    /// The percent fields as typed, by line: the text is not rewritten
    /// while the person types ("67" must not become "670" when the field
    /// formats itself under the cursor); the formula holds the parsed value.
    @State var percentTexts: [UUID: String] = [:]
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var amount: Double { PantryText.parse(amountText) ?? 0 }

    private var totalFlour: Double {
        givesDough ? formula.totalFlour(forDoughWeight: amount) : amount
    }

    private var canContinue: Bool {
        formula.isComplete && totalFlour > 0
    }

    var body: some View {
        Form {
            Section {
                TextField("Rezeptname", text: $name)
            }

            Section {
                Picker("Vorgabe", selection: $givesDough) {
                    Text("Mehl gesamt").tag(false)
                    Text("Teiggewicht").tag(true)
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField(givesDough ? "Teiggewicht" : "Mehl gesamt", text: $amountText)
                        .foregroundStyle(PantryText.parse(amountText) != nil ? Color.primary : Color.red)
                    Text(verbatim: "g")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(givesDough ? "Mehl gesamt" : "Teiggewicht")
                    Spacer()
                    Text(verbatim: gramsText(givesDough ? totalFlour : formula.doughWeight(forTotalFlour: amount)))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Menge")
            } footer: {
                Text("Alle Prozente beziehen sich auf das gesamte Mehl des Rezepts – alle Mehle zusammen sind 100 Prozent. Gib die Mehlmenge oder das gewünschte Teiggewicht vor, die Gramm rechnet die App.")
            }

            ForEach(formula.components, id: \.id) { component in
                componentSection(component)
            }

            Section {
                HStack {
                    TextField("Neue Komponente", text: $newComponentName)
                    Button("Hinzufügen") {
                        let trimmed = newComponentName.trimmingCharacters(in: .whitespaces)
                        formula.components.append(BakersFormula.Component(
                            name: trimmed, lines: [BakersFormula.Line(name: "", percent: 0)]))
                        newComponentName = ""
                    }
                    .disabled(newComponentName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                // What still keeps the formula from becoming a recipe.
                if !formula.isComplete {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(formula.issues.enumerated()), id: \.offset) { _, issue in
                            Text(verbatim: issueText(issue))
                                .foregroundStyle(Palette.warning(colorScheme))
                        }
                    }
                }
            }
        }
        .navigationTitle("Nach Bäckerprozent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Weiter") {
                    let recipe = formula.makeRecipe(name: name, totalFlour: totalFlour)
                    onContinue(RecipeExportData(recipeFB: recipe, imageData: nil))
                    dismiss()
                }
                .disabled(!canContinue)
            }
        }
    }

    /// One component: its name, its lines, a new line, and the component's
    /// removal while there is another.
    private func componentSection(_ component: BakersFormula.Component) -> some View {
        Section {
            HStack {
                Text("Komponente")
                TextField("Name der Komponente", text: Binding(
                    get: { component.name },
                    set: { value in update(component.id) { $0.name = value } }
                ))
                .multilineTextAlignment(.trailing)
            }
            ForEach(component.lines, id: \.id) { line in
                lineRow(line, in: component.id)
            }
            .onDelete { offsets in
                update(component.id) { target in
                    for index in offsets.sorted(by: >) where index < target.lines.count {
                        target.lines.remove(at: index)
                    }
                }
            }
            Button("Zutat hinzufügen") {
                update(component.id) { $0.lines.append(BakersFormula.Line(name: "", percent: 0)) }
            }
            if formula.components.count > 1 {
                Button("Komponente entfernen", role: .destructive) {
                    formula.components.removeAll { $0.id == component.id }
                }
            }
        } header: {
            Text(verbatim: component.name.isEmpty ? " " : component.name)
        }
    }

    /// Name, "Mehl" where the line counts as flour, the share and the grams.
    private func lineRow(_ line: BakersFormula.Line, in componentID: UUID) -> some View {
        HStack(spacing: 8) {
            TextField("Zutat", text: Binding(
                get: { line.name },
                set: { value in updateLine(line.id, in: componentID) { $0.name = value } }
            ))
            if line.isFlour {
                Text("Mehl")
                    .font(AppFont.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.accent(colorScheme).opacity(0.18)))
                    .foregroundStyle(Palette.accentText(colorScheme))
            }
            TextField("", text: Binding(
                get: { percentTexts[line.id] ?? PantryText.number(line.percent) },
                set: { value in
                    percentTexts[line.id] = value
                    updateLine(line.id, in: componentID) { $0.percent = PantryText.parse(value) ?? 0 }
                }
            ))
            .multilineTextAlignment(.trailing)
            .foregroundStyle(PantryText.parse(percentTexts[line.id] ?? "0") != nil ? Color.primary : Color.red)
            .frame(width: 60)
            Text(verbatim: "%")
                .foregroundStyle(.secondary)
            Text(verbatim: gramsText(formula.grams(of: line, totalFlour: totalFlour)))
                .font(AppFont.subheadline)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func update(_ componentID: UUID, _ change: (inout BakersFormula.Component) -> Void) {
        guard let index = formula.components.firstIndex(where: { $0.id == componentID }) else { return }
        change(&formula.components[index])
    }

    private func updateLine(_ lineID: UUID, in componentID: UUID, _ change: (inout BakersFormula.Line) -> Void) {
        update(componentID) { component in
            guard let index = component.lines.firstIndex(where: { $0.id == lineID }) else { return }
            change(&component.lines[index])
        }
    }

    private func gramsText(_ grams: Double) -> String {
        grams.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(AppSettings.locale)) + " g"
    }

    private func issueText(_ issue: BakersFormula.Issue) -> String {
        switch issue {
        case .noFlour:
            return String(localized: "Keine Zutat wird als Mehl erkannt – nenne das Mehl beim Namen, etwa „Weizenmehl 550“.", bundle: .module)
        case .flourNot100(let percent):
            let shown = percent.formatted(.number.precision(.fractionLength(0...1)).locale(AppSettings.locale))
            return String(localized: "Die Mehle ergeben \(shown) Prozent statt 100.", bundle: .module)
        case .nonPositive(let name):
            return String(localized: "„\(name)“ hat noch keinen Anteil.", bundle: .module)
        case .noLines:
            return String(localized: "Noch keine Zutaten.", bundle: .module)
        }
    }
}
