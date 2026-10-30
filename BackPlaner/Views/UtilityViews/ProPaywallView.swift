//
//  ProPaywallView.swift
//  BackPlaner
//
//  The sheet that offers BakePlanner Pro, and the two wrappers the Pro
//  call sites use: `ProGate` for a single control (a share button, a
//  toggle) and `ProLockedScreen` for a whole screen (the shopping list).
//  Both show their content unchanged while `Entitlements` says the feature
//  is open, so with the purchase switched off nothing in the app looks
//  different.
//

import BakePlannerCore
import SwiftUI
import StoreKit

struct ProPaywallView: View {

    /// The feature that led here; listed first so the person sees what
    /// they came for.
    var highlighted: ProFeature?

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isRestoring = false

    private var features: [ProFeature] {
        guard let highlighted else { return ProFeature.allCases }
        return [highlighted] + ProFeature.allCases.filter { $0 != highlighted }
    }

    var body: some View {
        let entitlements = Entitlements.shared
        let store = ProStore.shared

        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.accentText)
                        Text("BakePlanner Pro")
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
                }

                Section {
                    if entitlements.isPro {
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
                                if let product = store.product {
                                    Text(product.displayPrice)
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
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Der Kauf gilt auf allen Geräten mit Deinem Apple-Konto. Alles andere in der App bleibt kostenlos: Rezepte, Zeitplan, Backmodus, Backhistorie, Rezept-Datenbank und die Rechner.")
                        // What the purchase shares with whom, one tap away
                        // from the buy button.
                        Link("Datenschutzerklärung", destination: HelpLinks.privacy)
                    }
                }
            }
            .clearScrollBackground()
            .warmBackground()
            .navigationTitle("BakePlanner Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(entitlements.isPro ? "Fertig" : "Schließen") { dismiss() }
                }
            }
            .overlay {
                if store.isPurchasing || isRestoring {
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Kauf nicht möglich", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
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
            if try await ProStore.shared.purchase() {
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
            try await ProStore.shared.restore()
            if Entitlements.shared.isPro {
                dismiss()
            } else {
                errorMessage = String(localized: "Für dieses Apple-Konto wurde kein Kauf gefunden.",
                                      bundle: AppSettings.localizationBundle, locale: AppSettings.locale)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The small "Pro" mark next to a locked control.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "Pro")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.accentText, in: Capsule())
            .foregroundStyle(.white)
            .accessibilityLabel("Gehört zu BakePlanner Pro")
    }
}

/// Shows `content` while `feature` is open; locked, shows `label` with a Pro
/// mark as a button that opens the paywall. Meant for a single control,
/// typically a ShareLink or a Toggle, whose own look the label repeats.
struct ProGate<Content: View, Label: View>: View {

    let feature: ProFeature
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label

    @State private var showPaywall = false

    init(_ feature: ProFeature,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder label: @escaping () -> Label) {
        self.feature = feature
        self.content = content
        self.label = label
    }

    var body: some View {
        if Entitlements.shared.isUnlocked(feature) {
            content()
        } else {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 6) {
                    label()
                    ProBadge()
                }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView(highlighted: feature)
            }
        }
    }
}

/// Shows `content` while `feature` is open; locked, a screen that names the
/// feature and offers Pro. For destinations reached from the menu or a tab.
struct ProLockedScreen<Content: View>: View {

    let feature: ProFeature
    @ViewBuilder let content: () -> Content

    @State private var showPaywall = false

    init(_ feature: ProFeature, @ViewBuilder content: @escaping () -> Content) {
        self.feature = feature
        self.content = content
    }

    var body: some View {
        if Entitlements.shared.isUnlocked(feature) {
            content()
        } else {
            ContentUnavailableView {
                Label(feature.title, systemImage: "lock")
            } description: {
                VStack(spacing: 6) {
                    Text(feature.detail)
                    Text("Gehört zu BakePlanner Pro.")
                }
            } actions: {
                Button("Pro freischalten") {
                    showPaywall = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentText)
            }
            .warmBackground()
            .sheet(isPresented: $showPaywall) {
                ProPaywallView(highlighted: feature)
            }
        }
    }
}

#Preview {
    ProPaywallView(highlighted: .shoppingList)
}
