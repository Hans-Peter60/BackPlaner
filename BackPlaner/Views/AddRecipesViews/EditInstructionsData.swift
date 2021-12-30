//
//  EditInstructionsData.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 30.12.21.
//

import SwiftUI
import Combine

struct EditInstructionData: View {
    
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
                    Text(" ").bold()
                    
                    TextField(String(instructions.count), text: $schritt)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onReceive(Just(schritt)) { newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            if filtered != newValue {
                                self.schritt = filtered
                            }
                        }
                    
                    TextField("Sauerteigzutaten vermengen", text: $instruction)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("10 [Minuten]", text: $duration)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onReceive(Just(duration)) { newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                self.duration = filtered
                            }
                        }
                    
                    Button("Add") {
                        
                        // Make sure that the fields are populated
                        let cleanedSchritt     = schritt.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedDuration    = duration.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Check that all the fields are filled in
                        if cleanedSchritt == "" || cleanedInstruction == "" {
                            return
                        }
                        
                        // Create an InstructionFB object and set its properties
                        
                        let iFB         = InstructionFB()
                        iFB.id          = UUID().uuidString
                        iFB.step        = Double(cleanedSchritt) ?? 0
                        iFB.instruction = cleanedInstruction
                        iFB.duration    = Int(cleanedDuration) ?? 0
                        instructions.append(iFB)
                        
                        // Clear text fields
                        schritt     = String((Int(cleanedSchritt) ?? 0) + 1)
                        instruction = ""
                        duration    = ""
                    }
                    .buttonStyle(.bordered)
                }
                
                LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                    
                    ForEach(instructions.indices, id: \.self) { i in
                        
                        TextField("", value: $instructions[i].step, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("", text: $instructions[i].instruction)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("", value: $instructions[i].duration, formatter: GlobalVariables.formatter)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)

                        Button("Del") {
                            instructions.remove(at: i)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .toolbar {
            EditButton()
        }
    }

    func deleteInstruction(at offsets: IndexSet) {
        instructions.remove(atOffsets: offsets)
    }

}
