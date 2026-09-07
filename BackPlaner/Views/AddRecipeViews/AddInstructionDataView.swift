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
    
    @State private var step        = 1.1
    @State private var instruction = ""
    @State private var duration    = 0

    // Local layout sized so the four columns fit iPhone portrait without clipping.
    private let gridItemLayout = [GridItem(.fixed(50), alignment: .leading), GridItem(.flexible(minimum: 110), alignment: .leading), GridItem(.fixed(56), alignment: .trailing), GridItem(.fixed(44), alignment: .trailing)]

    var body: some View {
        
        VStack (alignment: .leading) {
            
            Group {
                Text("Verarbeitungsschritte:")
                    .font(Theme.brandFont(16))
                    .foregroundColor(Theme.title)
                    .padding(.top, 5)
                
                LazyVGrid(columns: gridItemLayout, spacing: 6) {
                    Text("Schritt").bold()
                    Text("Beschreibung").bold()
                    Text("Dauer").bold()
                    Text(" ").bold()
                    
                    TextField("", value: $step, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("", text:  $instruction)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("", value: $duration, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    
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
                
                LazyVGrid(columns: gridItemLayout, spacing: 6) {
                    
                    ForEach(instructions.indices, id: \.self) { i in
                        
//                        let step = Rational.decimalPlace(i.step, 10)
                        TextField("", value: $instructions[i].step, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("", text:  $instructions[i].instruction)
                            .autocapitalization(.none)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $instructions[i].duration, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text(" ")
                    }
                    .onDelete(perform: deleteInstruction)
                }
            }
        }
    }

    func deleteInstruction(at offsets: IndexSet) {
        instructions.remove(atOffsets: offsets)
    }

}
