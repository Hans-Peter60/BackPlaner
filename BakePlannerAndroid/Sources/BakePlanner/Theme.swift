import SwiftUI

/// The look of BakePlanner on iOS (Theme.swift there), brought to Android:
/// the warm palette as functions of the colour scheme (Skip has no dynamic
/// colours), Nunito in place of Avenir, and the white card with its soft
/// shadow that every screen of the iPhone puts its content on.
extension Palette {
    /// The accent as a foreground: dark enough on a card and on the
    /// gradient, lighter at night.
    static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.89, green: 0.575, blue: 0.31) : Color(red: 0.48, green: 0.29, blue: 0.13)
    }

    static func title(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.96, green: 0.90, blue: 0.80) : Color(red: 0.35, green: 0.20, blue: 0.08)
    }

    static func subtitle(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.82, green: 0.72, blue: 0.60) : Color(red: 0.45, green: 0.30, blue: 0.16)
    }

    static func cardTitle(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.97, green: 0.92, blue: 0.84) : Color(red: 0.25, green: 0.15, blue: 0.06)
    }

    /// The card surface: white by day, a warm dark surface at night.
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.20, green: 0.16, blue: 0.13) : .white
    }

    static func warning(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.00, green: 0.624, blue: 0.039) : Color(red: 0.655, green: 0.383, blue: 0.00)
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.00, green: 0.34, blue: 0.27) : Color(red: 0.87, green: 0.20, blue: 0.16)
    }
}

/// The app's typeface. On Android every text style is Nunito at the
/// system's size for that style (so it still follows the user's text
/// size); on Apple platforms the system font, as the Android app is not
/// shipped there. The iPhone's "brand" texts are Avenir Heavy: here the
/// same style in a heavier weight.
enum AppFont {
    /// The family for a weight. Compose does not pick a weight out of a
    /// family loaded from a Typeface, so each weight the app uses is a
    /// family of its own in res/font (nunito.xml, nunito_semibold.xml …),
    /// named the way SkipUI looks fonts up: "Nunito-SemiBold" becomes
    /// "nunito_semibold".
    private static func family(for weight: Font.Weight?) -> String {
        switch weight {
        case .medium: "Nunito-Medium"
        case .semibold: "Nunito-SemiBold"
        case .bold: "Nunito-Bold"
        case .heavy, .black: "Nunito-ExtraBold"
        default: "Nunito"
        }
    }

    /// Nunito at a text style's size.
    static func text(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        #if os(Android)
        return Font.custom(family(for: weight), size: 0, relativeTo: style)
        #else
        let font = Font.system(style)
        return weight.map { font.weight($0) } ?? font
        #endif
    }

    /// Nunito at a fixed size, for the chart and other tight places.
    static func size(_ size: Double, weight: Font.Weight? = nil) -> Font {
        #if os(Android)
        return Font.custom(family(for: weight), size: .init(size))
        #else
        let font = Font.system(size: .init(size))
        return weight.map { font.weight($0) } ?? font
        #endif
    }

    /// The style in bold, for a `Text` that asked for `.bold()`: the weight
    /// has to be chosen with the family (see above).
    static func bold(_ style: Font.TextStyle) -> Font { text(style, weight: .bold) }

    static var largeTitle: Font { text(.largeTitle, weight: .bold) }
    static var title: Font { text(.title, weight: .bold) }
    static var title2: Font { text(.title2, weight: .bold) }
    static var title3: Font { text(.title3, weight: .bold) }
    static var headline: Font { text(.headline, weight: .semibold) }
    static var subheadline: Font { text(.subheadline) }
    static var body: Font { text(.body) }
    static var callout: Font { text(.callout) }
    static var footnote: Font { text(.footnote) }
    static var caption: Font { text(.caption) }
    static var caption2: Font { text(.caption2) }
}

/// The iPhone's card: white, rounded, with a soft shadow, around a block
/// of content.
struct CardStyle: ViewModifier {
    var cornerRadius = 16.0
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Palette.card(colorScheme))
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            )
    }
}

extension View {
    /// Wraps the content in the standard white, rounded, shadowed card.
    func cardStyle(cornerRadius: Double = 16) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }
}
