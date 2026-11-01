import BakePlannerCore
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The settings the Android app uses, as on the iPhone: the default serving
/// size (the amount the rhythm plans), the dough yields of one's starters,
/// and the planning values (preheat time, bake pause, ovens, day window).
///
/// Stored under the iPhone's keys in the app's own settings file, which the
/// package reads through AppSettings.settingsReader (SettingsFile): on
/// Android, UserDefaults was neither shared with the package nor kept
/// after a restart. Not through @AppStorage either, for the same reason.
struct SettingsView: View {
    let model: AppModel
    @State var servingSize = AppSettings.storedServingSize
    @State var starterDoughYield = AppSettings.storedStarterDoughYield
    @State var lievitoMadreDoughYield = AppSettings.storedLievitoMadreDoughYield
    @State var preheatTime = AppSettings.storedPreheatTime
    @State var bakePause = AppSettings.storedBakePause
    @State var ovenCount = AppSettings.storedOvenCount
    @State var dayStart = AppSettings.storedDayStart
    @State var dayEnd = AppSettings.storedDayEnd
    /// "Meine Anstellgut-TAs" as typed: the quick picks of the starter TA
    /// calculator, kept as text under the iPhone's key.
    @State var starterPresetsText = SettingsFile.value(forKey: AppSettingsKeys.starterDoughYieldPresets) as? String
        ?? AppSettings.defaultStarterDoughYieldPresets
    @Environment(\.dismiss) var dismiss
    @Environment(\.locale) var locale
    /// An account change is under way (the browser may be open).
    @State var changesAccount = false
    @State var confirmsAccountDeletion = false
    /// What the last account change brought, for the alert. Kept apart
    /// from the alert's visibility: Android closes it before its button.
    @State var accountOutcome: AccountOutcome?
    @State var showsAccountOutcome = false

    enum AccountOutcome: Equatable {
        case signInFailed(String)
        case signedOut
        case signOutFailed(String)
        case deleted
        case deletionFailed(String)
    }

