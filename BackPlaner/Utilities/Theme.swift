//
//  Theme.swift
//  BackPlaner
//
//  Shared visual style extracted from ContentView so every screen shares the
//  same warm, bread-themed look (gradient background, brown palette, white cards).
//

import SwiftUI

// MARK: - Palette, fonts and gradients
enum Theme {

    /// Builds a color that automatically resolves to `light` or `dark` depending
    /// on the active interface style. This lets the warm bread theme keep its
    /// cream look in light mode while switching to a readable dark palette in
    /// dark mode. Previously all colors were hard-coded light, so the background
    /// stayed cream in dark mode while default/system text turned white and
    /// became unreadable.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    // Background gradient (top → bottom)
    static let backgroundTop    = dynamic(light: Color(red: 0.98, green: 0.93, blue: 0.82),
                                          dark:  Color(red: 0.16, green: 0.12, blue: 0.09))
    static let backgroundBottom = dynamic(light: Color(red: 0.93, green: 0.80, blue: 0.62),
                                          dark:  Color(red: 0.09, green: 0.07, blue: 0.05))

    // Accent / icon-badge gradient (topLeading → bottomTrailing).
    // This gradient is only ever a BACKGROUND for white content (icon badges,
    // the selected filter chip), so its lightest point — `accentTop` — has to
    // stay dark enough for white text to clear 4.5:1. That is why it is a good
    // deal deeper than the accent used as a foreground (`accentText` below).
    static let accentTop    = dynamic(light: Color(red: 0.62, green: 0.41, blue: 0.21),
                                      dark:  Color(red: 0.61, green: 0.41, blue: 0.22))
    static let accentBottom = dynamic(light: Color(red: 0.49, green: 0.29, blue: 0.14),
                                      dark:  Color(red: 0.48, green: 0.29, blue: 0.15))

    /// The accent used as a FOREGROUND on a card — the mirror image of the
    /// gradient above, so it has to go the other way in dark mode. Also passes
    /// on its own 12 % tint (the time capsule in the scheduled-steps list).
    static let accentText = dynamic(light: Color(red: 0.58, green: 0.355, blue: 0.16),
                                    dark:  Color(red: 0.89, green: 0.575, blue: 0.31))

    /// Status colors. The system `.orange` and `.red` are far too light on a
    /// white card (2.2:1 and 3.6:1), so the app carries its own.
    static let warning = dynamic(light: Color(red: 0.655, green: 0.383, blue: 0.00),
                                 dark:  Color(red: 1.00,  green: 0.624, blue: 0.039))
    static let danger  = dynamic(light: Color(red: 0.87, green: 0.20, blue: 0.16),
                                 dark:  Color(red: 1.00, green: 0.34, blue: 0.27))

    // Card surface used behind `cardStyle` content (white → warm dark surface).
    static let card = dynamic(light: .white,
                              dark:  Color(red: 0.20, green: 0.16, blue: 0.13))

    /// Outline of a text editor or of the unit menu. Unlike the card's shadow
    /// this border is not decoration: it is the only thing marking where the
    /// control begins and ends, which makes it a user interface component under
    /// WCAG 1.4.11 and puts it at a 3:1 minimum. The `.gray.opacity(0.3)` used
    /// before managed 1.4:1 on a white card and 1.6:1 on the dark one — a
    /// hairline that was essentially invisible. `subtitle` at 70 % reaches
    /// 3.6:1 and 4.5:1 while still reading as a quiet hairline.
    static let fieldBorder = subtitle.opacity(0.7)

    // Text colors (dark brown on cream in light mode, warm cream in dark mode).
    static let title     = dynamic(light: Color(red: 0.35, green: 0.20, blue: 0.08),
                                   dark:  Color(red: 0.96, green: 0.90, blue: 0.80))
    static let subtitle  = dynamic(light: Color(red: 0.45, green: 0.30, blue: 0.16),
                                   dark:  Color(red: 0.82, green: 0.72, blue: 0.60))
    static let cardTitle = dynamic(light: Color(red: 0.25, green: 0.15, blue: 0.06),
                                   dark:  Color(red: 0.97, green: 0.92, blue: 0.84))

