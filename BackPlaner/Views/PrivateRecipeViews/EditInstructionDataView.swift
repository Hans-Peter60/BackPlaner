//
//  EditInstructionDataView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 04.01.22.
//

import BakePlannerCore
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

    // Number, duration and the delete button sit at the top of their row,
    // level with the first line of a description that runs over several
    // lines — as on the recipe page.
    private let instructionGridLayout = [GridItem(scaledColumnSize(40), alignment: .topLeading), GridItem(.flexible(minimum: 100), alignment: .topLeading), GridItem(scaledColumnSize(60), alignment: .topTrailing), GridItem(scaledColumnSize(44), alignment: .topTrailing)]
        
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
    /// The step's time window, both empty for a fixed duration.
    @State private var minimumMinutes: Int?
    @State private var maximumMinutes: Int?
    /// The oven's settings as fields; all empty for a step without them.
    @State private var ovenTemperature: Int?
    @State private var ovenFallingTemperature: Int?
    @State private var steamChoice: SteamChoice

    /// Steam as the picker offers it: not stated, with, without.
    enum SteamChoice: Hashable {
        case notStated, with, without

        init(_ steam: Bool?) {
            switch steam {
            case nil: self = .notStated
            case true?: self = .with
            case false?: self = .without
            }
        }

        var value: Bool? {
            switch self {
            case .notStated: return nil
            case .with: return true
            case .without: return false
            }
        }
    }

    /// Whether the step is the oven's: it bakes, preheats or names an oven
    /// temperature in the text as typed, or carries stored oven settings.
    /// Decided live, so typing "backen" brings the oven fields up.
    private var isOvenStep: Bool {
        instructions.oven != nil
            || BakePlanValidator.isBakingStartInstruction(instruction)
            || BakePlanValidator.isPreheatInstruction(instruction)
            || BakePlan.ovenTemperatureCelsius(in: instruction) != nil
    }

    private var showsOvenSection: Bool { isOvenStep }

    /// The window is for steps the plan may stretch — not the oven's; a
    /// stored window stays editable whatever the wording.
    private var showsWindowSection: Bool { !isOvenStep || instructions.durationWindow != nil }

    init(instruction: Instruction) {
        self.instructions = instruction
        _instruction = State(initialValue: instruction.instruction)
        _step = State(initialValue: instruction.step)
        _duration = State(initialValue: instruction.duration)
        _minimumMinutes = State(initialValue: instruction.durationWindow?.lowerBound)
        _maximumMinutes = State(initialValue: instruction.durationWindow?.upperBound)
        // A step without stored settings starts with what its wording says,
        // so an oven step is filled in as the plan reads it; "Fertig" keeps it.
        let oven = instruction.oven ?? BakePlan.suggestedOvenSettings(in: instruction.instruction)
        _ovenTemperature = State(initialValue: oven?.temperature)
        _ovenFallingTemperature = State(initialValue: oven?.fallingTo)
        _steamChoice = State(initialValue: SteamChoice(oven?.steam))
    }
    
    var gridItemLayoutInstructions = [GridItem(scaledColumnSize(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(scaledColumnSize(80), alignment: .leading)]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: gridItemLayoutInstructions, spacing: 6) {
                        
                        Text("Nr.").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                        
                        VStack {
                            NumberField("", value: $step)
                                .textFieldStyle(.roundedBorder)
                                .padding(.bottom, 150)
                                .accessibilityLabel("Nummer")
                            
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
                            DurationField(minutes: $duration)
                                .textFieldStyle(.roundedBorder)
                                .padding(.bottom, 150)
                                .accessibilityLabel("Dauer")
                            
                            Spacer()
                        }
                    }
                    .scrollsSidewaysAtLargeText()
                }

                // MARK: Time window — how short and how long the step may take.
                // Not for an oven step, whose time is the oven's.
                if showsWindowSection {
                Section {
                    LabeledContent("Mindestens") {
                        OptionalDurationField(minutes: $minimumMinutes)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Mindestens")
                    }
                    LabeledContent("Höchstens") {
                        OptionalDurationField(minutes: $maximumMinutes)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Höchstens")
                    }
                } header: {
                    Text("Zeitfenster")
                } footer: {
                    Text("Der Planer darf den Schritt innerhalb des Fensters dehnen oder kürzen, etwa eine Kühlschrankgare von 12 bis 18 Stunden. Leer lassen, wenn die Dauer fest ist.")
                }
                }

                // MARK: Oven — the settings as fields, taken before the wording.
                // Only for a step that bakes, preheats or names an oven temperature.
                if showsOvenSection {
                Section {
                    LabeledContent("Temperatur") {
                        TextField("°C", value: $ovenTemperature, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Temperatur")
                    }
                    LabeledContent("Fallend auf") {
                        TextField("°C", value: $ovenFallingTemperature, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Fallend auf")
                    }
                    Picker("Schwaden", selection: $steamChoice) {
                        Text("Nicht angegeben").tag(SteamChoice.notStated)
                        Text("Mit Schwaden").tag(SteamChoice.with)
                        Text("Ohne Schwaden").tag(SteamChoice.without)
                    }
                } header: {
                    Text("Ofen")
                } footer: {
                    Text("Die Felder gelten vor dem Wortlaut: „Backofen anstellen“ nennt die Temperatur, „Fallend auf“ erzeugt den Schritt zum Zurückdrehen, und zwei Brote bei gleicher Temperatur dürfen sich einen Ofen teilen. Leer lassen, wenn der Schritt nichts mit dem Ofen zu tun hat.")
                }
                }
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
                        // Both bounds, in order, or no window at all.
                        self.instructions.durationWindow = DurationWindow.range(minimum: minimumMinutes,
                                                                                maximum: maximumMinutes)
                        self.instructions.oven = OvenSettings.from(temperature: ovenTemperature,
                                                                   fallingTo: ovenFallingTemperature,
                                                                   steam: steamChoice.value)

                        if let recipe = self.instructions.recipe {
                            // An edited step that now describes repeated
                            // folds gets one step per fold, as on import.
                            TimedFoldExpansion.expand(in: recipe, context: viewContext)
                            recalculateInstructionTimes(for: recipe)
                        }

                        try? self.viewContext.save()
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
        VStack(alignment: .trailing, spacing: 0) {
            Text(Rational.displayHoursMinutes(instruction.duration))
            // The step's time window, when it has one.
            if let window = instruction.durationWindow {
                Text(DurationWindow.text(window))
                    .font(Theme.bodyFont(11))
                    .foregroundColor(Theme.subtitle)
            }
        }
    }
}
