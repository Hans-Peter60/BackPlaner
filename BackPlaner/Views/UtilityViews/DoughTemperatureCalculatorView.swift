//
//  DoughTemperatureCalculatorView.swift
//  BackPlaner
//
//  Works out the water temperature a straight dough or one with a
//  preferment needs to hit a target dough temperature, by the baker's
//  standard "Desired Dough Temperature" method (see DoughTemperatureCalculator).
//

import BakePlannerCore
import SwiftUI

struct DoughTemperatureCalculatorView: View {

    @State private var targetDoughTemperature = 24
    @State private var roomTemperature = 21
    @State private var flourAtRoomTemperature = true
    @State private var flourTemperature = 21
    @State private var usesPreferment = false
    @State private var prefermentTemperature = 21

    /// Calibrated per mixer/kneading style; see the footer below.
    @AppStorage(AppSettingsKeys.doughFrictionFactor) private var frictionFactor = AppSettings.defaultFrictionFactor

    private var effectiveFlourTemperature: Int {
        flourAtRoomTemperature ? roomTemperature : flourTemperature
    }

    private var waterTemperature: Int {
        DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: targetDoughTemperature,
            roomTemperature: roomTemperature,
            flourTemperature: effectiveFlourTemperature,
            frictionFactor: frictionFactor,
            prefermentTemperature: usesPreferment ? prefermentTemperature : nil
        )
    }

    private var feasibilityMessage: LocalizedStringKey? {
        switch DoughTemperatureCalculator.feasibility(ofWaterTemperature: waterTemperature) {
        case .ok:      return nil
        case .tooCold: return "Kälter als Eiswasser – mit diesen Werten kaum erreichbar."
        case .tooHot:  return "Sehr heißes Wasser nötig – prüfe Ziel- und Reibungswärme."
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text("Schüttwassertemperatur")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)

                    Text("\(waterTemperature) °C")
                        .font(Theme.brandFont(40))
                        .foregroundColor(Theme.cardTitle)

                    if let feasibilityMessage {
                        Label {
                            Text(feasibilityMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.footnote)
                        .foregroundColor(Theme.warning)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            Section("Zieltemperatur") {
                Stepper(value: $targetDoughTemperature, in: 15...32) {
                    LabeledContent("Teig", value: "\(targetDoughTemperature) °C")
                }
            }

            Section("Zutaten") {
                Stepper(value: $roomTemperature, in: 0...35) {
                    LabeledContent("Raum", value: "\(roomTemperature) °C")
                }

                Toggle("Mehl hat Raumtemperatur", isOn: $flourAtRoomTemperature)

                if !flourAtRoomTemperature {
                    Stepper(value: $flourTemperature, in: -10...35) {
                        LabeledContent("Mehl", value: "\(flourTemperature) °C")
                    }
                }

                Toggle("Mit Sauerteig oder Vorteig", isOn: $usesPreferment)

                if usesPreferment {
                    Stepper(value: $prefermentTemperature, in: 0...35) {
                        LabeledContent("Sauerteig/Vorteig", value: "\(prefermentTemperature) °C")
                    }
                }
            }

            Section {
                Stepper(value: $frictionFactor,
                        in: AppSettings.minimumFrictionFactor...AppSettings.maximumFrictionFactor) {
                    LabeledContent("Reibungswärme", value: "\(frictionFactor) °C")
                }
            } footer: {
                Text("Die Wärme, die der Teig zusätzlich beim Kneten aufnimmt. Vergleiche nach dem Kneten die gemessene Teigtemperatur mit der Zieltemperatur und passe den Wert entsprechend an – einmal kalibriert, gilt er für jedes Rezept.")
            }
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Teigtemperatur")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DoughTemperatureCalculatorView()
    }
}
