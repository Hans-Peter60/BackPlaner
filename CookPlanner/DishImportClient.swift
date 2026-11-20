//
//  DishImportClient.swift
//  CookPlanner
//
//  The call to the Cloud Function analyzeDishSteps: the pasted recipe text
//  goes up, the work steps come back (CloudDishAnalysis). The function
//  wants a signed-in user and App Check; the user is anonymous, signed in
//  on first use.
//

import BakePlannerCore
import FirebaseAuth
@preconcurrency import FirebaseFunctions
import Foundation

final class DishImportClient: @unchecked Sendable {
    static let shared = DishImportClient()

    private let functions = Functions.functions(region: "europe-west1")

    private init() {}

    /// Reads a cooking recipe into work steps.
    func analyzeText(_ text: String) async throws -> CloudDishAnalysis {
        if Auth.auth().currentUser == nil {
            try await Auth.auth().signInAnonymously()
        }
        let callable = functions.httpsCallable("analyzeDishSteps")
        callable.timeoutInterval = 250
        let result: HTTPSCallableResult
        do {
            result = try await callable.call(["text": text])
        } catch {
            throw DishImportError.from(error)
        }
        guard let payload = result.data as? [String: Any], JSONSerialization.isValidJSONObject(payload) else {
            throw DishImportError.invalidResponse
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(CloudDishAnalysis.self, from: data)
    }
}

enum DishImportError: LocalizedError {
    case invalidResponse
    case hourlyLimit
    case monthlyLimit
    case other(String)

    static func from(_ error: Error) -> DishImportError {
        let nsError = error as NSError
        if nsError.domain == FunctionsErrorDomain,
           FunctionsErrorCode(rawValue: nsError.code) == .resourceExhausted {
            let reason = (nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String
            return reason == "monthly-limit" ? .monthlyLimit : .hourlyLimit
        }
        return .other(error.localizedDescription)
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Die Antwort der Analyse war unvollständig.")
        case .hourlyLimit:
            return String(localized: "Das stündliche Analyse-Limit ist erreicht. Bitte später noch einmal.")
        case .monthlyLimit:
            return String(localized: "Die kostenlosen Importe dieses Monats sind aufgebraucht.")
        case .other(let message):
            return message
        }
    }
}
