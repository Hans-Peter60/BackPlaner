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
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(hasInvalidUnit ? Color.red : Color.secondary.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Einheit auswählen")
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
