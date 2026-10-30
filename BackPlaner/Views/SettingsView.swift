import BakePlannerCore
import SwiftUI
import CoreData
import UniformTypeIdentifiers

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
    @AppStorage(AppSettingsKeys.automaticTranslation) private var automaticTranslation = AppSettings.defaultAutomaticTranslation
    @AppStorage(AppSettingsKeys.starterDoughYield) private var starterDoughYield = AppSettings.defaultStarterDoughYield
    @AppStorage(AppSettingsKeys.lievitoMadreDoughYield) private var lievitoMadreDoughYield = AppSettings.defaultLievitoMadreDoughYield
    @AppStorage(AppSettingsKeys.starterDoughYieldPresets) private var starterDoughYieldPresets = AppSettings.defaultStarterDoughYieldPresets
    @AppStorage(AppSettingsKeys.cloudRecipeAnalysisConsent) private var cloudRecipeAnalysisConsent = false
    @AppStorage(AppSettingsKeys.recipeImageAnalysisMode) private var recipeImageAnalysisMode = "localOnly"

    // Drives the navigation title's identity below; this is the same signal
    // that already updates the rest of the screen correctly, unlike the
    // `selectedLanguage` AppStorage, which races the app root's own copy of
    // it and can rebuild this view one step behind the environment change.
    @Environment(\.locale) private var locale

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

    // Recipe backup / restore.
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isImportingRecipes = false
    @State private var importedRecipeCount: Int?
    @State private var importErrorMessage: String?

    // BakePlanner Pro: the section only exists while the remote
    // configuration shows the store (or this installation has bought Pro).
    @State private var showPaywall = false
    @State private var isRestoringPurchases = false
    @State private var restoreMessage: String?

    // "Meine Anstellgut-TAs" while it is being typed; see the field itself.
    @State private var presetsText = ""
    @FocusState private var presetsFocused: Bool

    /// Writes the typed TAs into the setting. Called when the field is left
    /// or submitted, and when the screen goes away with the field still
    /// focused.
    private func storePresets() {
        guard presetsText != starterDoughYieldPresets else { return }
        starterDoughYieldPresets = presetsText
    }

    var body: some View {
        Form {
            proSection

            Section("Allgemein") {
                Group {
                    Picker("Sprache", selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language.rawValue)
                        }
                    }

                }
                .modifier(LargeTextPickerStyle())

                // The default for the "Veröffentlichen" toggle of a new
                // recipe. Stored as the storage preference it always was, so
                // an existing setting keeps its meaning.
                Toggle("Neue Rezepte veröffentlichen", isOn: Binding(
                    get: { RecipeStoragePreference(rawValue: defaultRecipeStorage)?.publishes ?? false },
                    set: { defaultRecipeStorage = RecipeStoragePreference(publishes: $0).rawValue }
                ))
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

                // The dough yield splits an amount of starter into flour and
                // water by these when the recipe does not state the TA itself.
                Stepper(value: $starterDoughYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield,
                        step: 5) {
                    LabeledContent("Anstellgut", value: "TA \(starterDoughYield)")
                }

                Stepper(value: $lievitoMadreDoughYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield,
                        step: 5) {
                    LabeledContent("Lievito Madre", value: "TA \(lievitoMadreDoughYield)")
                }

                // The TAs one keeps starters at — the quick picks offered when
                // a recipe's starter is swapped for one's own. Typed into a
                // local copy and stored when the field is left: bound to the
                // setting directly, every keystroke rebuilt this whole form.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Meine Anstellgut-TAs")
                        Spacer()
                        TextField("190, 210, 220", text: $presetsText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                            .focused($presetsFocused)
                            .onSubmit(storePresets)
                            .accessibilityLabel("Meine Anstellgut-TAs")
                    }
                    Text("Durch Komma getrennt; als Schnellwahl beim Anpassen der Anstellgut-TA.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                NavigationLink {
                    CustomUnitsView()
                } label: {
                    LabeledContent("Eigene Einheiten",
                                   value: unitStore.units.count.formatted())
                }
            }

            recipeBackupSection

            publicRecipeTranslationSection

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
                // for the step within reach. A Pro feature: locked, the row
                // leads to the paywall instead.
                ProGate(.liveActivity) {
                    Toggle("Live-Aktivität auf dem Sperrbildschirm", isOn: $liveActivity)
                        .onChange(of: liveActivity) { _, _ in
                            PlanSnapshotPublisher.shared.refresh()
                        }
                } label: {
                    Text("Live-Aktivität auf dem Sperrbildschirm")
                        .foregroundStyle(.primary)
                    Spacer()
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
        .onAppear {
            modelFB.checkAdminStatus()
            presetsText = starterDoughYieldPresets
        }
        .onChange(of: presetsFocused) { _, focused in
            if !focused { storePresets() }
        }
        .onDisappear(perform: storePresets)
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
            Text("Das Konto wird gelöscht und die Anmeldung aufgehoben. Rezepte, die Du veröffentlicht hast, bleiben für alle Nutzer sichtbar, gehören aber keinem Konto mehr. Rezepte auf diesem Gerät bleiben erhalten. Das lässt sich nicht widerrufen.")
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
            Text("Du verwendest die App wieder anonym. Rezepte auf diesem Gerät bleiben unberührt. Die unter Deinem Konto veröffentlichten Rezepte kannst Du wieder bearbeiten, sobald Du Dich erneut anmeldest.")
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
            Text("Das Konto und die Anmeldung sind entfernt. Du kannst die App weiter verwenden und Dich jederzeit neu anmelden.")
        }
        .alert("Löschen fehlgeschlagen", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        // The navigation bar title is bridged to UIKit and does not re-render
        // on its own when only the environment's locale changes under it;
        // switching the in-app language here left the previous language's
        // title standing above an already-translated screen. A new identity
        // forces this view (title included) to be rebuilt from scratch.
        .id(locale.identifier)
    }

    /// BakePlanner Pro, the one-time purchase. Absent while the remote
    /// configuration keeps the store hidden, so with the purchase switched
    /// off the settings look as they always did. See `Entitlements`.
    @ViewBuilder
    private var proSection: some View {
        let entitlements = Entitlements.shared
        if entitlements.storeVisible {
            Section {
                if entitlements.isPro {
                    Label("Pro ist freigeschaltet", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.accentText)
                    if entitlements.resolution.isGrandfathered && !ProStore.shared.hasPurchased {
                        Text("Du hattest die App schon, bevor es Pro gab. Die Pro-Funktionen bleiben für Dich frei.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        LabeledContent {
                            if let product = ProStore.shared.product {
                                Text(product.displayPrice)
                            }
                        } label: {
                            Label("Pro freischalten", systemImage: "seal")
                        }
                    }
                    .accessibilityIdentifier("settings.pro")

                    Button("Käufe wiederherstellen") {
                        Task { await restorePurchases() }
                    }
                    .disabled(isRestoringPurchases)
                }
            } header: {
                Text("BakePlanner Pro")
            } footer: {
                Text("Einmalkauf, kein Abo: PDF-Export, Rezepte weitergeben, wiederkehrende Backpläne, Einkaufslisten, Widgets und Live-Aktivität.")
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView()
            }
            .alert("Käufe wiederherstellen", isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
                Button("OK", role: .cancel) { restoreMessage = nil }
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }

    private func restorePurchases() async {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }
        do {
            try await ProStore.shared.restore()
            restoreMessage = Entitlements.shared.isPro
                ? String(localized: "Pro ist wieder freigeschaltet.", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
                : String(localized: "Für dieses Apple-Konto wurde kein Kauf gefunden.", bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        } catch {
            restoreMessage = error.localizedDescription
        }
    }

    /// Governs the public recipe screen's language handling: automatic
    /// translation into the app's language, or — off — the original
    /// language with the globe menu available to pick another one by hand.
    /// The two are mutually exclusive: once translation already settled the
    /// language, the globe would only redo what just happened.
    @ViewBuilder
    private var publicRecipeTranslationSection: some View {
        Section {
            Toggle("Öffentliche Rezepte automatisch übersetzen", isOn: $automaticTranslation)
        } header: {
            Text("Übersetzung")
        } footer: {
            Text("Betrifft nur die Rezept-Datenbank. Eingeschaltet übersetzt die App ein Rezept automatisch in Deine Sprache. Ausgeschaltet zeigt ein Rezept zunächst die Sprache, in der es geschrieben wurde; über das Globus-Symbol kannst Du dann selbst eine Sprache auswählen.")
        }
    }

    /// Every recipe on this device — what "alle eigenen Rezepte sichern"
    /// bundles into one file. A plain fetch, not a live `@FetchRequest`: the
    /// list only has to be right at the moment the button is tapped. The
    /// export item keeps the recipes' ids and reads them when the file is
    /// written, so this fetch returns faults and copies nothing.
    private var allOwnRecipes: [Recipe] {
        let request = Recipe.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? viewContext.fetch(request)) ?? []
    }

    /// Whether there is anything to back up; a count, not a fetch.
    private var hasOwnRecipes: Bool {
        ((try? viewContext.count(for: Recipe.fetchRequest())) ?? 0) > 0
    }

    private var backupFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "BakePlanner-Rezepte-\(formatter.string(from: Date()))"
    }

    /// Export and restore as a file: the one way to back up or hand over a
    /// recipe beyond iCloud and the public database (see the manual's
    /// "Es gibt keinen Export" limitation). Bake history and the starter
    /// feeding diary are not part of this — only the recipe itself.
    @ViewBuilder
    private var recipeBackupSection: some View {
        Section {
            ShareLink(
                item: RecipeFileExport(recipes: allOwnRecipes, fileName: backupFileName),
                preview: SharePreview(Text("BakePlanner-Rezepte"))
            ) {
                Label("Alle eigenen Rezepte sichern", systemImage: "arrow.down.doc")
            }
            .disabled(!hasOwnRecipes)

            Button {
                isImportingRecipes = true
            } label: {
                Label("Aus Sicherung wiederherstellen", systemImage: "arrow.up.doc")
            }
        } header: {
            Text("Sicherung")
        } footer: {
            Text("Sichert oder importiert Rezepte als Datei — zum Beispiel vor einem Gerätewechsel oder um ein Rezept außerhalb der Rezept-Datenbank weiterzugeben. Importierte Rezepte landen als neue eigene Rezepte, bestehende werden nie überschrieben.")
        }
        .fileImporter(isPresented: $isImportingRecipes, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    importedRecipeCount = try RecipeImport.importRecipes(from: url, into: viewContext)
                } catch {
                    importErrorMessage = error.localizedDescription
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .alert("Import abgeschlossen", isPresented: Binding(
            get: { importedRecipeCount != nil },
            set: { if !$0 { importedRecipeCount = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(importedRecipeCount ?? 0) Rezepte importiert")
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
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
    /// so the authorship of published recipes follows a uid that survives a
    /// reinstall and is the same on every device, and it is where a moderator
    /// signs in — a moderator is simply an account whose uid is listed in the
    /// Firestore `admins` collection. Signing in is voluntary.
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
            Text("Die Anmeldung ist freiwillig. Mit ihr gilt die Autorschaft Deiner veröffentlichten Rezepte auf allen Geräten, auf denen Du angemeldet bist, und bleibt nach einer Neuinstallation erhalten. Administratoren verwalten damit gemeldete Rezepte.")
        }
    }

    /// The user manual, the support page, the privacy policy and the legal
    /// notice live on the website, not in the app, so they can be corrected
    /// without an update. All open in Safari, like "Link zum Rezept" — the
    /// app deliberately has no web view. Privacy policy and legal notice
    /// have to be reachable from inside a commercial app.
    @ViewBuilder
    private var helpSection: some View {
        Section {
            Link(destination: HelpLinks.manual) {
                Label("Benutzerhandbuch", systemImage: "book")
            }
            Link(destination: HelpLinks.support) {
                Label("Hilfe und Kontakt", systemImage: "questionmark.circle")
            }
            Link(destination: HelpLinks.privacy) {
                Label("Datenschutzerklärung", systemImage: "hand.raised")
            }
            Link(destination: HelpLinks.imprint) {
                Label("Impressum", systemImage: "building.columns")
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

    /// The privacy policy, in the language the app runs in. Also the URL to
    /// give App Store Connect.
    static var privacy: URL {
        URL(string: "\(site)privacy.html#\(languageCode)")!
    }

    /// The legal notice (Impressum) German law requires of a commercial app.
    static var imprint: URL {
        URL(string: "\(site)impressum.html#\(languageCode)")!
    }
}

struct RecipeAIPrivacyView: View {
    @AppStorage(AppSettingsKeys.cloudRecipeAnalysisConsent) private var cloudRecipeAnalysisConsent = false
    @AppStorage(AppSettingsKeys.recipeImageAnalysisMode) private var recipeImageAnalysisMode = "localOnly"

    var body: some View {
        List {
            Section("Umfang der Verarbeitung") {
                Text("Wenn Du die geschützte Cloud-KI auswählst, verarbeitet BackPlaner die von Dir ausgewählten Rezeptbilder oder den Rezepttext und die Adresse der von Dir angegebenen Internetseite sowie technische Schutzdaten der Anfrage. Dazu gehören eine pseudonyme Firebase-Nutzerkennung, der Nachweis von Firebase App Check und, mit BakePlanner Pro, der vom App Store signierte Kaufbeleg, damit der Server Dein Kontingent zuordnen kann. Der Beleg enthält die Kennung und das Datum des Kaufs, aber keinen Namen und keine Zahlungsdaten.")
                Text("Für die stündliche und die monatliche Nutzungsbegrenzung werden zur pseudonymen Nutzerkennung der Beginn des aktuellen Zeitfensters, der aktuelle Monat und die Anzahl der Anfragen gespeichert.")
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
                Text("In Firestore verbleibt nur der Datensatz zur Nutzungsbegrenzung mit pseudonymer Nutzerkennung, Zeitfenster, Monat und Anfragezahlen sowie eine Prüfsumme des zuletzt geprüften Kaufbelegs und der Zeitpunkt der Prüfung. Bei einer späteren Analyse werden ein abgelaufenes Zeitfenster und ein vergangener Monat durch die neuen ersetzt.")
                Text("Der erkannte Rezeptentwurf wird erst gespeichert, wenn Du ihn anschließend prüfst und ausdrücklich speicherst. Dabei gilt Deine Wahl, ob das Rezept auf dem Gerät bleibt oder veröffentlicht wird.")
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
