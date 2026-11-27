import BakePlannerCore
import SwiftUI

/// What Pro brings on Android: the iPhone's Pro features that the Android
/// app has. Widgets, the Live Activity, the yearbook, the hands-free bake
/// mode, the starter's diagram and the calendar check do not exist here.
extension ProFeature {
    static let android: [ProFeature] = [
        .pdfExport, .recipeSharing, .recurringPlans, .shoppingList, .pantry, .bakingDay,
        .collections, .statistics, .bakersFormula, .ovenProfiles, .historyImport,
    ]

    var title: String {
        switch self {
        case .pdfExport: return String(localized: "Rezepte als PDF teilen", bundle: .module)
        case .recipeSharing: return String(localized: "Rezepte weitergeben", bundle: .module)
        case .recurringPlans: return String(localized: "Wiederkehrende Backpläne", bundle: .module)
        case .shoppingList: return String(localized: "Einkaufslisten", bundle: .module)
        case .pantry: return String(localized: "Vorrat", bundle: .module)
        case .bakingDay: return String(localized: "Backtag planen", bundle: .module)
        case .collections: return String(localized: "Sammlungen und Fertig bis", bundle: .module)
        case .statistics: return String(localized: "Backstatistik", bundle: .module)
        case .bakersFormula: return String(localized: "Rezept nach Bäckerprozent", bundle: .module)
        case .ovenProfiles: return String(localized: "Ofenprofile", bundle: .module)
        case .historyImport: return String(localized: "Backhistorie aus Fotos", bundle: .module)
        default: return rawValue
        }
    }

    /// One line on what the feature does, for the paywall — the iPhone's,
    /// where Android does the same.
    var detail: String {
        switch self {
        case .pdfExport: return String(localized: "Ein Rezept in der gezeigten Portionsgröße als PDF drucken oder verschicken.", bundle: .module)
        case .recipeSharing: return String(localized: "Ein einzelnes Rezept als Datei weitergeben, die sich wieder importieren lässt.", bundle: .module)
        case .recurringPlans: return String(localized: "Ein Rezept plant sich in seinem Rhythmus von selbst, etwa das Füttern des Anstellguts.", bundle: .module)
        case .shoppingList: return String(localized: "Die Zutaten eines Rezepts auf eine Einkaufsliste setzen und abhaken.", bundle: .module)
        case .pantry: return String(localized: "Mehle, Saaten und Hefe mit Menge und Haltbarkeit führen; Gekauftes wandert aus der Einkaufsliste hinein.", bundle: .module)
        case .bakingDay: return String(localized: "Mehrere Brote für einen Backtag: Wunschzeit für das letzte, und die App legt die Startzeiten so, dass Öfen und Backpause passen.", bundle: .module)
        case .collections: return String(localized: "Eigene Filter-Kombinationen als Chip sichern und mit „Fertig bis“ nur die Rezepte sehen, die bis dahin noch zu schaffen sind.", bundle: .module)
        case .statistics: return String(localized: "Die Backhistorie als Zahlen und Diagramme: wie oft, was am meisten, wie bewertet.", bundle: .module)
        case .bakersFormula: return String(localized: "Ein neues Rezept aus Anteilen vom Mehl: Bäckerprozente eingeben, die App rechnet die Gramm.", bundle: .module)
        case .ovenProfiles: return String(localized: "Jeder Ofen mit seinen Vorheizzeiten, ob er heißer oder kälter läuft, als der Regler zeigt, und dem Umluft-Abschlag. Der Plan rechnet mit dem gewählten Ofen, und die Ofenschritte nennen die Reglereinstellung.", bundle: .module)
        case .historyImport: return String(localized: "Alte Brotfotos werden zur Backhistorie: Datum und Titel aus den Fotos, das Rezept nach dem Titel vorgeschlagen – zum Prüfen, dann mit einem Tipp angelegt.", bundle: .module)
        default: return ""
        }
    }
}

