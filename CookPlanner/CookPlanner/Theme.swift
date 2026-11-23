//
//  Theme.swift
//  CookPlanner
//
//  The warm palette, fonts and card style of BakePlanner (BakePlanner/BackPlaner/
//  Utilities/Theme.swift), so the two apps read as one family. Without
//  the bakery photo behind the gradient, and without the parts only a
//  bread app needs.
//

import SwiftUI

enum Theme {

    /// A color that resolves to `light` or `dark` with the interface style.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    static let backgroundTop    = dynamic(light: Color(red: 0.98, green: 0.93, blue: 0.82),
                                          dark:  Color(red: 0.16, green: 0.12, blue: 0.09))
    static let backgroundBottom = dynamic(light: Color(red: 0.93, green: 0.80, blue: 0.62),
                                          dark:  Color(red: 0.09, green: 0.07, blue: 0.05))

    static let accentTop    = dynamic(light: Color(red: 0.62, green: 0.41, blue: 0.21),
                                      dark:  Color(red: 0.61, green: 0.41, blue: 0.22))
    static let accentBottom = dynamic(light: Color(red: 0.49, green: 0.29, blue: 0.14),
                                      dark:  Color(red: 0.48, green: 0.29, blue: 0.15))

    /// The accent as a foreground; clears 4.5:1 on the card and the gradient.
    static let accentText = dynamic(light: Color(red: 0.48, green: 0.29, blue: 0.13),
                                    dark:  Color(red: 0.89, green: 0.575, blue: 0.31))

    static let warning = dynamic(light: Color(red: 0.655, green: 0.383, blue: 0.00),
                                 dark:  Color(red: 1.00,  green: 0.624, blue: 0.039))
    static let danger  = dynamic(light: Color(red: 0.87, green: 0.20, blue: 0.16),
                                 dark:  Color(red: 1.00, green: 0.34, blue: 0.27))
    static let good    = dynamic(light: Color(red: 0.16, green: 0.47, blue: 0.24),
                                 dark:  Color(red: 0.45, green: 0.80, blue: 0.53))

    static let card = dynamic(light: .white,
                              dark:  Color(red: 0.20, green: 0.16, blue: 0.13))

    static let title     = dynamic(light: Color(red: 0.35, green: 0.20, blue: 0.08),
                                   dark:  Color(red: 0.96, green: 0.90, blue: 0.80))
    static let subtitle  = dynamic(light: Color(red: 0.45, green: 0.30, blue: 0.16),
                                   dark:  Color(red: 0.82, green: 0.72, blue: 0.60))
    static let cardTitle = dynamic(light: Color(red: 0.25, green: 0.15, blue: 0.06),
                                   dark:  Color(red: 0.97, green: 0.92, blue: 0.84))

    static func brandFont(_ size: CGFloat) -> Font { .custom("Avenir Heavy", size: size, relativeTo: .body) }
    static func bodyFont(_ size: CGFloat)  -> Font { .custom("Avenir", size: size, relativeTo: .body) }

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
    static var accent: LinearGradient {
        LinearGradient(colors: [accentTop, accentBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct WarmBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content.scrollEdgeEffectStyle(.soft, for: .all)
        }
    }
}

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
    func warmBackground() -> some View { modifier(WarmBackground()) }
    func cardStyle(cornerRadius: CGFloat = 16) -> some View { modifier(CardStyle(cornerRadius: cornerRadius)) }
    func clearScrollBackground() -> some View { scrollContentBackground(.hidden) }
}

/// The gradient icon badge of the list rows.
struct IconBadge: View {
    let systemImage: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
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
        .accessibilityHidden(true)
    }
}
