//
//  ShareImportView.swift
//  CookPlannerShare
//
//  What the share sheet shows: the page about to be handed to CookPlanner,
//  one button to do it and one to leave. The colours follow the app's
//  Theme.swift, which stays in the app target.
//

import Observation
import SwiftUI

@Observable @MainActor
final class ShareImportModel {

    enum Phase: Equatable {
        /// Still reading the shared item.
        case loading
        /// The address is known; waiting for the cook.
        case ready
        /// Parked in the App Group, but the app could not be opened from here.
        case handedOff
        case failed(String)
    }

    var pageURL: URL?
    var phase: Phase = .loading
}

struct ShareImportView: View {

    let model: ShareImportModel
    var onImport: () -> Void
    var onCancel: () -> Void
    var onDone: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            ShareTheme.background
                .ignoresSafeArea()
            ScrollView {
                card
                    .frame(maxWidth: 480)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rezept in CookPlanner importieren")
                        .font(.headline)
                        .foregroundStyle(ShareTheme.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    if let host = model.pageURL?.host() {
                        Text(verbatim: host)
                            .font(.subheadline)
                            .foregroundStyle(ShareTheme.subtitle)
                    }
                }
            }

            switch model.phase {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Seite wird gelesen …")
                        .foregroundStyle(ShareTheme.subtitle)
                }

            case .ready:
                Text("Die Seite wird an CookPlanner übergeben. Dort liest die App die Arbeitsschritte aus, schätzt die Zeiten und zeigt Dir alles vor dem Speichern.")
                    .font(.footnote)
                    .foregroundStyle(ShareTheme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)

                buttons {
                    Button(action: onImport) {
                        Label("Importieren", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ShareTheme.accent)

                    Button("Abbrechen", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                        .tint(ShareTheme.accent)
                }

            case .handedOff:
                Text("CookPlanner ließ sich von hier aus nicht öffnen. Öffne die App selbst, der Import startet dort von allein.")
                    .font(.footnote)
                    .foregroundStyle(ShareTheme.subtitle)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Fertig", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(ShareTheme.accent)
                    .frame(maxWidth: .infinity)

            case .failed(let message):
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(ShareTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Schließen", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(ShareTheme.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ShareTheme.card)
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
        )
    }

    /// Two buttons side by side, stacked once the text grows too large for
    /// one row.
    @ViewBuilder
    private func buttons<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        layout { content() }
    }

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ShareTheme.accent)
                .frame(width: 44, height: 44)
            Image(systemName: "frying.pan")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

/// The app's palette in short, so the sheet looks like the app without
/// pulling the whole theme into the extension.
enum ShareTheme {

    private static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    static let backgroundTop = dynamic(light: Color(red: 0.99, green: 0.95, blue: 0.88),
                                       dark: Color(red: 0.16, green: 0.12, blue: 0.09))
    static let backgroundBottom = dynamic(light: Color(red: 0.96, green: 0.86, blue: 0.72),
                                          dark: Color(red: 0.09, green: 0.07, blue: 0.05))
    static let accent = dynamic(light: Color(red: 0.75, green: 0.38, blue: 0.14),
                                dark: Color(red: 0.89, green: 0.55, blue: 0.28))
    static let danger = dynamic(light: Color(red: 0.87, green: 0.20, blue: 0.16),
                                dark: Color(red: 1.00, green: 0.34, blue: 0.27))
    static let card = dynamic(light: .white, dark: Color(red: 0.20, green: 0.16, blue: 0.13))
    static let subtitle = dynamic(light: Color(red: 0.45, green: 0.30, blue: 0.16),
                                  dark: Color(red: 0.82, green: 0.72, blue: 0.60))
    static let cardTitle = dynamic(light: Color(red: 0.25, green: 0.15, blue: 0.06),
                                   dark: Color(red: 0.97, green: 0.92, blue: 0.84))

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}
