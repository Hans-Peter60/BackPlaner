import SwiftUI

/// CookPlanner's colours on Android, the iPhone's (Theme.swift there) as
/// functions of the colour scheme — Skip has no dynamic colours.
enum Palette {
    static func backgroundTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.16, green: 0.12, blue: 0.09) : Color(red: 0.98, green: 0.93, blue: 0.82)
    }

    static func backgroundBottom(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.09, green: 0.07, blue: 0.05) : Color(red: 0.93, green: 0.80, blue: 0.62)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.61, green: 0.41, blue: 0.22) : Color(red: 0.62, green: 0.41, blue: 0.21)
    }

    static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.89, green: 0.575, blue: 0.31) : Color(red: 0.48, green: 0.29, blue: 0.13)
    }

    static func title(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.96, green: 0.90, blue: 0.80) : Color(red: 0.35, green: 0.20, blue: 0.08)
    }

    static func subtitle(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.82, green: 0.72, blue: 0.60) : Color(red: 0.45, green: 0.30, blue: 0.16)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.20, green: 0.16, blue: 0.13) : .white
    }

    static func good(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.40, green: 0.78, blue: 0.47) : Color(red: 0.16, green: 0.47, blue: 0.24)
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.00, green: 0.34, blue: 0.27) : Color(red: 0.87, green: 0.20, blue: 0.16)
    }
}

/// The warm gradient behind every screen.
struct WarmBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// The iPhone's card: white, rounded, with a soft shadow.
struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Palette.card(colorScheme))
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
