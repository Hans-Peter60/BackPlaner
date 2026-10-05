import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.selectedLanguage) private var selectedLanguage = AppLanguage.system.rawValue
    @AppStorage(AppSettingsKeys.defaultRecipeStorage) private var defaultRecipeStorage = AppSettings.defaultRecipeStorage
    @AppStorage(AppSettingsKeys.defaultServingSize) private var defaultServingSize = AppSettings.defaultServingSize
    @AppStorage(AppSettingsKeys.useDetailView) private var useDetailView = AppSettings.defaultUseDetailView
    @AppStorage(AppSettingsKeys.preheatTime) private var preheatTime = AppSettings.defaultPreheatTime
    @AppStorage(AppSettingsKeys.bakePause) private var bakePause = AppSettings.defaultBakePause
    @AppStorage(AppSettingsKeys.ovenCount) private var ovenCount = AppSettings.defaultOvenCount
    @AppStorage(AppSettingsKeys.dayStart) private var dayStart = AppSettings.defaultDayStart
    @AppStorage(AppSettingsKeys.dayEnd) private var dayEnd = AppSettings.defaultDayEnd
    @AppStorage(AppSettingsKeys.speechInBakeMode) private var speechInBakeMode = AppSettings.defaultSpeechInBakeMode
    @AppStorage(AppSettingsKeys.liveActivity) private var liveActivity = AppSettings.defaultLiveActivity
    @AppStorage(AppSettingsKeys.bakersPercentages) private var bakersPercentages = AppSettings.defaultBakersPercentages
    @AppStorage(AppSettingsKeys.cloudRecipeAnalysisConsent) private var cloudRecipeAnalysisConsent = false
    @AppStorage(AppSettingsKeys.recipeImageAnalysisMode) private var recipeImageAnalysisMode = "localOnly"

    @EnvironmentObject private var modelFB: RecipeFBModel

    // Observed, not just read: the row below shows how many units the user has
    // defined, and coming back from that screen has to update the number.
    @ObservedObject private var unitStore = CustomUnitStore.shared

    // The moderation section shows how many authors and recipes this device
    // hides, so it has to follow the store rather than read it once.
    @ObservedObject private var moderation = ModerationStore.shared

    // Account deletion (App Store Guideline 5.1.1(v)).
    @State private var showDeleteAccountConfirm = false
    @State private var showReauthentication     = false
    @State private var isDeletingAccount        = false
    @State private var deleteErrorMessage: String?
    @State private var showDeletedConfirmation  = false

    // Signing out only changed the account section back to the sign-in button,
    // which reads as a demand to sign in again rather than as a confirmation.
    @State private var showSignedOutConfirmation = false
    @State private var signOutErrorMessage: String?

    var body: some View {
        Form {
            Section("Allgemein") {
                Group {
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
                .modifier(LargeTextPickerStyle())
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

                // Adds "· 62 %" of the component's flour to every weighed
                // ingredient in the component columns.
                Toggle("Bäckerprozente anzeigen", isOn: $bakersPercentages)

                NavigationLink {
                    CustomUnitsView()
                } label: {
                    LabeledContent("Eigene Einheiten",
                                   value: unitStore.units.count.formatted())
                }
            }

            Section("Backplanung") {
                Stepper(value: $preheatTime, in: 0...120, step: 5) {
                    LabeledContent("Vorheizzeit", value: "\(preheatTime) min")
                }

                Stepper(value: $bakePause, in: 0...120, step: 5) {
                    LabeledContent("Backpause", value: "\(bakePause) min")
                }

                // With more than one oven the plan check lets as many bakes
                // run side by side; only the one too many is an error.
                Stepper(value: $ovenCount, in: 1...AppSettings.maximumOvenCount) {
                    LabeledContent("Backöfen", value: ovenCount.formatted())
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

                // Off hides the read-aloud button in the bake mode entirely.
                Toggle("Sprachausgabe im Backmodus", isOn: $speechInBakeMode)

                // Off ends a running Live Activity right away; on starts one
                // for the step within reach.
                Toggle("Live-Aktivität auf dem Sperrbildschirm", isOn: $liveActivity)
                    .onChange(of: liveActivity) { _, _ in
                        PlanSnapshotPublisher.shared.refresh()
                    }
            }

            recipeAIPrivacySection

            moderationSection

            accountSection

            helpSection
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Einstellungen")
        // Picks up an admins document created while the app was running (by
        // the console or scripts/grant-admin.mjs), so the account section
        // shows "Administrator" without a restart.
        .onAppear { modelFB.checkAdminStatus() }
        .overlay {
            if isDeletingAccount {
                ProgressView("Konto wird gelöscht …")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .confirmationDialog("Konto endgültig löschen?", isPresented: $showDeleteAccountConfirm, titleVisibility: .visible) {
            Button("Konto löschen", role: .destructive) { deleteAccount() }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Deine privaten Rezepte in der Rezept-Datenbank werden mit ihren Bildern gelöscht und die Anmeldung wird aufgehoben. Rezepte, die Du veröffentlicht hast, bleiben für alle Nutzer sichtbar. Rezepte auf diesem Gerät bleiben erhalten. Das lässt sich nicht widerrufen.")
        }
        // Firebase refuses to delete an account whose sign-in is not recent, so
        // the identity is confirmed once more and the deletion then continues.
        .sheet(isPresented: $showReauthentication) {
            NavigationStack {
                Form {
                    Section {
                        Text("Zur Sicherheit musst Du Dich noch einmal anmelden, bevor das Konto gelöscht wird.")
                            .font(Theme.bodyFont(15))

                        AppleSignInView(purpose: .reauthenticate) {
                            showReauthentication = false
                            deleteAccount()
                        }
                    }
                }
                .clearScrollBackground()
                .warmBackground()
                .navigationTitle("Erneut anmelden")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { showReauthentication = false }
                    }
                }
            }
        }
        .alert("Du bist abgemeldet", isPresented: $showSignedOutConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Deine privaten Rezepte in der Rezept-Datenbank sind erst wieder sichtbar, wenn Du Dich erneut anmeldest. Rezepte auf diesem Gerät und von Dir veröffentlichte Rezepte bleiben unberührt.")
        }
        .alert("Abmelden fehlgeschlagen", isPresented: Binding(
            get: { signOutErrorMessage != nil },
            set: { if !$0 { signOutErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { signOutErrorMessage = nil }
        } message: {
            Text(signOutErrorMessage ?? "")
        }
        .alert("Konto wurde gelöscht", isPresented: $showDeletedConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Deine privaten Rezepte und die Anmeldung sind entfernt. Du kannst die App weiter verwenden und Dich jederzeit neu anmelden.")
        }
        .alert("Löschen fehlgeschlagen", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var recipeAIPrivacySection: some View {
        Section {
            NavigationLink {
                RecipeAIPrivacyView()
            } label: {
                LabeledContent(
                    "KI-Analyse beim Rezeptimport",
                    value: cloudRecipeAnalysisConsent
                        ? String(localized: "Zugelassen", bundle: AppSettings.localizationBundle)
                        : String(localized: "Nur lokal", bundle: AppSettings.localizationBundle)
                )
            }

            if cloudRecipeAnalysisConsent {
                Button("Einwilligung zur Cloud-KI widerrufen", role: .destructive) {
                    cloudRecipeAnalysisConsent = false
                    recipeImageAnalysisMode = "localOnly"
                }
            }
        } header: {
            Text("Datenschutz & KI")
        } footer: {
            Text("Die Cloud-KI wird nur nach Deiner ausdrücklichen Einwilligung verwendet. Eine lokale Analyse bleibt immer verfügbar.")
        }
    }

    /// Deletes the account, asking for a fresh sign-in when Firebase considers
    /// the current one too old.
    private func deleteAccount() {
        isDeletingAccount = true
        modelFB.deleteAccount { result in
            isDeletingAccount = false
            switch result {
            case .success:
                showDeletedConfirmation = true
            case .failure(let error):
                if case AccountDeletionError.requiresRecentLogin = error {
                    showReauthentication = true
                } else {
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Lets the user take back what he blocked or reported.
    ///
    /// Blocking and reporting were one-way streets until now: both lists live
    /// in `UserDefaults` and had no counterpart, so a block made by accident
    /// lasted for as long as the app stayed installed.
    @ViewBuilder
    private var moderationSection: some View {
        Section {
            LabeledContent("Blockierte Autoren",
                           value: moderation.blockedAuthors.count.formatted())

            Button("Blockierungen aufheben") {
                moderation.unblockAllAuthors()
            }
            .disabled(moderation.blockedAuthors.isEmpty)

            LabeledContent("Von Dir gemeldete Rezepte",
                           value: moderation.hiddenRecipes.count.formatted())

            Button("Meldungen auf diesem Gerät zurücknehmen") {
                moderation.unhideAllRecipes()
            }
            .disabled(moderation.hiddenRecipes.isEmpty)
        } header: {
            Text("Moderation")
        } footer: {
            // Deliberately spells out the asymmetry: unblocking works at once,
            // un-reporting does not, because the recipe is withheld server-side
            // until a moderator has looked at it.
            Text("Blockierte Autoren erscheinen sofort wieder in der Rezept-Datenbank. Ein gemeldetes Rezept bleibt dagegen für alle Nutzer ausgeblendet, bis ein Administrator es geprüft hat — das Zurücknehmen wirkt erst danach.")
        }
    }

    /// The account section serves two purposes: it is where an author signs in
    /// so his private cloud recipes are tied to a uid that survives a reinstall,
    /// and it is where a moderator signs in — a moderator is simply an account
    /// whose uid is listed in the Firestore `admins` collection.
    @ViewBuilder
    private var accountSection: some View {
        Section {
            if modelFB.isSignedInWithAccount {
                // Says "Apple-Konto" rather than the address: the email scope
                // is never requested, so for anyone signing in now there is no
                // address to show anyway — and not reading it keeps a piece of
                // personal data out of the app entirely.
                LabeledContent("Angemeldet als", value: String(localized: "Apple-Konto", bundle: AppSettings.localizationBundle))

                if modelFB.isAdmin {
                    Label("Administrator", systemImage: "checkmark.seal")
                        .foregroundColor(Theme.subtitle)
                }

                Button("Abmelden", role: .destructive) {
                    modelFB.signOutAccount { result in
                        switch result {
                        case .success:
                            showSignedOutConfirmation = true
                        case .failure(let error):
                            signOutErrorMessage = error.localizedDescription
                        }
                    }
                }

                Button("Konto löschen", role: .destructive) {
                    showDeleteAccountConfirm = true
                }
                .disabled(isDeletingAccount)
            } else {
                AppleSignInView()
            }
        } header: {
            Text("Konto")
        } footer: {
            Text("Die Anmeldung wird für private Cloud-Rezepte benötigt: nur so bleiben sie nach einer Neuinstallation erreichbar. Administratoren verwalten damit gemeldete Rezepte.")
        }
    }

    /// The user manual and the support page live on the website, not in the
    /// app, so they can be corrected without an update. Both open in Safari,
    /// like "Link zum Rezept" — the app deliberately has no web view.
    @ViewBuilder
    private var helpSection: some View {
        Section {
            Link(destination: HelpLinks.manual) {
                Label("Benutzerhandbuch", systemImage: "book")
            }
            Link(destination: HelpLinks.support) {
                Label("Hilfe und Kontakt", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Hilfe")
        } footer: {
            Text("Öffnet die Seiten im Browser.")
        }
    }

    private func formattedHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

/// Addresses of the manual and the support page on the BakePlanner website,
/// in the language the app is running in.
enum HelpLinks {

    static let site = "https://hans-peter60.github.io/bakeplanner/"

    /// "de", "en" or "fr" — the manual exists in exactly these; anything else
    /// gets English.
    static var languageCode: String {
        let code = AppSettings.locale.language.languageCode?.identifier ?? "en"
        return ["de", "fr"].contains(code) ? code : "en"
    }

    static var manual: URL {
        URL(string: "\(site)manual-\(languageCode).html")!
    }

    static var support: URL {
        URL(string: "\(site)index.html#\(languageCode)")!
    }
}

struct RecipeAIPrivacyView: View {
    @AppStorage(AppSettingsKeys.cloudRecipeAnalysisConsent) private var cloudRecipeAnalysisConsent = false
    @AppStorage(AppSettingsKeys.recipeImageAnalysisMode) private var recipeImageAnalysisMode = "localOnly"

    var body: some View {
        List {
            Section("Umfang der Verarbeitung") {
                Text("Wenn Du die geschützte Cloud-KI auswählst, verarbeitet BackPlaner die von Dir ausgewählten Rezeptbilder oder den Rezepttext und die Adresse der von Dir angegebenen Internetseite sowie technische Schutzdaten der Anfrage. Dazu gehören eine pseudonyme Firebase-Nutzerkennung und der Nachweis von Firebase App Check.")
                Text("Für die stündliche Nutzungsbegrenzung werden zur pseudonymen Nutzerkennung der Beginn des aktuellen Zeitfensters und die Anzahl der Anfragen gespeichert.")
            }

            Section("Zweck und Rechtsgrundlage") {
                Text("Die Verarbeitung erfolgt ausschließlich, um Zutaten, Mengen, Zeiten und Arbeitsschritte aus den Bildern oder dem Seitentext zu erkennen und daraus einen Rezeptentwurf zu erstellen. Die technischen Daten dienen der Absicherung des Endpunkts und dem Schutz vor missbräuchlicher oder übermäßiger Nutzung.")
                Text("Die Analyse in der Cloud erfolgt nur auf Grundlage Deiner vorherigen ausdrücklichen Einwilligung. Ohne Einwilligung wird keine Cloud-Analyse gestartet.")
            }

            Section("Empfänger und Verarbeitungsort") {
                Text("Die Daten werden verschlüsselt an eine geschützte Google Firebase Cloud Function von BackPlaner in der Region europe-west1 übertragen. Die ausgewählten Bilder beziehungsweise der Seitentext werden von dort an Google Vertex AI (Gemini) am Standort EU zur Analyse weitergegeben. Die Internetseite selbst lädt Dein Gerät direkt.")
                Text("Google Cloud ist dabei technischer Dienstleister. Eine Weitergabe für Werbung oder Nutzertracking durch BackPlaner findet nicht statt.")
            }

            Section("Speicherung und Löschung") {
                Text("BackPlaner speichert die übertragenen Rezeptbilder und Seitentexte weder in Firebase Storage noch in der Rezept-Datenbank. Sie werden innerhalb der Analyseanfrage verarbeitet und nicht dauerhaft abgelegt.")
                Text("In Firestore verbleibt nur der Datensatz zur stündlichen Nutzungsbegrenzung mit pseudonymer Nutzerkennung, Zeitfenster und Anfragezahl. Bei einer späteren Analyse wird ein abgelaufenes Zeitfenster durch das neue ersetzt.")
                Text("Der erkannte Rezeptentwurf wird erst gespeichert, wenn Du ihn anschließend prüfst und ausdrücklich speicherst. Dabei gilt die von Dir gewählte lokale, private oder öffentliche Ablage.")
            }

            Section("Lokale Analyse") {
                Text("Mit „Nur auf diesem Gerät“ werden weder Rezeptbilder noch Seitentexte an Firebase oder Google Vertex AI übertragen. Je nach Verfügbarkeit verwendet die App Apple Intelligence auf dem Gerät, die lokale Texterkennung oder die strukturierten Rezeptdaten der Seite.")
            }

            Section("Einwilligung und Widerruf") {
                LabeledContent(
                    "Cloud-KI",
                    value: cloudRecipeAnalysisConsent
                        ? String(localized: "Zugelassen", bundle: AppSettings.localizationBundle)
                        : String(localized: "Nicht zugelassen", bundle: AppSettings.localizationBundle)
                )

                if cloudRecipeAnalysisConsent {
                    Button("Einwilligung widerrufen", role: .destructive) {
                        cloudRecipeAnalysisConsent = false
                        recipeImageAnalysisMode = "localOnly"
                    }
                } else {
                    Text("Eine Einwilligung kannst Du direkt beim Rezeptimport erteilen, nachdem Dir die Datenübertragung erklärt wurde.")
                        .foregroundStyle(.secondary)
                }

                Text("Der Widerruf gilt für alle zukünftigen Analysen. Bereits abgeschlossene Verarbeitungen werden dadurch nicht rückwirkend aufgehoben.")
            }

            Section("Keine automatisierte Entscheidung") {
                Text("Die KI erstellt lediglich einen bearbeitbaren Rezeptentwurf. Sie trifft keine rechtlich oder vergleichbar erheblich wirkende Entscheidung. Du kannst das Ergebnis vollständig prüfen, ändern oder verwerfen.")
            }
        }
        .navigationTitle("Datenschutz bei KI")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lets the user add units the app does not ship with.
///
/// The unit menu in the recipe forms offers a fixed list because a unit
/// carries a conversion factor, not just a name (see ``UnitBase``). Anything
/// outside that list — "Becher", or the "cups" an English recipe brings in
/// through the image import — was previously flagged as unknown with no way to
/// keep it. This is that way.
struct CustomUnitsView: View {

    @ObservedObject private var store = CustomUnitStore.shared

    @State private var name         = ""
    @State private var abbreviation = ""
    @State private var factor: Double?
    @State private var base         = UnitBase.milliliter
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if store.units.isEmpty {
                Section {
                    Text("Du hast noch keine eigene Einheit angelegt. Die mitgelieferten Einheiten stehen in der Auswahlliste immer zur Verfügung.")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)
                }
            } else {
                Section("Eigene Einheiten") {
                    ForEach(store.units) { unit in
                        LabeledContent {
                            Text(describe(unit))
                                .foregroundColor(Theme.subtitle)
                        } label: {
                            Text(verbatim: "\(unit.abbreviation) – \(unit.name)")
                        }
                        // Two lines that belong to one unit; read as one entry.
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { store.delete(at: $0) }
                }
            }

            Section("Neue Einheit") {
                TextField("Name", text: $name)
                    .accessibilityLabel("Name der Einheit")

                TextField("Kürzel", text: $abbreviation)
                    .accessibilityLabel("Kürzel der Einheit")

                Picker("Gemessen in", selection: $base) {
                    ForEach(UnitBase.allCases) { unitBase in
                        Text(unitBase.title).tag(unitBase)
                    }
                }

                // A counted unit has no factor to ask for — it is always 1.
                if base != .piece {
                    TextField("Umrechnung", value: $factor, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Umrechnung")
                }

                Text(base.factorExplanation)
                    .font(.footnote)
                    .foregroundColor(Theme.subtitle)

                Button("Einheit hinzufügen") { addUnit() }
            }

            Section {
                Text("Eine Einheit sagt der App, wie sie eine Menge in ein Gewicht umrechnet. Davon leben die Gesamtzutaten, die Bäckerprozente und die Einkaufsliste. Deshalb braucht auch eine eigene Einheit eine Umrechnung — ohne sie würde „2 Becher Mehl“ als 2 Gramm zählen.")
                    .font(.footnote)
                    .foregroundColor(Theme.subtitle)
            }
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Eigene Einheiten")
        .toolbar {
            if !store.units.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
        .alert("Einheit nicht angelegt", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// The conversion in words, e.g. "250 ml" or "gezählt".
    private func describe(_ unit: CustomUnit) -> String {
        switch unit.base {
        case .piece:
            return String(localized: "gezählt", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        case .gram, .milliliter:
            let amount = unit.factor.formatted(.number.precision(.fractionLength(0...2)))
            return "\(amount) \(unit.baseUnit)"
        }
    }

    private func addUnit() {
        do {
            try store.add(name: name, abbreviation: abbreviation, factor: factor, base: base)
            name         = ""
            abbreviation = ""
            factor       = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(RecipeFBModel())
}
