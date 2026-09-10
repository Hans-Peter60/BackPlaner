//
//  UnitSelectionView.swift
//  BackPlaner
//

import SwiftUI

struct UnitSelectionView: View {
    @Binding var unit: String

    private var selectedUnit: UnitSetFB? {
        UnitSelectionView.matchingUnit(for: unit)
    }

    private var hasInvalidUnit: Bool {
        !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedUnit == nil
    }

    private var title: String {
        if let selectedUnit {
            return selectedUnit.abbreviation
        }

        let cleanedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedUnit.isEmpty ? "-" : cleanedUnit
    }

    var body: some View {
        Menu {
            Button("Keine Einheit") {
                unit = ""
            }

            Divider()

            ForEach(GlobalVariables.unitSets) { unitSet in
                Button(UnitSelectionView.displayName(for: unitSet)) {
                    unit = unitSet.abbreviation
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // An unknown unit used to be signalled by the border turning
                // red and by nothing else, so it did not exist for anyone who
                // cannot tell that red from the ordinary grey (WCAG 1.4.1).
                // The mark carries the same message in shape.
                if hasInvalidUnit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(Theme.danger)
                        // The label below already says it; announcing the icon
                        // as well would repeat it.
                        .accessibilityHidden(true)
                }

                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasInvalidUnit ? Theme.danger : Theme.fieldBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        // VoiceOver was told the unit but never that the app cannot make sense
        // of it. Put it in the label rather than a hint: hints can be switched
        // off, and this one is the difference between a saved recipe that
        // computes and one that does not.
        .accessibilityLabel(hasInvalidUnit ? "Einheit auswählen, unbekannte Einheit"
                                           : "Einheit auswählen")
        .accessibilityValue(title)
    }

    static func matchingUnit(for unit: String) -> UnitSetFB? {
        let cleanedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase

        return GlobalVariables.unitSets.first { unitSet in
            cleanedUnit == unitSet.name.localizedLowercase || cleanedUnit == unitSet.abbreviation.localizedLowercase
        }
    }

    private static func displayName(for unitSet: UnitSetFB) -> String {
        "\(unitSet.abbreviation) - \(unitSet.name)"
    }
}
