//
//  AddInstructionData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 07.11.21.
//

import SwiftUI
import Combine

struct AddInstructionData: View {
    
    @Binding var instructions: [InstructionFB]
    
    @State private var schritt     = 1.1
    @State private var instruction = ""
    @State private var duration    = 0
    
    var body: some View {
        
        VStack (alignment: .leading) {
            
            Group {
                Text("Verarbeitungsschritte:")
                    .bold()
                    .padding(.top, 5)
                
                LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                    Text("Schritt").bold()
                    Text("Beschreibung").bold()
                    Text("Dauer").bold()
                    Text(" ").bold()
                    
                    TextField("", value: $schritt, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("", text:  $instruction)
                        .autocapitalization(.none)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("", value: $duration, formatter: GlobalVariables.formatter)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Add") {
                        
                        // Make sure that the fields are populated
 
                        let cleanedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)

                        
                        // Check that all the fields are filled in
                        if schritt == 0.0 || cleanedInstruction == "" {
                            return
                        }
                        
                        // Create an InstructionFB object and set its properties
                        
                        let iFB         = InstructionFB()
                        iFB.id          = UUID().uuidString
                        iFB.step        = schritt
                        iFB.instruction = cleanedInstruction
                        iFB.duration    = duration
                        instructions.append(iFB)
                        
                        // Clear text fields
                        schritt    += 1
                        instruction = ""
                        duration    = 0
                    }
                    .buttonStyle(.bordered)
                }
                
                LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                    
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
