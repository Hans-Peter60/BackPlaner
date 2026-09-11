import SwiftUI

struct IconActionButton: View {
    enum Style {
        case primary
        case destructive
        case neutral
    }

    let systemImage: String
    let style: Style
    let accessibilityLabel: LocalizedStringKey
    let title: LocalizedStringKey?
    let controlSize: ControlSize
    let action: () -> Void

    init(systemImage: String,
         style: Style,
         accessibilityLabel: LocalizedStringKey,
         title: LocalizedStringKey? = nil,
         controlSize: ControlSize = .large,
         action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.style = style
        self.accessibilityLabel = accessibilityLabel
        self.title = title
        self.controlSize = controlSize
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .imageScale(.large)
                    .foregroundColor(foregroundColor)
                if let title = title {
                    Text(title)
                        .foregroundColor(foregroundColor)
                        // Without this the title reports its whole one-line
                        // width as the button's minimum — 457 pt for "Als
                        // eigenes Rezept speichern" at the largest text size.
                        // A vertical ScrollView adopts its content's minimum
                        // width, so that one label stretched the entire recipe
                        // screen to 615 pt on a 402 pt phone and clipped it at
                        // both edges. Flexible horizontally, the minimum drops
                        // to the longest single word and the title wraps.
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .accessibilityLabel(Text(accessibilityLabel))
            // Only an icon-only button gets the hand-tuned 22 pt box. With a
            // title, a fixed ideal height keeps the button at one line's worth
            // of space while the wrapped text needs four — the label then spills
            // out of its own button and over whatever sits beside it.
            .frame(idealWidth:  title == nil ? 22 : nil,
                   idealHeight: title == nil ? 22 : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(controlSize)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .blue
        case .destructive: return .red
        case .neutral: return .primary
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            IconActionButton(systemImage: "plus.circle.fill", style: .primary, accessibilityLabel: "Hinzufügen") {}
            IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Löschen") {}
            IconActionButton(systemImage: "square.and.pencil", style: .neutral, accessibilityLabel: "Bearbeiten") {}
        }
        HStack(spacing: 16) {
            IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Hinzufügen", controlSize: .regular) {}
            IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Löschen", controlSize: .regular) {}
            IconActionButton(systemImage: "square.and.pencil", style: .neutral, accessibilityLabel: "Bearbeiten", controlSize: .regular) {}
        }
    }
    .padding()
}
