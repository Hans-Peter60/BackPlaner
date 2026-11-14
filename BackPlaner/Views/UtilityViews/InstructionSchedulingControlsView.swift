import BakePlannerCore
import SwiftUI

struct InstructionSchedulingControlsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Binding var changeDurations: Bool
    @Binding var startSelection: Int
    @Binding var dateTime: Date

    let dateRange: ClosedRange<Date>
    let onDateTapped: () -> Void
    let onDateChanged: (Date) -> Void
    /// The ovens to choose from and the chosen one's id; the row only shows
    /// with two or more ovens.
    var ovenProfiles: [OvenProfile] = []
    var ovenProfileID: Binding<String>? = nil

    private var isPhonePortrait: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            if let ovenProfileID, ovenProfiles.count > 1 {
                OvenChoiceMenu(profiles: ovenProfiles, selection: ovenProfileID)
                    .font(Theme.bodyFont(isPhonePortrait ? 13 : 15))
                    .accessibilityIdentifier("plan.oven")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: dateTime) { _, newValue in
            onDateChanged(newValue)
        }
    }

    private var controls: some View {
        Group {
            if isPhonePortrait {
                // One row while it fits. In English and French the toggle's
                // label and the picker's words are wider than in German, and
                // the row pushed the time past the card's edge; the controls
                // then go on two rows, with the picker at its natural width.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        durationToggle
                        anchorPicker.frame(width: 70)
                        datePicker
                    }
                    .modifier(ControlsHandle())
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            durationToggle
                            anchorPicker.fixedSize()
                        }
                        datePicker
                    }
                    .modifier(ControlsHandle())
                }
            } else {
                HStack(spacing: 12) {
                    durationToggle
                    anchorPicker.frame(width: 150)
                    datePicker
                }
                .modifier(ControlsHandle())
            }
        }
    }

    /// The accessibility element the UI tests scroll to. On the laid-out
    /// container itself, not around the ViewThatFits: there the reported
    /// frame did not match the controls on screen, and the screenshot test
    /// stopped scrolling with them halfway down the picture.
    private struct ControlsHandle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("plan.controls")
        }
    }

    private var durationToggle: some View {
        Toggle(isOn: $changeDurations) {
            // One string with its own line break: as two separate Text
            // views the words could not be reordered, and no language
            // other than German read correctly.
            Text("Dauer\nändern")
                .multilineTextAlignment(.leading)
        }
        .font(Theme.bodyFont(isPhonePortrait ? 13 : 15))
        .controlSize(isPhonePortrait ? .mini : .regular)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var anchorPicker: some View {
        Picker("Startzeit", selection: $startSelection) {
            if isPhonePortrait {
                Text("Ab").tag(0)
                Text("Bis").tag(1)
            } else {
                Text("Starten ab").tag(0)
                Text("Fertig bis").tag(1)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Starten ab oder fertig bis")
    }

    private var datePicker: some View {
        DatePicker(
            "Datum und Uhrzeit",
            selection: $dateTime,
            in: dateRange,
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .environment(\.locale, AppSettings.locale)
        .font(Theme.bodyFont(isPhonePortrait ? 12 : 13))
        .layoutPriority(1)
        .onTapGesture(perform: onDateTapped)
    }
}

/// The oven a plan is baked in, as a menu: the oven symbol, the chosen
/// name and a chevron, in the caller's font — a menu-style Picker would
/// keep its own size next to the small planning controls.
struct OvenChoiceMenu: View {
    let profiles: [OvenProfile]
    @Binding var selection: String

    private var chosenName: String {
        OvenProfiles.selected(from: profiles, selectedID: selection)?.name ?? ""
    }

    var body: some View {
        Menu {
            Picker("Ofen", selection: $selection) {
                ForEach(profiles) { profile in
                    Text(profile.name).tag(profile.id.uuidString)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "oven")
                Text(chosenName)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .foregroundColor(Theme.accentText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ofen")
        .accessibilityValue(chosenName)
    }
}
