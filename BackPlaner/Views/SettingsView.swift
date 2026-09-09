import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.selectedLanguage) private var selectedLanguage = AppLanguage.system.rawValue
    @AppStorage(AppSettingsKeys.defaultRecipeStorage) private var defaultRecipeStorage = AppSettings.defaultRecipeStorage
    @AppStorage(AppSettingsKeys.defaultServingSize) private var defaultServingSize = AppSettings.defaultServingSize
    @AppStorage(AppSettingsKeys.useDetailView) private var useDetailView = AppSettings.defaultUseDetailView
    @AppStorage(AppSettingsKeys.preheatTime) private var preheatTime = AppSettings.defaultPreheatTime
    @AppStorage(AppSettingsKeys.bakePause) private var bakePause = AppSettings.defaultBakePause
    @AppStorage(AppSettingsKeys.dayStart) private var dayStart = AppSettings.defaultDayStart
    @AppStorage(AppSettingsKeys.dayEnd) private var dayEnd = AppSettings.defaultDayEnd

    @EnvironmentObject private var modelFB: RecipeFBModel

    var body: some View {
        Form {
            Section("Allgemein") {
                Picker("Sprache", selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }

                Picker("Standard-Ablage", selection: $defaultRecipeStorage) {
                    ForEach(RecipeStoragePreference.allCases) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
            }

            Section("Rezepte") {
                // A segmented Picker hides its own label, so show the title as a
                // separate line above the control instead.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Standard-Portionsgröße")
                    Picker("Standard-Portionsgröße", selection: $defaultServingSize) {
                        Text(0.5, format: .number.precision(.fractionLength(1))).tag(1)
                        Text(1.0, format: .number.precision(.fractionLength(1))).tag(2)
                        Text(1.5, format: .number.precision(.fractionLength(1))).tag(3)
                        Text(2.0, format: .number.precision(.fractionLength(1))).tag(4)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Toggle("Detailansicht verwenden", isOn: $useDetailView)
            }

            Section("Backplanung") {
                Stepper(value: $preheatTime, in: 0...120, step: 5) {
                    LabeledContent("Vorheizzeit", value: "\(preheatTime) min")
                }

                Stepper(value: $bakePause, in: 0...120, step: 5) {
                    LabeledContent("Backpause", value: "\(bakePause) min")
                }

                Stepper(value: $dayStart, in: 0...23) {
                    LabeledContent("Tagesbeginn", value: formattedHour(dayStart))
                }
                // The day window flags work steps that fall outside it, so the
                // end has to stay after the beginning.
                .onChange(of: dayStart) { _, newValue in
                    if dayEnd <= newValue {
                        dayEnd = min(newValue + 1, 23)
                    }
                }

                Stepper(value: $dayEnd, in: dayStart...23) {
                    LabeledContent("Tagesende", value: formattedHour(dayEnd))
                }
            }

            accountSection
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Einstellungen")
    }

    /// The account section serves two purposes: it is where an author signs in
    /// so his private cloud recipes are tied to a uid that survives a reinstall,
    /// and it is where a moderator signs in — a moderator is simply an account
    /// whose uid is listed in the Firestore `admins` collection.
    @ViewBuilder
    private var accountSection: some View {
        Section {
            if modelFB.isSignedInWithAccount {
                LabeledContent("Angemeldet als", value: modelFB.accountEmail ?? String(localized: "Apple-Konto"))

                if modelFB.isAdmin {
                    Label("Administrator", systemImage: "checkmark.seal")
                        .foregroundColor(Theme.subtitle)
                }

                Button("Abmelden", role: .destructive) {
                    modelFB.signOutAccount()
                }
            } else {
                AppleSignInView()
            }
        } header: {
            Text("Konto")
        } footer: {
            Text("Die Anmeldung wird für private Cloud-Rezepte benötigt: nur so bleiben sie nach einer Neuinstallation erreichbar. Administratoren verwalten damit gemeldete Rezepte.")
        }
    }

    private func formattedHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(RecipeFBModel())
}
