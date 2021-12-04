//
//  AddInstructionData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 07.11.21.
//

import SwiftUI

struct AddInstructionData: View {
    
    @Binding var instructions: [InstructionFB]
    
    @State private var schritt = ""
    @State private var instruction = ""
    @State private var duration = ""
    
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
                    Text("").bold()
                    
                    TextField("1", text: $schritt)
                    // .frame(width:20)
                    
                    TextField("Sauerteigzutaten vermengen", text: $instruction)
                    
                    TextField("10 [Minuten]", text: $duration)
                    // .frame(width:20)
                    
                    Button("Add") {
                        
                        // Make sure that the fields are populated
                        let cleanedSchritt = schritt.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedDuration = duration.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Check that all the fields are filled in
                        if cleanedSchritt == "" || cleanedInstruction == "" {
                            return
                        }
                        
                        // Create an InstructionFB object and set its properties
                        
                        let iFB = InstructionFB()
                        iFB.id = UUID().uuidString
                        iFB.step = Double(cleanedSchritt) ?? 0
                        iFB.instruction = cleanedInstruction
                        iFB.duration = Int(cleanedDuration) ?? 0
                        instructions.append(iFB)
                        
                        // Clear text fields
                        schritt = String((Int(cleanedSchritt) ?? 0) + 1)
                        instruction = ""
                        duration = ""
                    }
                    .buttonStyle(.bordered)
                }
                
                LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                    ForEach(instructions.sorted(by: { $0.step > $1.step })) { i in
                        let step = Rational.decimalPlace(i.step, 10)
                        Text(step)
                        Text(i.instruction)
                        Text(Rational.displayHoursMinutes(i.duration)) // + Rational.displayHoursMinutes(i.startTime ?? 0))
                        Text("")
                    }
                }
            }
        }
    }
}