    // Fonts (the app uses the Avenir family throughout).
    // `relativeTo:` lets the custom fonts scale with the user's preferred text
    // size (Dynamic Type) instead of staying at a fixed point size.
    static func brandFont(_ size: CGFloat) -> Font { .custom("Avenir Heavy", size: size, relativeTo: .body) }
    static func bodyFont(_ size: CGFloat)  -> Font { .custom("Avenir", size: size, relativeTo: .body) }

    // Gradients
    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom],
                       startPoint: .top, endPoint: .bottom)
    }
    static var accent: LinearGradient {
        LinearGradient(colors: [accentTop, accentBottom],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - View modifiers

/// Places the warm bread-themed gradient behind the content.
private struct WarmBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            content
        }
    }
}

/// Wraps the content in the standard white, rounded, shadowed card.
private struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            )
    }
}

extension View {

    /// Places the warm bread-themed gradient behind the content.
    func warmBackground() -> some View { modifier(WarmBackground()) }

    /// Wraps the content in the standard white, rounded, shadowed card.
    func cardStyle(cornerRadius: CGFloat = 16) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }

    /// Hides the default List/Form background so the warm gradient shows through.
    func clearScrollBackground() -> some View { scrollContentBackground(.hidden) }
}

// MARK: - Reusable components

/// The gradient icon badge used in ContentView's menu cards.
struct IconBadge: View {

    let systemImage: String
    var size: CGFloat     = 52
    var iconSize: CGFloat = 22

    // The badge sits next to text, so it has to grow with it — otherwise it
    // shrinks into a dot beside accessibility-size titles.
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent)
                .frame(width: size * scale, height: size * scale)

            Image(systemName: systemImage)
                .font(.system(size: iconSize * scale, weight: .semibold))
                .foregroundColor(.white)
        }
        // Purely decorative: the badge repeats what the adjacent title says.
        .accessibilityHidden(true)
    }
}

/// One-time agreement the user must accept before publishing a recipe to the
/// shared public database (App Store Guideline 1.2: zero tolerance for
/// objectionable content, user responsibility, moderation within 24h).
struct EULAView: View {

    @Environment(\.dismiss) private var dismiss

    /// Called after the user accepts; use it to perform the pending publish.
    var onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Nutzungsbedingungen für öffentliche Rezepte")
                        .font(Theme.brandFont(20))
                        .foregroundColor(Theme.title)

                    Text("Wenn Du ein Rezept öffentlich teilst, wird es für alle Nutzer der Rezept-Datenbank sichtbar.\n\nEs gilt eine Null-Toleranz-Politik gegenüber anstößigen, beleidigenden, rechtswidrigen oder urheberrechtsverletzenden Inhalten. Du bist allein verantwortlich für die von Dir geteilten Inhalte.\n\nGemeldete Inhalte werden geprüft und innerhalb von 24 Stunden entfernt. Autoren, die wiederholt gegen diese Regeln verstoßen, können ausgeschlossen werden.\n\nMit „Akzeptieren“ bestätigst Du, dass Du diese Bedingungen einhältst.")
                        .font(Theme.bodyFont(15))
                        .foregroundColor(Theme.subtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .warmBackground()
            .navigationTitle("Bevor Du teilst")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ablehnen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Akzeptieren") {
                        ModerationStore.shared.acceptEULA()
                        onAccept()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// A branded header shown at the top of a screen.
struct ScreenHeader: View {

    private let titleText: Text
    var subtitle: LocalizedStringKey? = nil

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        titleText = Text(title)
        self.subtitle = subtitle
    }

    /// A title that reads the same in every language — the app's own name.
    ///
    /// Passed through the translation it became "Bake Planner" in English and
    /// "Planificateur de cuisson" in French, so the app introduced itself
    /// under three names.
    init(brand: String, subtitle: LocalizedStringKey? = nil) {
        titleText = Text(verbatim: brand)
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            titleText
                .font(Theme.brandFont(34))
                .foregroundColor(Theme.title)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Theme.subtitle)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }
}
