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
/// devices. Two things rest on it: the moderator login in the settings, and
/// the authorship of published recipes, which then follows the person rather
/// than the installation. Signing in is voluntary; without it the anonymous
/// identity of the installation is the author.
struct AppleSignInView: View {

    /// What the Apple credential is used for. Deleting an account needs a
    /// FRESH credential for the account that is already signed in, which is a
    /// different Firebase call than signing in.
    enum Purpose {
        case signIn
        case reauthenticate
    }

    @EnvironmentObject private var modelFB: RecipeFBModel

    var purpose: Purpose = .signIn

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
                errorMessage = String(localized: "Apple-Login lieferte kein gültiges Token.", bundle: AppSettings.localizationBundle)
                return
            }
            isSigningIn = true
            let finish: (Result<Void, Error>) -> Void = { result in
                isSigningIn = false
                switch result {
                case .success:
                    onSignedIn?()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }

            switch purpose {
            case .signIn:
                modelFB.signInWithApple(idTokenString: idToken, rawNonce: nonce, completion: finish)
            case .reauthenticate:
                modelFB.reauthenticateWithApple(idTokenString: idToken, rawNonce: nonce, completion: finish)
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

#Preview {
    AppleSignInView()
        .padding()
        .environmentObject(RecipeFBModel())
}
