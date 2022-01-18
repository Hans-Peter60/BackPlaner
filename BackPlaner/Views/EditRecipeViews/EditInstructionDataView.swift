//
//  EditInstructionDataView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 04.01.22.
//

import SwiftUI
import CoreData
import Combine

struct EditInstructionDataView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    var recipeId: NSManagedObjectID
    
    var instructionsRequest: FetchRequest<Instruction>
    var instructions: FetchedResults<Instruction> { instructionsRequest.wrappedValue }
    
    init(recipeId: NSManagedObjectID) {
        self.recipeId = recipeId
        self.instructionsRequest = FetchRequest(entity: Instruction.entity(), sortDescriptors: [], predicate: NSPredicate(format: "recipe == %@", recipeId))
    }

    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    
    @State private var step         = ""
    @State private var instruction  = ""
    @State private var duration     = 0
    @State private var showingSheet = false
    
    @State private var selectedInstructionId: NSManagedObjectID?
        
    var body: some View {
        
        ScrollView {
            
            // MARK: Components
            VStack(alignment: .leading) {
                
                ForEach (instructions.sorted(by: { $0.step < $1.step }), id: \.self) { instruction in
                    
                    Section {
                        
                        LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                            
                            InstructionRowView(instruction: instruction)
                                .onTapGesture {
                                    self.selectedInstructionId = instruction.objectID
                                    self.showingSheet          = true
                                }
                            
                            Button("Del") {
                                viewContext.delete(instruction)
                                
                                do {
                                    try viewContext.save()
                                } catch {
                                    // handle the Core Data error
                                }
                            }
                            .font(Font.custom("Avenir", size: 15))
                            .padding()
                            .foregroundColor(.gray)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSheet ) {
                if selectedInstructionId != nil {
                    EditInstructionView(instructionId: self.selectedInstructionId!)
                        .environment(\.managedObjectContext, self.viewContext)
                }
            }
        }
    }
}


struct EditInstructionView: View {
    
    var instructionId: NSManagedObjectID?
    
    @EnvironmentObject var model: RecipeModel
    
    @Environment(\.presentationMode)     var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    
    @State private var instruction  = ""
    @State private var step         = 0.0
    @State private var duration     = 0
    
    var instructions: Instruction {
        viewContext.object(with: instructionId!) as! Instruction
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
                        TextField("", value: $step, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("...", text: $instruction)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $duration, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .navigationBarTitle(Text("Verarbeitungsschritt ändern"), displayMode: .inline)
                .navigationBarItems(leading: Button("Cancel") {
                    self.presentationMode.wrappedValue.dismiss()
                }, trailing: Button("Done") {
                    self.presentationMode.wrappedValue.dismiss()
                    self.instructions.instruction = self.instruction
                    self.instructions.step        = self.step
                    self.instructions.duration    = self.duration
                    
                    try? self.viewContext.save()
                }
                )
            }
            .frame(height: 120)
            .onAppear {
                self.instruction = self.instructions.instruction
                self.duration    = self.instructions.duration
                self.step        = self.instructions.step
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
    
struct InstructionRowView: View {
    @ObservedObject var instruction: Instruction
    
    var body: some View {

        let step = Rational.decimalPlace(instruction.step, 10)
        Text(step)
        Text(instruction.instruction)
        Text(Rational.displayHoursMinutes(instruction.duration))
    }
}
