//
//  CookProPaywallView.swift
//  CookPlanner
//
//  The sheet that offers CookPlanner Pro, the small "Pro" mark, and the
//  modifier the call sites use to open it. While `CookPro` says a feature
//  is open, nothing in the app looks different.
//

import BakePlannerCore
import StoreKit
import SwiftUI

extension KitchenProFeature {
    var title: LocalizedStringResource {
        switch self {
        case .menu:         "Menü aus mehreren Gängen"
        case .handsFree:    "Vorlesen und Sprachbefehle"
        case .yearbook:     "Kochjahr-Buch"
        case .statistics:   "Kochstatistik"
        case .collections:  "Eigene Sammlungen"
        case .planPDF:      "Plan als PDF"
        case .learnedTimes: "Gemessene Zeiten übernehmen"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .menu:
            "Vorspeise, Hauptgang und Dessert aus Deinen Gerichten als ein Plan: Der Hauptgang wird gekocht, während die Gäste die Vorspeise essen."
        case .handsFree:
            "Der Kochmodus liest jeden Schritt samt Zutaten vor und hört auf „Erledigt“, „Steht“, „Was kommt“ oder „Wie lange“ – ohne das Display mit nassen Händen anzufassen."
        case .yearbook:
            "Dein Kochjahr als PDF-Buch: die Zahlen des Jahres, jeder Monat mit seinen Fotos, die Lieblingsgerichte und was die Uhr Dich gelehrt hat."
        case .statistics:
            "Die Kochhistorie als Zahlen und Diagramm: wie oft, was am meisten, wie bewertet."
        case .collections:
            "Eigene Filter-Kombinationen als Chip sichern und mit einem Tipp wieder aufrufen."
        case .planPDF:
            "Den Plan mit Uhrzeiten zum Drucken oder Verschicken, für die Küche an der Wand."
        case .learnedTimes:
            "Die mit der Stoppuhr gemessenen Zeiten früherer Durchgänge ins Gericht übernehmen, damit der nächste Plan noch genauer wird."
        }
    }

    var symbolName: String {
        switch self {
        case .menu:         "list.number"
        case .handsFree:    "mic"
        case .yearbook:     "book.closed"
        case .statistics:   "chart.bar.xaxis"
        case .collections:  "bookmark"
        case .planPDF:      "printer"
        case .learnedTimes: "wand.and.stars"
        }
    }
}

struct CookProPaywallView: View {

    /// The feature that led here; listed first.
    var highlighted: KitchenProFeature?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isRestoring = false
    @State private var redeeming = false

    private var features: [KitchenProFeature] {
        guard let highlighted else { return KitchenProFeature.allCases }
        return [highlighted] + KitchenProFeature.allCases.filter { $0 != highlighted }
    }