    var body: some View {
        Form {
            // The app's language is chosen in Android's settings (Android 13
            // and later, locales_config.xml); this row leads there.
            Section {
                Button {
                    Task {
                        _ = await UIApplication.shared.open(Self.languageSettingsURL)
                    }
                } label: {
                    HStack {
                        Text("Sprache")
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text(verbatim: Self.languageName(of: locale))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Allgemein")
            } footer: {
                Text("Öffnet die Android-Einstellungen, in denen Du die Sprache von BakePlanner unabhängig von der Gerätesprache wählst.")
            }

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
                Toggle("Bäckerprozente anzeigen", isOn: Binding(get: { model.showsBakersPercentages },
                                                               set: { model.showsBakersPercentages = $0 }))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Meine Anstellgut-TAs")
                        Spacer()
                        TextField("Meine Anstellgut-TAs", text: $starterPresetsText)
                            .frame(width: 160)
                    }
                    Text("Durch Komma getrennt; als Schnellwahl beim Anpassen der Anstellgut-TA.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

            // Which recipes the list shows, as the iPhone's filter chips.
            Section {
                Toggle("Lokal", isOn: Binding(get: { model.showsLocalRecipes },
                                              set: { model.showsLocalRecipes = $0 }))
                Toggle("Öffentlich", isOn: Binding(get: { model.showsPublicRecipes },
                                                   set: { model.showsPublicRecipes = $0 }))
            } header: {
                Text("Rezeptliste")
            }

            accountSection

            // The cloud AI reads recipes only with the user's consent, given
            // in the import; here it is shown and taken back, as on the iPhone.
            Section {
                NavigationLink {
                    RecipeAIPrivacyView(model: model)
                } label: {
                    valueRow("KI-Analyse beim Rezeptimport",
                             localizedValue: model.allowsCloudAnalysis ? "Zugelassen" : "Nur lokal")
                }
                if model.allowsCloudAnalysis {
                    Button("Einwilligung zur Cloud-KI widerrufen", role: .destructive) {
                        model.allowsCloudAnalysis = false
                        model.usesCloudAnalysis = false
                    }
                }
            } header: {
                Text("Datenschutz & KI")
            } footer: {
                Text("Die Cloud-KI wird nur nach Deiner ausdrücklichen Einwilligung verwendet. Eine lokale Analyse bleibt immer verfügbar.")
            }

            // Takes back what was blocked or reported on this device, as on
            // the iPhone.
            Section {
                valueRow("Blockierte Autoren", value: String(model.blockedAuthors.count))
                Button("Blockierungen aufheben") {
                    model.blockedAuthors = []
                }
                .disabled(model.blockedAuthors.isEmpty)
                valueRow("Von Dir gemeldete Rezepte", value: String(model.reportedRecipeIDs.count))
                Button("Meldungen auf diesem Gerät zurücknehmen") {
                    model.reportedRecipeIDs = []
                }
                .disabled(model.reportedRecipeIDs.isEmpty)
            } header: {
                Text("Moderation")
            } footer: {
                Text("Blockierte Autoren erscheinen sofort wieder in der Rezept-Datenbank. Ein gemeldetes Rezept bleibt dagegen für alle Nutzer ausgeblendet, bis ein Administrator es geprüft hat — das Zurücknehmen wirkt erst danach.")
            }

            // The website's pages, in the app's language, in the browser —
            // as on the iPhone. Privacy policy and legal notice have to be
            // reachable from inside the app.
            Section {
                helpLink("Benutzerhandbuch", url: HelpLinks.manual)
                helpLink("Hilfe und Kontakt", url: HelpLinks.support)
                helpLink("Datenschutzerklärung", url: HelpLinks.privacy)
                helpLink("Impressum", url: HelpLinks.imprint)
            } header: {
                Text("Hilfe")
            } footer: {
                Text("Öffnet die Seiten im Browser.")
            }
        }
        .navigationTitle("Einstellungen")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
        .task {
            await model.refreshAccount()
        }
        .confirmationDialog("Konto endgültig löschen?", isPresented: $confirmsAccountDeletion,
                            titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) {
                changeAccount {
                    await model.deleteAccount().map { AccountOutcome.deletionFailed($0) } ?? AccountOutcome.deleted
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Das Konto wird gelöscht und die Anmeldung aufgehoben. Rezepte, die Du veröffentlicht hast, bleiben für alle Nutzer sichtbar, gehören aber keinem Konto mehr. Rezepte auf diesem Gerät bleiben erhalten. Das lässt sich nicht widerrufen.")
        }
        .alert(accountOutcomeTitle, isPresented: $showsAccountOutcome) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            accountOutcomeMessage
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
        .onChange(of: starterPresetsText) { _, value in
            SettingsFile.set(value, forKey: AppSettingsKeys.starterDoughYieldPresets)
        }
    }

    /// Signing in with Apple, as on the iPhone: the same account there and
    /// here, so recipes published on either count as one's own.
    @ViewBuilder
    private var accountSection: some View {
        Section {
            if changesAccount {
                ProgressView()
            } else if model.account.isSignedInWithApple {
                HStack {
                    Text("Angemeldet als")
                    Spacer()
                    Text("Apple-Konto")
                        .foregroundStyle(.secondary)
                }
                if model.account.isAdmin {
                    Text("Administrator")
                        .foregroundStyle(.secondary)
                }
                Button("Abmelden", role: .destructive) {
                    changeAccount {
                        await model.signOut().map { AccountOutcome.signOutFailed($0) } ?? AccountOutcome.signedOut
                    }
                }
                Button("Konto löschen", role: .destructive) {
                    confirmsAccountDeletion = true
                }
            } else {
                Button("Mit Apple anmelden") {
                    changeAccount {
                        await model.signInWithApple().map { AccountOutcome.signInFailed($0) }
                    }
                }
            }
        } header: {
            Text("Konto")
        } footer: {
            Text("Die Anmeldung ist freiwillig. Mit ihr gilt die Autorschaft Deiner veröffentlichten Rezepte auf allen Geräten, auf denen Du angemeldet bist, und bleibt nach einer Neuinstallation erhalten. Administratoren verwalten damit gemeldete Rezepte.")
        }
    }

    /// Runs an account change and shows what came of it; nil shows nothing
    /// (a sign-in that worked speaks for itself).
    private func changeAccount(_ change: @escaping @MainActor () async -> AccountOutcome?) {
        changesAccount = true
        Task {
            let outcome = await change()
            changesAccount = false
            if let outcome {
                accountOutcome = outcome
                showsAccountOutcome = true
            }
        }
    }

    private var accountOutcomeTitle: LocalizedStringKey {
        switch accountOutcome {
        case .signInFailed: return "Anmeldung fehlgeschlagen"
        case .signedOut: return "Du bist abgemeldet"
        case .signOutFailed: return "Abmelden fehlgeschlagen"
        case .deleted: return "Konto wurde gelöscht"
        case .deletionFailed, nil: return "Löschen fehlgeschlagen"
        }
    }

    @ViewBuilder
    private var accountOutcomeMessage: some View {
        switch accountOutcome {
        case .signInFailed(let reason), .signOutFailed(let reason), .deletionFailed(let reason):
            Text(verbatim: reason)
        case .signedOut:
            Text("Du verwendest die App wieder anonym. Rezepte auf diesem Gerät bleiben unberührt. Die unter Deinem Konto veröffentlichten Rezepte kannst Du wieder bearbeiten, sobald Du Dich erneut anmeldest.")
        case .deleted:
            Text("Das Konto und die Anmeldung sind entfernt. Du kannst die App weiter verwenden und Dich jederzeit neu anmelden.")
        case nil:
            EmptyView()
        }
    }

    private func helpLink(_ title: LocalizedStringKey, url: URL) -> some View {
        Button {
            Task { _ = await UIApplication.shared.open(url) }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valueRow(_ title: LocalizedStringKey, localizedValue: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(localizedValue)
                .foregroundStyle(.secondary)
        }
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
        SettingsFile.set(value, forKey: key)
    }

    /// Android's page for the language of this app; Skip adds the package.
    static let languageSettingsURL = URL(string: "intent://android.settings.APP_LOCALE_SETTINGS")!

    /// "Deutsch", "English", "Français": the app's language in itself.
    static func languageName(of locale: Locale) -> String {
        let code = String(locale.identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first ?? "")
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// "06:00", as on the iPhone.
    static func hourText(_ hour: Int) -> String {
        (hour < 10 ? "0" : "") + String(hour) + ":00"
    }
}

/// What the cloud AI processes, why, where, and for how long — the
/// iPhone's page of the same name, with the local-analysis paragraph as it
/// applies to Android.
struct RecipeAIPrivacyView: View {
    let model: AppModel

    var body: some View {
        List {
            Section {
                Text("Wenn Du die geschützte Cloud-KI auswählst, verarbeitet BackPlaner die von Dir ausgewählten Rezeptbilder oder den Rezepttext und die Adresse der von Dir angegebenen Internetseite sowie technische Schutzdaten der Anfrage. Dazu gehören eine pseudonyme Firebase-Nutzerkennung, der Nachweis von Firebase App Check und, mit BakePlanner Pro, der vom App Store signierte Kaufbeleg, damit der Server Dein Kontingent zuordnen kann. Der Beleg enthält die Kennung und das Datum des Kaufs, aber keinen Namen und keine Zahlungsdaten.")
                Text("Für die stündliche und die monatliche Nutzungsbegrenzung werden zur pseudonymen Nutzerkennung der Beginn des aktuellen Zeitfensters, der aktuelle Monat und die Anzahl der Anfragen gespeichert.")
            } header: {
                Text("Umfang der Verarbeitung")
            }
            Section {
                Text("Die Verarbeitung erfolgt ausschließlich, um Zutaten, Mengen, Zeiten und Arbeitsschritte aus den Bildern oder dem Seitentext zu erkennen und daraus einen Rezeptentwurf zu erstellen. Die technischen Daten dienen der Absicherung des Endpunkts und dem Schutz vor missbräuchlicher oder übermäßiger Nutzung.")
                Text("Die Analyse in der Cloud erfolgt nur auf Grundlage Deiner vorherigen ausdrücklichen Einwilligung. Ohne Einwilligung wird keine Cloud-Analyse gestartet.")
            } header: {
                Text("Zweck und Rechtsgrundlage")
            }
            Section {
                Text("Die Daten werden verschlüsselt an eine geschützte Google Firebase Cloud Function von BackPlaner in der Region europe-west1 übertragen. Die ausgewählten Bilder beziehungsweise der Seitentext werden von dort an Google Vertex AI (Gemini) am Standort EU zur Analyse weitergegeben. Die Internetseite selbst lädt Dein Gerät direkt.")
                Text("Google Cloud ist dabei technischer Dienstleister. Eine Weitergabe für Werbung oder Nutzertracking durch BackPlaner findet nicht statt.")
            } header: {
                Text("Empfänger und Verarbeitungsort")
            }
            Section {
                Text("BackPlaner speichert die übertragenen Rezeptbilder und Seitentexte weder in Firebase Storage noch in der Rezept-Datenbank. Sie werden innerhalb der Analyseanfrage verarbeitet und nicht dauerhaft abgelegt.")
                Text("In Firestore verbleibt nur der Datensatz zur Nutzungsbegrenzung mit pseudonymer Nutzerkennung, Zeitfenster, Monat und Anfragezahlen sowie eine Prüfsumme des zuletzt geprüften Kaufbelegs und der Zeitpunkt der Prüfung. Bei einer späteren Analyse werden ein abgelaufenes Zeitfenster und ein vergangener Monat durch die neuen ersetzt.")
                Text("Der erkannte Rezeptentwurf wird erst gespeichert, wenn Du ihn anschließend prüfst und ausdrücklich speicherst. Dabei gilt Deine Wahl, ob das Rezept auf dem Gerät bleibt oder veröffentlicht wird.")
            } header: {
                Text("Speicherung und Löschung")
            }
            Section {
                Text("Mit „Nur auf diesem Gerät“ werden weder Rezeptbilder noch Seitentexte an Firebase oder Google Vertex AI übertragen. Auf Android übernimmt die App dann nur die strukturierten Rezeptdaten einer Internetseite; Fotos lassen sich ohne die Cloud-KI bisher nicht lesen.")
            } header: {
                Text("Lokale Analyse")
            }
            Section {
                HStack {
                    Text("Cloud-KI")
                    Spacer()
                    Text(model.allowsCloudAnalysis ? LocalizedStringKey("Zugelassen") : LocalizedStringKey("Nicht zugelassen"))
                        .foregroundStyle(.secondary)
                }
                if model.allowsCloudAnalysis {
                    Button("Einwilligung widerrufen", role: .destructive) {
                        model.allowsCloudAnalysis = false
                        model.usesCloudAnalysis = false
                    }
                } else {
                    Text("Eine Einwilligung kannst Du direkt beim Rezeptimport erteilen, nachdem Dir die Datenübertragung erklärt wurde.")
                        .foregroundStyle(.secondary)
                }
                Text("Der Widerruf gilt für alle zukünftigen Analysen. Bereits abgeschlossene Verarbeitungen werden dadurch nicht rückwirkend aufgehoben.")
            } header: {
                Text("Einwilligung und Widerruf")
            }
            Section {
                Text("Die KI erstellt lediglich einen bearbeitbaren Rezeptentwurf. Sie trifft keine rechtlich oder vergleichbar erheblich wirkende Entscheidung. Du kannst das Ergebnis vollständig prüfen, ändern oder verwerfen.")
            } header: {
                Text("Keine automatisierte Entscheidung")
            }
        }
        .navigationTitle("Datenschutz bei KI")
    }
}
