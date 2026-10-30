import SwiftUI

struct ContentView: View {
    @State var model = AppModel()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(verbatim: "BakePlanner")
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(Palette.accent(colorScheme))

                if let loadError = model.loadError {
                    Text("Die Rezepte konnten nicht geladen werden.")
                    Text(verbatim: loadError)
                        .font(.caption)
                } else {
                    Text("Rezepte auf diesem Gerät: \(model.recipeCount)")
                }
            }
            .padding()
        }
        .task {
            model.load()
        }
    }
}

/// The colours of BakePlanner on iOS (Theme.swift in the iOS app): warm
/// flour and crust tones, darker at night.
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
}
