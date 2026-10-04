//
//  AddInstructionDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 07.11.21.
//

import SwiftUI
import Combine

struct AddInstructionDataView: View {
    
    @Binding var instructions: [InstructionFB]

    /// The enclosing Form's scroll proxy, used to move the row being edited
    /// clear of the keyboard. Without it the rows still work, they just rely
    /// on the system's own keyboard avoidance.
    var scrollProxy: ScrollViewProxy?
    
    @State private var step        = 1.1
    @State private var instruction = ""
    @State private var duration    = 0

    /// The Form row that holds the keyboard: the entry line or an existing
    /// instruction, by index. All three fields of a row share one value, so
    /// focusing any of them scrolls that whole row into view.
    private enum Row: Hashable {
        case entry
        case instruction(Int)
    }

    @FocusState private var focusedRow: Row?

    // Local layout sized so the four columns fit iPhone portrait without clipping.
    private let gridItemLayout = [GridItem(scaledColumnSize(50), alignment: .leading), GridItem(.flexible(minimum: 110), alignment: .leading), GridItem(scaledColumnSize(56), alignment: .trailing), GridItem(scaledColumnSize(44), alignment: .trailing)]

    // Each instruction is its own Form row, deliberately. As one tall cell the
    // system's keyboard avoidance only ever moved the focused field to the
    // keyboard's very edge, where the keypad's rounded top cut it off. With
    // separate rows the focused one can be scrolled to the middle instead, and
    // swipe-to-delete works as well.
    var body: some View {

        VStack (alignment: .leading) {

            Text("Verarbeitungsschritte:")
                .font(Theme.brandFont(16))
                .foregroundColor(Theme.title)
                .padding(.top, 5)

            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                Text("Schritt").bold()
                Text("Beschreibung").bold()
                Text("Dauer").bold()
                Text(verbatim: " ").bold()

                // The grid header above names each column visually, but a
                // header cell is not a label — every field needs its own.
                TextField("", value: $step, formatter: GlobalVariables.formatter)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRow, equals: .entry)
                    .accessibilityLabel("Schritt")

                TextField("", text:  $instruction)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRow, equals: .entry)
                    .accessibilityLabel("Beschreibung")

                TextField("", value: $duration, formatter: GlobalVariables.formatter)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRow, equals: .entry)
                    .accessibilityLabel("Dauer in Minuten")

                IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Verarbeitungsschritt hinzufügen", controlSize: .regular) {
                    // Make sure that the fields are populated
                    let cleanedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Check that all the fields are filled in
                    if step == 0.0 || cleanedInstruction == "" {
                        return
                    }

                    // Create an InstructionFB object and set its properties
                    let iFB         = InstructionFB()
                    iFB.id          = UUID().uuidString
                    iFB.step        = step
                    iFB.instruction = cleanedInstruction
                    iFB.duration    = duration
                    instructions.append(iFB)

                    // Clear text fields
                    if Double(Int(step)) == step {
                        step += 1
                    }
                    else {
                        step += 0.1
                    }
                    instruction = ""
                    duration    = 0
                }
            }
            .scrollsSidewaysAtLargeText()
        }
        .id(Row.entry)
        .onChange(of: focusedRow) { _, row in
            scrollIntoView(row)
        }

        ForEach(instructions.indices, id: \.self) { i in
            LazyVGrid(columns: gridItemLayout, spacing: 6) {
                TextField("", value: $instructions[i].step, formatter: GlobalVariables.formatter)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRow, equals: .instruction(i))
                    .accessibilityLabel("Schritt")
                TextField("", text:  $instructions[i].instruction)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRow, equals: .instruction(i))
                    .accessibilityLabel("Beschreibung")
                TextField("", value: $instructions[i].duration, formatter: GlobalVariables.formatter)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedRow, equals: .instruction(i))
                    .accessibilityLabel("Dauer in Minuten")
                Text(verbatim: " ")
            }
            .scrollsSidewaysAtLargeText()
            .id(Row.instruction(i))
        }
        .onDelete(perform: deleteInstruction)
    }

    /// Centres the row that just took the keyboard in the space left above it.
    ///
    /// Deliberately not done the moment focus changes: the keyboard is still on
    /// its way up then, and the form only gains the extra room below its last
    /// row (AddRecipeView's `keyboardRoom`) once the keyboard announces itself.
    /// Scrolling right away could therefore not move the last rows past the
    /// keyboard's edge. After the keyboard animation both the room and the
    /// reduced viewport are in place, and centring lands where it should.
    private func scrollIntoView(_ row: Row?) {
        guard let row, let scrollProxy else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            // The user may have moved on in the meantime.
            guard focusedRow == row else { return }
            withAnimation {
                scrollProxy.scrollTo(row, anchor: .center)
            }
        }
    }

    func deleteInstruction(at offsets: IndexSet) {
        instructions.remove(atOffsets: offsets)
    }

}
