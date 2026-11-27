import BakePlannerCore
import Foundation
import SwiftUI
#if os(Android)
import SkipFirebaseCore
import SkipFirebaseAuth
@preconcurrency import SkipFirebaseFunctions
#endif

/// The call to the Cloud Function analyzeDishSteps, as on the iPhone
/// (DishImportClient.swift there): the recipe text goes up, the work
/// steps come back. The function wants a signed-in user and App Check; the
/// user is anonymous, signed in on first use.
enum DishImportClient {

    enum ImportError: LocalizedError {
        case unavailable
        case invalidResponse
        case hourlyLimit
        case monthlyLimit
        case notAllowed
        case offline
        case timedOut
        case other(String)

        var errorDescription: String? {
            switch self {
            case .unavailable, .notAllowed:
                return String(localized: "Der Analyse-Dienst hat die Anfrage nicht zugelassen. Bitte die App aktualisieren oder später noch einmal versuchen.", bundle: .module)
            case .invalidResponse:
                return String(localized: "Die Antwort der Analyse war unvollständig.", bundle: .module)
            case .hourlyLimit:
                return String(localized: "Das stündliche Analyse-Limit ist erreicht. Bitte später noch einmal.", bundle: .module)
            case .monthlyLimit:
                return String(localized: "Die kostenlosen Rezeptanalysen dieses Monats sind aufgebraucht. Von Hand anlegen geht weiter; mit CookPlanner Pro gibt es keine Monatsgrenze.", bundle: .module)
            case .offline:
                return String(localized: "Keine Verbindung zum Analyse-Dienst. Bitte die Internetverbindung prüfen und noch einmal versuchen.", bundle: .module)
            case .timedOut:
                return String(localized: "Die Analyse hat zu lange gedauert. Bitte noch einmal versuchen, bei langen Rezepten vielleicht in zwei Teilen.", bundle: .module)
            case .other(let message):
                return message
            }
        }
    }

    static func configure() {
        #if os(Android)
        FirebaseApp.configure()
        #endif
    }

