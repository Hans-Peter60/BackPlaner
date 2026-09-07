import SwiftUI
import AuthenticationServices
import CryptoKit

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

    // Admin (Sign in with Apple) sign-in state.
    @State private var adminLoginError: String?
    @State private var isSigningIn = false
    /// Raw nonce generated for the current Apple request; its SHA256 is sent to
    /// Apple, and the raw value is used to build the Firebase credential.
    @State private var currentNonce: String?

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

                Stepper(value: $dayEnd, in: dayStart...23) {
                    LabeledContent("Tagesende", value: formattedHour(dayEnd))
                }
            }

            adminSection
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Einstellungen")
    }

    /// Admin sign-in: a real email/password account gives a stable uid that can
    /// be listed in the Firestore `admins` collection (unlike anonymous uids).
    @ViewBuilder
    private var adminSection: some View {
        Section("Administrator") {
            if modelFB.isAdmin {
                LabeledContent("Angemeldet als", value: modelFB.adminEmail ?? "Administrator")
                Button("Abmelden", role: .destructive) {
                    modelFB.signOutAdmin()
                    adminLoginError = nil
                }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    let nonce = Self.randomNonceString()
                    currentNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    handleAppleCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                .disabled(isSigningIn)

                if let adminLoginError {
                    Text(adminLoginError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
    }

    /// Handles the Apple authorization result and forwards the token to Firebase.
    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        adminLoginError = nil
        switch result {
        case .failure(let error):
            adminLoginError = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                adminLoginError = String(localized: "Apple-Login lieferte kein gültiges Token.")
                return
            }
            isSigningIn = true
            modelFB.signInAsAdminWithApple(idTokenString: idToken, rawNonce: nonce) { result in
                isSigningIn = false
                if case .failure(let error) = result {
                    adminLoginError = error.localizedDescription
                }
            }
        }
    }

    /// A cryptographically random nonce string (Apple-recommended implementation).
    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else { continue }
            for random in randoms where remaining > 0 {
                if random < 63 {
                    result.append(charset[Int(random) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// SHA256 hex digest, as required for the Apple sign-in nonce.
    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
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
