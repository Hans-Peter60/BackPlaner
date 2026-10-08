//
//  BakeHistoryFactsFormSection.swift
//  BackPlaner
//
//  The form rows for the structured part of a bake-history entry — the
//  temperatures, the proof times as they really were, the flour, and crumb
//  and oven spring in a few words. Shared by the "+ Historie" tab and the
//  editing form of an existing entry, so both record the same things.
//

import SwiftUI

struct BakeHistoryFactsFormSection: View {

    @Binding var facts: BakeHistoryFacts

    // At the accessibility text sizes a title, a field, a unit and the
    // "Fertig" button no longer share one row.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Field: Hashable {
        case roomTemperature, doughTemperature, bulkProof, finalProof, flour, outcome
    }

    @FocusState private var focusedField: Field?

    // The numeric fields are edited as text and parsed on every change, so
    // "22," on the way to "22,5" is never rejected and never reformatted
    // under the typist's fingers.
    @State private var roomText  = ""
    @State private var doughText = ""
    @State private var bulkText  = ""
    @State private var finalText = ""

    var body: some View {
        Section {
            numberRow(.roomTemperature, text: $roomText, field: .roomTemperature,
                      unit: "°C", keyboard: .decimalPad)
            numberRow(.doughTemperature, text: $doughText, field: .doughTemperature,
                      unit: "°C", keyboard: .decimalPad)
            numberRow(.bulkProof, text: $bulkText, field: .bulkProof,
                      unit: "Min", keyboard: .numberPad, hint: durationHint(bulkText))
            numberRow(.finalProof, text: $finalText, field: .finalProof,
                      unit: "Min", keyboard: .numberPad, hint: durationHint(finalText))

            textRow(.flour, text: $facts.flour, field: .flour,
                    prompt: "z. B. Weizen 550, Dinkel 630")

            VStack(alignment: .leading, spacing: 10) {
                textRow(.outcome, text: $facts.outcome, field: .outcome,
                        prompt: "Stichworte, durch Komma getrennt")
                keywordRow(title: "Krume", keywords: BakeHistoryFacts.OutcomeKeyword.crumb)
                keywordRow(title: "Ofentrieb", keywords: BakeHistoryFacts.OutcomeKeyword.ovenSpring)
            }
        } header: {
            Text("Messwerte und Ergebnis")
        } footer: {
            Text("Beim nächsten Planen dieses Rezepts zeigt die Backansicht diese Angaben als „Letztes Mal“.")
        }
        .font(Theme.bodyFont(16))
        .onAppear(perform: loadTexts)
        // The owner may fill `facts` after this appeared (the editing form
        // loads its entry in onAppear), so follow it — but never overwrite a
        // field that already reads as the same value, or typing would stall.
        .onChange(of: facts) { _, _ in loadTexts() }
        .onChange(of: roomText)  { _, text in facts.roomTemperature  = BakeHistoryFacts.parseTemperature(text) }
        .onChange(of: doughText) { _, text in facts.doughTemperature = BakeHistoryFacts.parseTemperature(text) }
        .onChange(of: bulkText)  { _, text in facts.bulkProofMinutes  = BakeHistoryFacts.parseMinutes(text) }
        .onChange(of: finalText) { _, text in facts.finalProofMinutes = BakeHistoryFacts.parseMinutes(text) }
    }

    private func loadTexts() {
        if BakeHistoryFacts.parseTemperature(roomText) != facts.roomTemperature {
            roomText = BakeHistoryFacts.temperatureInput(facts.roomTemperature)
        }
        if BakeHistoryFacts.parseTemperature(doughText) != facts.doughTemperature {
            doughText = BakeHistoryFacts.temperatureInput(facts.doughTemperature)
        }
        if BakeHistoryFacts.parseMinutes(bulkText) != facts.bulkProofMinutes {
            bulkText = BakeHistoryFacts.minutesInput(facts.bulkProofMinutes)
        }
        if BakeHistoryFacts.parseMinutes(finalText) != facts.finalProofMinutes {
            finalText = BakeHistoryFacts.minutesInput(facts.finalProofMinutes)
        }
    }

    /// "3h 30m" under a minutes field once it holds an hour or more, so 210
    /// does not have to be worked out in the head.
    private func durationHint(_ text: String) -> String? {
        guard let minutes = BakeHistoryFacts.parseMinutes(text), minutes >= 60 else { return nil }
        return BakeHistoryFacts.durationText(minutes)
    }

    // MARK: Rows

    private func numberRow(_ kind: BakeHistoryFacts.Kind,
                           text: Binding<String>,
                           field: Field,
                           unit: LocalizedStringKey,
                           keyboard: UIKeyboardType,
                           hint: String? = nil) -> some View {
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))

        return VStack(alignment: .leading, spacing: 4) {
            rowLayout {
                Text(kind.title)
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }

                HStack(spacing: 6) {
                    TextField("", text: text)
                        .keyboardType(keyboard)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 56, maxWidth: 90)
                        .focused($focusedField, equals: field)
                        // The field has no visible title of its own; the
                        // row's title is what it means.
                        .accessibilityLabel(Text(kind.title))

                    Text(unit)
                        .foregroundColor(Theme.subtitle)

                    // The number pads have no Return key, and a keyboard
                    // toolbar never shows inside the recipe TabView (see
                    // ServingScaleControl), so the button sits in the row
                    // while the field is edited.
                    if focusedField == field {
                        Button("Fertig") { focusedField = nil }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .font(Theme.bodyFont(15))
                    }
                }
            }

            if let hint {
                Text(verbatim: "= \(hint)")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
            }
        }
        .animation(.default, value: focusedField)
    }

    private func textRow(_ kind: BakeHistoryFacts.Kind,
                         text: Binding<String>,
                         field: Field,
                         prompt: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind.title)
                .foregroundColor(Theme.cardTitle)
            TextField(kind.title, text: text, prompt: Text(prompt))
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .autocorrectionDisabled()
        }
    }

    /// The chips of one group. A tap puts the word into the field or takes it
    /// out again; a selected chip carries a checkmark, not only a colour.
    private func keywordRow(title: LocalizedStringKey,
                            keywords: [BakeHistoryFacts.OutcomeKeyword]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.bodyFont(13))
                .foregroundColor(Theme.subtitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keywords) { keyword in
                        keywordChip(keyword.text)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func keywordChip(_ word: String) -> some View {
        let isSelected = BakeHistoryFacts.contains(word, in: facts.outcome)

        return Button {
            facts.outcome = BakeHistoryFacts.toggling(word, in: facts.outcome)
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(verbatim: word)
                    .font(Theme.bodyFont(14))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : Theme.accentText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accentText.opacity(0.12)))
            )
        }
        // Plain, so each chip takes its own tap instead of the whole form row.
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