    /// Reads a cooking recipe into work steps.
    @MainActor
    static func analyze(_ text: String) async throws -> CloudDishAnalysis {
        #if os(Android)
        do {
            if Auth.auth().currentUser == nil {
                _ = try await Auth.auth().signInAnonymously()
            }
            let callable = Functions.functions(region: "europe-west1").httpsCallable("analyzeDishSteps")
            callable.timeoutInterval = 250
            let result = try await callable.call(["text": text])
            guard let payload = result.data as? [String: Any], JSONSerialization.isValidJSONObject(payload) else {
                throw ImportError.invalidResponse
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            do {
                return try JSONDecoder().decode(CloudDishAnalysis.self, from: data)
            } catch {
                throw ImportError.invalidResponse
            }
        } catch let error as ImportError {
            throw error
        } catch {
            // skip-firebase hands the function's answer over as an NSError
            // in com.firebase.functions with the gRPC code; the reason for
            // a monthly limit only shows in the text.
            logger.error("dish analysis failed: \(error)")
            let nsError = error as NSError
            let text = "\(error)".lowercased()
            if nsError.domain == "com.firebase.functions" {
                switch nsError.code {
                case 8: throw text.contains("monthly-limit") ? ImportError.monthlyLimit : ImportError.hourlyLimit
                case 4: throw ImportError.timedOut
                case 14: throw ImportError.offline
                case 7, 9, 16: throw ImportError.notAllowed
                default: break
                }
            }
            if text.contains("network") || text.contains("unknownhost") || text.contains("unable to resolve") {
                throw ImportError.offline
            }
            if text.contains("timeout") || text.contains("timed out") { throw ImportError.timedOut }
            throw ImportError.other(error.localizedDescription)
        }
        #else
        throw ImportError.unavailable
        #endif
    }
}

/// A recipe from pasted text or from a web page, read into work steps by
/// the cloud AI and handed to the editor for the cook to check (the
/// iPhone's DishTextImportView and DishWebImportView in one sheet).
struct DishImportView: View {
    let fromWeb: Bool
    let onImported: (KitchenDish) -> Void
    @State var text = ""
    @State var address = ""
    @State var isAnalyzing = false
    @State var failure: String?
    @State var result: KitchenDish?
    @State var warnings: [String] = []
    @State var notice: String?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Text(result.name)
                            .font(.headline)
                        Text(String(localized: "\(result.tasks.count) Schritte, \(result.ingredients.count) Zutaten", bundle: .module))
                            .foregroundStyle(.secondary)
                        if let notice {
                            Text(notice)
                                .font(.footnote)
                                .foregroundStyle(Palette.subtitle(colorScheme))
                        }
                    }
                    if !warnings.isEmpty {
                        Section(String(localized: "Bitte prüfen", bundle: .module)) {
                            ForEach(warnings, id: \.self) { warning in
                                Text(warning).font(.footnote)
                            }
                        }
                    }
                    Section {
                        Button(String(localized: "Im Editor prüfen", bundle: .module)) {
                            onImported(result)
                            dismiss()
                        }
                        Button(String(localized: "Noch einmal", bundle: .module)) {
                            self.result = nil
                        }
                    }
                } else {
                    Section {
                        if fromWeb {
                            TextField(String(localized: "Adresse der Rezeptseite", bundle: .module), text: $address)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        } else {
                            TextField(String(localized: "Rezepttext hier einfügen", bundle: .module), text: $text, axis: .vertical)
                                .lineLimit(20)
                        }
                    } footer: {
                        Text(fromWeb
                             ? String(localized: "Die Seite wird auf diesem Gerät geladen; nur der Rezepttext geht zur Analyse an einen Dienst von Google.", bundle: .module)
                             : String(localized: "Der Text wird zur Analyse an einen Dienst von Google gesendet.", bundle: .module))
                    }
                    Section {
                        if isAnalyzing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(String(localized: "Wird analysiert …", bundle: .module))
                            }
                        } else {
                            Button(String(localized: "Analysieren", bundle: .module)) { analyze() }
                                .disabled(fromWeb ? normalizedURL == nil : text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                        }
                        if let failure {
                            Text(failure)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger(colorScheme))
                        }
                    }
                }
            }
            .navigationTitle(fromWeb ? String(localized: "Aus Webseite importieren", bundle: .module)
                                     : String(localized: "Aus Text importieren", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen", bundle: .module)) { dismiss() }
                }
            }
        }
        .tint(Palette.accent(colorScheme))
    }

    /// The address as typed, as an https address.
    private var normalizedURL: URL? {
        RecipeWebPageLoader.normalizedURL(from: address)
    }

    private func analyze() {
        failure = nil
        isAnalyzing = true
        Task {
            defer { isAnalyzing = false }
            do {
                var input = text
                var fallback = String(localized: "Gericht", bundle: .module)
                var source = KitchenDishSource.text
                if fromWeb, let url = normalizedURL {
                    let page = try await RecipeWebPageLoader.load(url)
                    input = page.analysisText
                    if !page.title.isEmpty { fallback = page.title }
                    source = .web
                }
                let analysis = try await DishImportClient.analyze(input)
                result = CloudDishImport.dish(from: analysis.dish, source: source, fallbackName: fallback)
                warnings = analysis.dish.warnings ?? []
                notice = analysis.freeImports.flatMap { allowance in
                    switch allowance.remaining {
                    case 0: return String(localized: "Das war die letzte kostenlose Rezeptanalyse dieses Monats. Mit CookPlanner Pro gibt es keine Monatsgrenze.", bundle: .module)
                    case 1: return String(localized: "Noch eine kostenlose Rezeptanalyse in diesem Monat.", bundle: .module)
                    case 2: return String(localized: "Noch \(allowance.remaining) kostenlose Rezeptanalysen in diesem Monat.", bundle: .module)
                    default: return nil
                    }
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
