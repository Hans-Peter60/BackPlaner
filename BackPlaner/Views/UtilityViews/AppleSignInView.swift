//
//  AppleSignInView.swift
//  BackPlaner
//

import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with Apple, wired to Firebase.
///
/// The Apple account provides a uid that survives reinstalls and works across
/// devices. Two features need it: the moderator login in the settings, and the
/// account that author-only cloud recipes are tied to. Both use this view, so
/// the nonce handling exists exactly once.
struct AppleSignInView: View {

    @EnvironmentObject private var modelFB: RecipeFBModel

    /// Called after a successful sign-in, e.g. to continue a pending save.
    var onSignedIn: (() -> Void)?

    @State private var errorMessage: String?
    @State private var isSigningIn = false
    /// Raw nonce generated for the current Apple request; its SHA256 is sent to
    /// Apple, and the raw value is used to build the Firebase credential.
    @State private var currentNonce: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonceString()
                currentNonce = nonce
                // No name/email scopes are requested: only the stable Apple uid
                // is needed, so no personal data is collected or stored.
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 44)
            .disabled(isSigningIn)
            .accessibilityLabel("Mit Apple anmelden")

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    // System .red is only 3.6:1 on white; 4.5 is required.
                    .foregroundColor(Theme.danger)
            }
        }
    }

    /// Handles the Apple authorization result and forwards the token to Firebase.
    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        errorMessage = nil
        switch result {
        case .failure(let error):
            // Cancelling is a normal choice, not an error worth reporting.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = String(localized: "Apple-Login lieferte kein gültiges Token.")
                return
            }
            isSigningIn = true
            modelFB.signInWithApple(idTokenString: idToken, rawNonce: nonce) { result in
                isSigningIn = false
                switch result {
                case .success:
                    onSignedIn?()
                case .failure(let error):
                    errorMessage = error.localizedDescription
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
}

/// Asks for the Apple sign-in that a private cloud recipe requires, and reports
/// back once it succeeded so the interrupted save can continue.
struct PrivateCloudSignInSheet: View {

    @Environment(\.dismiss) private var dismiss

    /// Called after a successful sign-in; the sheet closes itself beforehand.
    var onSignedIn: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Private Rezepte in der Rezept-Datenbank gehören zu Deinem Apple-Konto. Ohne Anmeldung wäre das Rezept nach einer Neuinstallation nicht mehr erreichbar.")
                        .font(Theme.bodyFont(15))

                    AppleSignInView {
                        dismiss()
                        onSignedIn()
                    }
                } footer: {
                    Text("Es werden weder Name noch E-Mail-Adresse abgefragt.")
                }
            }
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle("Anmeldung erforderlich")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AppleSignInView()
        .padding()
        .environmentObject(RecipeFBModel())
}
