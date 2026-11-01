import BakePlannerCore
import Foundation
import SwiftUI

/// The settings the Android app uses, as on the iPhone: the default serving
/// size (the amount the rhythm plans), the dough yields of one's starters,
/// and the planning values (preheat time, bake pause, ovens, day window).
///
/// Stored in UserDefaults.standard under the iPhone's keys, because that is
/// where the package reads them (AppSettings.stored…). Not through
/// @AppStorage: on Android it keeps its values on the Kotlin side, which the
/// package's Foundation may not see.
struct SettingsView: View {
    @State var servingSize = AppSettings.storedServingSize
    @State var starterDoughYield = AppSettings.storedStarterDoughYield
    @State var lievitoMadreDoughYield = AppSettings.storedLievitoMadreDoughYield
    @State var preheatTime = AppSettings.storedPreheatTime
    @State var bakePause = AppSettings.storedBakePause
    @State var ovenCount = AppSettings.storedOvenCount
    @State var dayStart = AppSettings.storedDayStart
    @State var dayEnd = AppSettings.storedDayEnd
    /// Whether Firebase answers (step 11b), nil while it is being asked.
    @State var connection: PublicRecipeService.ConnectionCheck?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Standard-Portionsgröße")
                    // Stored as halves: 1 is 0.5, 4 is 2.0, as on the iPhone.
                    Picker("Standard-Portionsgröße", selection: $servingSize) {
                        ForEach([1, 2, 3, 4], id: \.self) { halves in
                            Text(verbatim: (Double(halves) / 2).formatted(.number.precision(.fractionLength(1))))
                                .tag(halves)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Split an amount of starter into flour and water when the
                // recipe does not state the starter's TA.
                Stepper(value: $starterDoughYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield,
                        step: 5) {
                    valueRow("Anstellgut", value: "TA \(starterDoughYield)")
                }
                Stepper(value: $lievitoMadreDoughYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield,
                        step: 5) {
                    valueRow("Lievito Madre", value: "TA \(lievitoMadreDoughYield)")
                }
            } header: {
                Text("Rezepte")
            }

            Section {
                Stepper(value: $preheatTime, in: 0...120, step: 5) {
                    valueRow("Vorheizzeit", value: "\(preheatTime) min")
                }
                Stepper(value: $bakePause, in: 0...120, step: 5) {
                    valueRow("Backpause", value: "\(bakePause) min")
                }
                // With more than one oven the plan check lets as many bakes
                // run side by side.
                Stepper(value: $ovenCount, in: 1...AppSettings.maximumOvenCount) {
                    valueRow("Backöfen", value: String(ovenCount))
                }
                Stepper(value: $dayStart, in: 0...23) {
                    valueRow("Tagesbeginn", value: Self.hourText(dayStart))
                }
                Stepper(value: $dayEnd, in: dayStart...23) {
                    valueRow("Tagesende", value: Self.hourText(dayEnd))
                }
            } header: {
                Text("Backplanung")
            }

            // For now only shows whether the public recipes can be reached.
            Section {
                switch connection {
                case nil:
                    Text("Verbindung wird geprüft …")
                case .recipes(let count):
                    valueRow("Anzahl", value: String(count))
                case .failed(let message):
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                case .unavailable:
                    Text(verbatim: "–")
                }
            } header: {
                Text("Öffentliche Rezepte")
            }
        }
        .task {
            connection = await PublicRecipeService.checkConnection()
        }
        .navigationTitle("Einstellungen")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
        .onChange(of: servingSize) { _, value in store(value, AppSettingsKeys.defaultServingSize) }
        .onChange(of: starterDoughYield) { _, value in store(value, AppSettingsKeys.starterDoughYield) }
        .onChange(of: lievitoMadreDoughYield) { _, value in store(value, AppSettingsKeys.lievitoMadreDoughYield) }
        .onChange(of: preheatTime) { _, value in store(value, AppSettingsKeys.preheatTime) }
        .onChange(of: bakePause) { _, value in store(value, AppSettingsKeys.bakePause) }
        .onChange(of: ovenCount) { _, value in store(value, AppSettingsKeys.ovenCount) }
        .onChange(of: dayStart) { _, value in
            store(value, AppSettingsKeys.dayStart)
            // The day window flags steps outside it, so the end stays after
            // the beginning — the iPhone's rule.
            if dayEnd <= value {
                dayEnd = min(value + 1, 23)
            }
        }
        .onChange(of: dayEnd) { _, value in store(value, AppSettingsKeys.dayEnd) }
    }

    private func valueRow(_ title: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(.secondary)
        }
    }

    private func store(_ value: Int, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// "06:00", as on the iPhone.
    static func hourText(_ hour: Int) -> String {
        (hour < 10 ? "0" : "") + String(hour) + ":00"
    }
}