    var body: some View {
        let pro = CookPro.shared
        let store = CookProStore.shared

        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.accentText)
                        Text(verbatim: "CookPlanner Pro")
                            .font(Theme.brandFont(26))
                        Text("Einmal kaufen, dauerhaft nutzen. Kein Abo.")
                            .font(Theme.bodyFont(15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Enthalten") {
                    ForEach(features) { feature in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(Theme.brandFont(15))
                                Text(feature.detail)
                                    .font(Theme.bodyFont(13))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: feature.symbolName)
                                .foregroundStyle(Theme.accentText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mehr Rezeptanalysen")
                                .font(Theme.brandFont(15))
                            Text("Ohne Pro gibt es eine feste Zahl Analysen über die Cloud im Monat, mit Pro keine Monatsgrenze.")
                                .font(Theme.bodyFont(13))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.accentText)
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    if pro.hasPurchased {
                        Label("Pro ist freigeschaltet", systemImage: "checkmark.seal.fill")
                            .font(Theme.brandFont(15))
                            .foregroundStyle(Theme.accentText)
                    } else {
                        Button {
                            Task { await purchase() }
                        } label: {
                            HStack {
                                Text("Pro freischalten")
                                    .font(Theme.brandFont(16))
                                Spacer()
                                if let price = store.product?.displayPrice {
                                    Text(verbatim: price)
                                        .font(Theme.brandFont(16))
                                } else if store.productUnavailable {
                                    Text("Preis nicht verfügbar")
                                        .font(Theme.bodyFont(13))
                                        .foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(store.product == nil || store.isPurchasing)
                        .accessibilityIdentifier("paywall.purchase")

                        Button("Käufe wiederherstellen") {
                            Task { await restore() }
                        }
                        .disabled(isRestoring || store.isPurchasing)

                        // A code from Hans-Peter unlocks Pro for free.
                        Button("Code einlösen") {
                            redeeming = true
                        }
                        .disabled(isRestoring || store.isPurchasing)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Der Kauf gilt auf allen Geräten mit Deinem Apple-Konto. Alles, was Du zum Planen und Kochen gegen die Uhr brauchst, bleibt kostenlos: Gerichte, Plan, Kochmodus mit Wecker, Einkaufsliste, Verlauf und iCloud-Abgleich.")
                        Link("Datenschutzerklärung", destination: URL(string: "https://hans-peter60.github.io/bakeplanner/cookplanner-privacy.html")!)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .warmBackground()
            .navigationTitle(Text(verbatim: "CookPlanner Pro"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(pro.hasPurchased ? "Fertig" : "Schließen") { dismiss() }
                }
            }
            .overlay {
                if store.isPurchasing || isRestoring {
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .offerCodeRedemption(isPresented: $redeeming) { result in
                Task {
                    do {
                        try await CookProStore.shared.redeemed(result)
                        if CookProStore.shared.hasPurchased { dismiss() }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Kauf nicht möglich", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
            .task {
                // The product may not have loaded at launch (no network
                // then); a second try when the sheet opens is cheap.
                if store.product == nil {
                    await store.loadProduct()
                }
            }
        }
    }

    private func purchase() async {
        do {
            if try await CookProStore.shared.purchase() {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await CookProStore.shared.restore()
            if CookProStore.shared.hasPurchased {
                dismiss()
            } else {
                errorMessage = String(localized: "Für dieses Apple-Konto wurde kein Kauf gefunden.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The small "Pro" mark next to a locked control.
struct CookProBadge: View {
    var body: some View {
        Text(verbatim: "Pro")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accentText, in: Capsule())
            .foregroundStyle(.white)
            .accessibilityLabel("Gehört zu CookPlanner Pro")
    }
}

/// Which feature's paywall is showing; the identity for `.sheet(item:)`.
struct CookProOffer: Identifiable, Equatable {
    var feature: KitchenProFeature
    var id: String { feature.rawValue }
}

extension View {
    /// Presents the paywall for the feature in `offer` while it is set.
    func cookProPaywall(_ offer: Binding<CookProOffer?>) -> some View {
        sheet(item: offer) { offer in
            CookProPaywallView(highlighted: offer.feature)
        }
    }
}

/// Runs `action` when `feature` is open, otherwise sets `offer` so the
/// paywall opens. For buttons and menu entries.
@MainActor
func withCookPro(_ feature: KitchenProFeature, offer: Binding<CookProOffer?>, _ action: () -> Void) {
    if CookPro.shared.isUnlocked(feature) {
        action()
    } else {
        offer.wrappedValue = CookProOffer(feature: feature)
    }
}

/// Shows `content` while `feature` is open; locked, a screen that names
/// the feature and offers Pro. For a whole view, like the statistics.
struct CookProLockedScreen<Content: View>: View {

    let feature: KitchenProFeature
    @ViewBuilder let content: () -> Content

    @State private var offer: CookProOffer?

    init(_ feature: KitchenProFeature, @ViewBuilder content: @escaping () -> Content) {
        self.feature = feature
        self.content = content
    }

    var body: some View {
        if CookPro.shared.isUnlocked(feature) {
            content()
        } else {
            ContentUnavailableView {
                Label {
                    Text(feature.title)
                } icon: {
                    Image(systemName: "lock")
                }
            } description: {
                VStack(spacing: 6) {
                    Text(feature.detail)
                    Text("Gehört zu CookPlanner Pro.")
                }
            } actions: {
                Button("Pro freischalten") {
                    offer = CookProOffer(feature: feature)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentText)
            }
            .cookProPaywall($offer)
        }
    }
}