/// The sheet that offers BakePlanner Pro, the iPhone's paywall: what it
/// contains (the feature that led here first), the price from Google Play,
/// buying and restoring. A promotional code is redeemed in the Play Store
/// and arrives as a purchase.
struct ProPaywallView: View {
    var highlighted: ProFeature?
    @State var pro = BakePro.shared
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var features: [ProFeature] {
        guard let highlighted, ProFeature.android.contains(highlighted) else { return ProFeature.android }
        return [highlighted] + ProFeature.android.filter { $0 != highlighted }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Text(verbatim: "BakePlanner Pro")
                            .font(AppFont.size(26, weight: .bold))
                            .foregroundStyle(Palette.title(colorScheme))
                        Text(String(localized: "Einmal kaufen, dauerhaft nutzen. Kein Abo.", bundle: .module))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section(String(localized: "Enthalten", bundle: .module)) {
                    ForEach(features, id: \.self) { feature in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .fontWeight(.semibold)
                            Text(feature.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if pro.purchased {
                        Text(String(localized: "Pro ist freigeschaltet", bundle: .module))
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.accentText(colorScheme))
                    } else {
                        Button {
                            pro.purchase()
                        } label: {
                            HStack {
                                Text(String(localized: "Pro freischalten", bundle: .module))
                                    .fontWeight(.semibold)
                                Spacer()
                                if !pro.price.isEmpty {
                                    Text(pro.price)
                                } else if pro.productUnavailable {
                                    Text(String(localized: "Preis nicht verfügbar", bundle: .module))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(pro.price.isEmpty)
                        Button(String(localized: "Käufe wiederherstellen", bundle: .module)) {
                            pro.restore()
                        }
                        if pro.pending {
                            Text(String(localized: "Die Zahlung ist noch nicht abgeschlossen. Pro wird freigeschaltet, sobald Google Play sie bestätigt.", bundle: .module))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let failure = pro.lastFailure {
                            Text(failure)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger(colorScheme))
                        }
                    }
                } footer: {
                    Text(String(localized: "Der Kauf gilt auf allen Android-Geräten mit Deinem Google-Konto; einen Code löst Du im Play Store unter „Zahlungen und Abos“ ein. Ein Kauf auf dem iPhone gilt hier nicht. Alles andere in der App bleibt kostenlos: Rezepte, Zeitplan, Backmodus, Backhistorie, Rezept-Datenbank und die Rechner.", bundle: .module))
                }
            }
            .navigationTitle(Text(verbatim: "BakePlanner Pro"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(pro.purchased ? String(localized: "Fertig", bundle: .module) : String(localized: "Schließen", bundle: .module)) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: pro.purchased) { _, purchased in
            if purchased { dismiss() }
        }
    }
}

/// The small "PRO" mark beside a locked control.
struct ProBadge: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(verbatim: "PRO")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Palette.accentText(colorScheme)))
    }
}

/// A whole screen that belongs to Pro: its content while unlocked, else
/// what it offers and the way to it.
struct ProLockedScreen<Content: View>: View {
    let feature: ProFeature
    @ViewBuilder let content: () -> Content
    @State var pro = BakePro.shared
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if pro.isUnlocked(feature) {
            content()
        } else {
            VStack(spacing: 12) {
                ProBadge()
                Text(feature.title)
                    .font(AppFont.size(20, weight: .bold))
                    .foregroundStyle(Palette.title(colorScheme))
                Text(feature.detail)
                    .foregroundStyle(Palette.subtitle(colorScheme))
                    .multilineTextAlignment(.center)
                Button(String(localized: "Mehr erfahren", bundle: .module)) {
                    pro.offer(feature)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Runs `action` while `feature` is open, else offers Pro.
@MainActor
func proGated(_ feature: ProFeature, _ action: () -> Void) {
    if BakePro.shared.isUnlocked(feature) {
        action()
    } else {
        BakePro.shared.offer(feature)
    }
}

extension BakePro {
    /// A button or menu title with " · PRO" while the feature is locked
    /// (Skip's menus take plain text only).
    func title(_ title: String, for feature: ProFeature) -> String {
        isUnlocked(feature) ? title : title + " · PRO"
    }
}
