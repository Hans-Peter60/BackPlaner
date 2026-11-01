import BakePlannerCore
import Foundation
import SwiftUI

/// The units the user added, kept as JSON text in the app's settings file
/// under the iPhone's key, and handed to the package's unit table at start
/// (GlobalVariables.customUnitSets), so amounts in those units weigh what
/// they should in the totals, the percentages and the shopping list.
enum CustomUnitFile {
    static let key = "units.custom"

    static var units: [CustomUnit] {
        guard let text = SettingsFile.value(forKey: key) as? String else { return [] }
        return CustomUnits.decode(Data(text.utf8))
    }

    static func save(_ units: [CustomUnit]) {
        if let data = CustomUnits.encode(units), let text = String(data: data, encoding: .utf8) {
            SettingsFile.set(text, forKey: key)
        }
    }

    /// Makes the package read the user's units; called once at start, after
    /// the settings file is restored.
    static func install() {
        GlobalVariables.setCustomUnitSets { CustomUnits.unitSets(CustomUnitFile.units) }
    }
}

/// Lets the user add units the app does not ship with — "Becher", or the
/// "cups" an imported recipe brings in — each with the conversion the app
/// needs to weigh it. The iPhone's CustomUnitsView.
struct CustomUnitsView: View {
    @State var units = CustomUnitFile.units
    @State var name = ""
    @State var abbreviation = ""
    @State var factorText = ""
    @State var base = UnitBase.milliliter
    /// Why the last unit was not added. Kept apart from the alert's
    /// visibility: Android closes the alert before it runs its button.
    @State var refusal: CustomUnitError?
    @State var showsRefusal = false

    var body: some View {
        Form {
            if units.isEmpty {
                Section {
                    Text("Du hast noch keine eigene Einheit angelegt. Die mitgelieferten Einheiten stehen in der Auswahlliste immer zur Verfügung.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(units) { unit in
                        HStack {
                            Text(verbatim: "\(unit.abbreviation) – \(unit.name)")
                            Spacer()
                            describe(unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        units.remove(atOffsets: offsets)
                        CustomUnitFile.save(units)
                    }
                } header: {
                    Text("Eigene Einheiten")
                }
            }

            Section {
                TextField("Name", text: $name)
                TextField("Kürzel", text: $abbreviation)
                Picker("Gemessen in", selection: $base) {
                    ForEach(UnitBase.allCases) { unitBase in
                        baseTitle(unitBase).tag(unitBase)
                    }
                }
                // A counted unit has no factor to ask for — it is always 1.
                if base != .piece {
                    TextField("Umrechnung", text: $factorText)
                        .keyboardType(.decimalPad)
                }
                factorExplanation(base)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Einheit hinzufügen") {
                    addUnit()
                }
            } header: {
                Text("Neue Einheit")
            }

            Section {
                Text("Eine Einheit sagt der App, wie sie eine Menge in ein Gewicht umrechnet. Davon leben die Gesamtzutaten, die Bäckerprozente und die Einkaufsliste. Deshalb braucht auch eine eigene Einheit eine Umrechnung — ohne sie würde „2 Becher Mehl“ als 2 Gramm zählen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Eigene Einheiten")
        .alert("Einheit nicht angelegt", isPresented: $showsRefusal) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            if let refusal {
                refusalText(refusal)
            }
        }
    }

    private func addUnit() {
        let factor = Double(factorText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        do {
            let unit = try CustomUnits.validated(name: name, abbreviation: abbreviation, factor: factor,
                                                 base: base, existing: units)
            units.append(unit)
            CustomUnitFile.save(units)
            name = ""
            abbreviation = ""
            factorText = ""
        } catch let error as CustomUnitError {
            refusal = error
            showsRefusal = true
        } catch {
            logger.error("could not add a unit: \(error)")
        }
    }

    /// The conversion in words, e.g. "250 ml" or "gezählt".
    private func describe(_ unit: CustomUnit) -> Text {
        switch unit.base {
        case .piece:
            return Text("gezählt")
        case .gram, .milliliter:
            let amount = unit.factor.formatted(.number.precision(.fractionLength(0...2)))
            return Text(verbatim: "\(amount) \(unit.baseUnit)")
        }
    }

    // The wording lives with the view, as on the iPhone (AppSettings.swift).
    private func baseTitle(_ base: UnitBase) -> Text {
        switch base {
        case .gram: return Text("Gramm")
        case .milliliter: return Text("Milliliter")
        case .piece: return Text("Stück")
        }
    }

    private func factorExplanation(_ base: UnitBase) -> Text {
        switch base {
        case .gram: return Text("Wie viel Gramm eine Einheit wiegt. Ein Pfund wären 500.")
        case .milliliter: return Text("Wie viele Milliliter eine Einheit enthält. Ein Becher wären etwa 250. Das Gewicht rechnet die App je Zutat daraus.")
        case .piece: return Text("Wird gezählt, nicht gewogen. Die Umrechnung bleibt 1.")
        }
    }

    private func refusalText(_ error: CustomUnitError) -> Text {
        switch error {
        case .missingName: return Text("Bitte einen Namen angeben.")
        case .missingAbbreviation: return Text("Bitte ein Kürzel angeben.")
        case .factorNotPositive: return Text("Die Umrechnung muss größer als 0 sein.")
        case .abbreviationTaken(let abbreviation): return Text("Das Kürzel „\(abbreviation)“ ist schon vergeben.")
        }
    }
}
