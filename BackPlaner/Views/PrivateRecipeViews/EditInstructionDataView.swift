//
//  EditInstructionDataView.swift
//  PetersBackPlaner
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
    @State private var selectedInstruction: Instruction?

    private let instructionGridLayout = [GridItem(scaledColumnSize(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(60), alignment: .trailing), GridItem(scaledColumnSize(44), alignment: .trailing)]
        
    var body: some View {
        
        ScrollView {
            
            // MARK: Components
            VStack(alignment: .leading) {
                
                ForEach (instructions.sorted(by: { $0.step < $1.step }), id: \.self) { instruction in
                    
                    Section {
                        
                        LazyVGrid(columns: instructionGridLayout, spacing: 6) {
                            
                            InstructionRowView(instruction: instruction)
                                .onTapGesture {
                                    selectedInstruction = instruction
                                }
                                // A tap gesture alone carries no semantics: without
                                // the button trait VoiceOver announces the row as
                                // plain text and never offers to activate it.
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Verarbeitungsschritt bearbeiten")
                            
                            IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Verarbeitungsschritt löschen", controlSize: .regular) {
                                viewContext.delete(instruction)
                                
                                do {
                                    try viewContext.save()
                                } catch {
                                    // handle the Core Data error
                                }
                            }
                        }
                        .scrollsSidewaysAtLargeText()
                    }
                }
            }
        }
        .sheet(item: $selectedInstruction) { instruction in
            EditInstructionView(instruction: instruction)
                .environment(\.managedObjectContext, self.viewContext)
        }
    }
}


struct EditInstructionView: View {
    
    @ObservedObject var instructions: Instruction
    
    @EnvironmentObject var model: RecipeModel
    
    @Environment(\.presentationMode)     var presentationMode
    @Environment(\.managedObjectContext) var viewContext
    
    @State private var instruction: String
    @State private var step: Double
    @State private var duration: Int
    
    init(instruction: Instruction) {
        self.instructions = instruction
        _instruction = State(initialValue: instruction.instruction)
        _step = State(initialValue: instruction.step)
        _duration = State(initialValue: instruction.duration)
    }
    
    var gridItemLayoutInstructions = [GridItem(scaledColumnSize(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(scaledColumnSize(80), alignment: .leading)]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: gridItemLayoutInstructions, spacing: 6) {
                        
                        Text("Schritt").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                        
                        VStack {
                            TextField("", value: $step, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .padding(.bottom, 150)
                                .accessibilityLabel("Schritt")
                            
                            Spacer()
                        }
            
                        TextEditor(text: $instruction)
                            .padding(4)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.fieldBorder))
                            .multilineTextAlignment(.leading)
                            .frame(minWidth: 200, idealWidth: 500, maxWidth: 600, minHeight: 200, idealHeight: 200, maxHeight: 200, alignment: .leading)
                            .padding(.top, 5)
                            .accessibilityLabel("Beschreibung")
                        
                        VStack {
                            TextField("", value: $duration, formatter: GlobalVariables.formatter)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .padding(.bottom, 150)
                                .accessibilityLabel("Dauer in Minuten")
                            
                            Spacer()
                        }
                    }
                    .scrollsSidewaysAtLargeText()
                }
                .navigationTitle(Text("Verarbeitungsschritt ändern"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            self.presentationMode.wrappedValue.dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") {
                            self.presentationMode.wrappedValue.dismiss()
                            self.instructions.instruction = self.instruction
                            self.instructions.step        = self.step
                            self.instructions.duration    = self.duration

                            if let recipe = self.instructions.recipe {
                                recalculateInstructionTimes(for: recipe)
                            }

                            try? self.viewContext.save()
                        }
                    }
                }
            }
        }
    }

    private func recalculateInstructionTimes(for recipe: Recipe) {
        var instructionsFB = recipe.instructionsArray.map { instruction in
            let instructionFB = InstructionFB()
            instructionFB.instruction = instruction.instruction
            instructionFB.step        = instruction.step
            instructionFB.startTime   = instruction.startTime
            instructionFB.duration    = instruction.duration
            instructionFB.componentName = instruction.componentName
            return instructionFB
        }

        instructionsFB = Rational.calculateStartTimes(
            instructionsFB,
            Date(),
            dependencies: Rational.ComponentDependency.from(recipe.componentsArray)
        )

        for (instruction, instructionFB) in zip(recipe.instructionsArray, instructionsFB) {
            instruction.startTime = instructionFB.startTime ?? 0
            instruction.date      = instructionFB.date
        }

        recipe.prepTime = GlobalVariables.totalDuration
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
