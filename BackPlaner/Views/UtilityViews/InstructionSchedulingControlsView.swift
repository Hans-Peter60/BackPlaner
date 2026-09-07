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

    private var isPhonePortrait: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: isPhonePortrait ? 6 : 12) {
            Toggle(isOn: $changeDurations) {
                VStack(alignment: .leading, spacing: -2) {
                    Text("Dauer")
                    Text("ändern")
                }
            }
                .font(Theme.bodyFont(isPhonePortrait ? 13 : 15))
                .controlSize(isPhonePortrait ? .mini : .regular)
                .fixedSize(horizontal: true, vertical: false)

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
            .frame(width: isPhonePortrait ? 70 : 150)
            .accessibilityLabel("Starten ab oder fertig bis")

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: dateTime) { _, newValue in
            onDateChanged(newValue)
        }
    }
}
