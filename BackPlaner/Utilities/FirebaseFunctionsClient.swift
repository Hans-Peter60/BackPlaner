import BakePlannerCore
import Foundation
@preconcurrency import FirebaseFunctions
import UIKit

struct ProtectedConnectionStatus: Sendable {
    let isAuthenticated: Bool
    let isAppCheckVerified: Bool
}

// The answer models (CloudRecipeAnalysis, CloudRecipe …) live in
// BakePlannerCore (CloudRecipeImport.swift), so the Android app reads them too.

final class FirebaseFunctionsClient: @unchecked Sendable {
    static let shared = FirebaseFunctionsClient()

    private let functions: Functions

    private init() {
        functions = Functions.functions(region: "europe-west1")
    }

    func verifyProtectedConnection() async throws -> ProtectedConnectionStatus {
        let result = try await functions
            .httpsCallable("verifyProtectedConnection")
            .call()

        guard let payload = result.data as? [String: Any],
              payload["ok"] as? Bool == true else {
            throw FirebaseFunctionsClientError.invalidResponse
        }

        return ProtectedConnectionStatus(
            isAuthenticated: payload["authenticated"] as? Bool == true,
            isAppCheckVerified: payload["appCheckVerified"] as? Bool == true
        )
    }

    @MainActor
    func analyzeRecipeImages(_ images: [UIImage]) async throws -> CloudRecipeAnalysis {
        let encodedImages = try images.map { image in
            let data = try image.recipeAnalysisJPEGData()
            return [
                "data": data.base64EncodedString(),
                "mimeType": "image/jpeg"
            ]
        }

        // The signed Pro purchase (or AppTransaction) lets the server waive
        // the monthly allowance after verifying the signature itself.
        var payload: [String: Any] = ["images": encodedImages]
        payload.merge(Entitlements.shared.proClaim) { _, claim in claim }

        let callable = functions.httpsCallable("analyzeRecipeImages")
        callable.timeoutInterval = 250
        let result = try await Self.mappingLimits {
            try await callable.call(payload)
        }

        guard let payload = result.data as? [String: Any],
              JSONSerialization.isValidJSONObject(payload) else {
            throw FirebaseFunctionsClientError.invalidResponse
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(CloudRecipeAnalysis.self, from: data)
    }

    /// Structures the text of a recipe web page. The page is fetched by the
    /// app; only the extracted text and the address leave the device.
    func analyzeRecipeText(_ text: String, sourceURL: URL?) async throws -> CloudRecipeAnalysis {
        // The signed Pro purchase (or AppTransaction) lets the server waive
        // the monthly allowance after verifying the signature itself.
        var payload: [String: Any] = ["text": text]
        payload.merge(await Entitlements.shared.proClaim) { _, claim in claim }
        if let sourceURL {
            payload["sourceURL"] = sourceURL.absoluteString
        }

        let callable = functions.httpsCallable("analyzeRecipeText")
        callable.timeoutInterval = 250
        let result = try await Self.mappingLimits {
            try await callable.call(payload)
        }

        guard let response = result.data as? [String: Any],
              JSONSerialization.isValidJSONObject(response) else {
            throw FirebaseFunctionsClientError.invalidResponse
        }

        let data = try JSONSerialization.data(withJSONObject: response)
        return try JSONDecoder().decode(CloudRecipeAnalysis.self, from: data)
    }

    /// Turns the server's "resource-exhausted" with the reason
    /// `monthly-limit` into `.monthlyLimitReached`, so the import can tell
    /// the person why the cloud stayed out of it. Every other error passes.
    private static func mappingLimits<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch {
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain,
               nsError.code == FunctionsErrorCode.resourceExhausted.rawValue,
               let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
               details["reason"] as? String == "monthly-limit" {
                throw FirebaseFunctionsClientError.monthlyLimitReached
            }
            throw error
        }
    }
}

enum FirebaseFunctionsClientError: LocalizedError {
    case imageEncodingFailed
    case imageTooLarge
    case invalidResponse
    /// The free cloud imports of this month are used up (see
    /// `MonetizationConfig.freeImportsPerMonth`).
    case monthlyLimitReached

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Ein Rezeptbild konnte nicht vorbereitet werden."
        case .imageTooLarge:
            return "Ein Rezeptbild ist auch nach der Verkleinerung zu groß."
        case .invalidResponse:
            return "Der Server hat eine ungültige Antwort geliefert."
        case .monthlyLimitReached:
            return String(localized: "Die kostenlosen Cloud-Importe dieses Monats sind aufgebraucht. Das Rezept wurde auf dem Gerät analysiert. Mit BakePlanner Pro gibt es kein Monatslimit.",
                          bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
        }
    }
}

private extension UIImage {
    @MainActor
    func recipeAnalysisJPEGData() throws -> Data {
        let maximumDimension: CGFloat = 2_000
        let largestDimension = max(size.width, size.height)
        let scale = min(1, maximumDimension / largestDimension)
        let targetSize = CGSize(
            width: max(1, size.width * scale),
            height: max(1, size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let preparedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = preparedImage.jpegData(compressionQuality: 0.72) else {
            throw FirebaseFunctionsClientError.imageEncodingFailed
        }
        guard data.count <= 3 * 1_024 * 1_024 else {
            throw FirebaseFunctionsClientError.imageTooLarge
        }
        return data
    }
}
