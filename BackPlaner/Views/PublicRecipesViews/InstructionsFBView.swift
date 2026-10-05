//
//  InstructionsFBView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 24.11.21.
//

import SwiftUI
import CoreData

struct InstructionsFBView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.locale) private var locale
    @EnvironmentObject var modelFB:      RecipeFBModel
    @EnvironmentObject var model:        RecipeModel
    
    var recipeFB: RecipeFB
    var recipeId: NSManagedObjectID?
    var languageCode = ""
    
    @State private var dateTime = GlobalVariables.dateTimePicker
    @State private var dateTimeStartSelection     = 0
    @State var         selectedServingSize        = AppSettings.storedServingSize
    /// A target dough weight in grams; overrides the serving-size factor.
    @State private var targetWeight: Int?
    @State private var showingNotificationMessage = false
    @State private var changeDurationsFlag        = false
    @State private var showingAlert               = false
    // Summary shown after reminders are scheduled, so the action is no longer opaque.
    @State private var reminderCount              = 0
    @State private var reminderOvenOnText         = ""
    @State private var reminderOvenTemperature    = ""
    @State private var reminderFinishText         = ""

    /// 1.0 is the recipe as stored.
    private var servingScale: Double {
        ServingScale.factor(servingSize: selectedServingSize, targetWeight: targetWeight, baseWeight: recipeFB.totalWeight)
    }
    // Findings of the bake-plan check (day window, overlapping bakes, bake pause).
    @State private var planIssues                 = [BakePlanIssue]()
    @State private var showingPlanError           = false
    @State private var planErrorMessage           = ""
    @State private var reminderHintText           = ""
    // Publishing a so-far private recipe into the shared database.
    @State private var showPublishWarning         = false
    @State private var showPublishEULA            = false
    @State private var isPublishing               = false
    @State private var publishErrorMessage: String?
    @State private var showPublishedConfirmation  = false

    // Saving a public recipe onto the device gave no feedback at all, so it
    // was impossible to tell whether the tap had done anything.
    @State private var showSavedConfirmation      = false
    @State private var saveErrorMessage: String?
    /// Asks whether a new plan replaces the recipe's existing one or joins it.
    @State private var showingPlanChoice = false

    /// Whether the recipe already has planned steps.
    private var hasExistingPlan: Bool {
        BakePlanScheduler.hasPlan(recipeName: recipeFB.name, in: viewContext)
    }

    var startDates = [Double:Date]()

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>
    
    @State private var oldName       = ""
    @State private var ingredientsFB = [IngredientFB]()
    @State private var index         = -1

    @State private var durations: [String] = []

    // Narrow the step ("S."), duration and start columns so the description column stays as wide as possible.
    var gridItemLayoutInstructions = [GridItem(scaledColumnSize(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(60), alignment: .trailing), GridItem(scaledColumnSize(90), alignment: .trailing)]

    let dateRange: ClosedRange<Date> = GlobalVariables.planningDateRange()
    
    var manager:LocalNotificationManager = LocalNotificationManager()

    /// The minutes typed into the duration field of step `index`. The list
    /// grows with the first entry into a field instead of having a fixed
    /// length: at 24 (own recipes) and 34 (public ones) entries, longer
    /// recipes lost their duration fields, and the public screen hid every
    /// step after the 34th.
    private func durationBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { index < durations.count ? durations[index] : "" },
            set: { value in
                if durations.count <= index {
                    durations.append(contentsOf: Array(repeating: "", count: index - durations.count + 1))
                }
                durations[index] = value
            }
        )
    }

    var body: some View {
        
        GeometryReader { fullView in
            
            ScrollView(.vertical, showsIndicators: false) {
                
                VStack (alignment: .leading) {
                    
                    PortraitAdaptiveStack(spacing: 12) {
                        NavigationLink(
                            destination: ShowBigImageView(image: (GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()).jpegData(compressionQuality: 1.0) ?? Data() )
                        ) {
                            Image(uiImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                                .cornerRadius(5)
                        }
                        // The image is the link's only content, so without this the
                        // link would be announced with no name at all.
                        .accessibilityLabel("Rezeptbild vergrößern")

                        VStack(alignment: .leading, spacing: 10) {
                            Text(recipeFB.name)
                                .font(Theme.brandFont(18))
                                .foregroundColor(Theme.title)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            IconActionButton(systemImage: "square.and.arrow.down", style: .primary, accessibilityLabel: "Als eigenes Rezept speichern", title: "Als eigenes Rezept speichern", controlSize: .regular) {
                                do {
                                    _ = try model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipeFB, context: viewContext, recipeImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                                    showSavedConfirmation = true
                                } catch {
                                    saveErrorMessage = error.localizedDescription
                                }
                            }

                            // Publishing is only offered for a recipe that is
                            // private so far — a public one would just be
                            // duplicated.
                            if recipeFB.visibility == .authorOnly {
                                IconActionButton(systemImage: RecipeStoragePreference.publicRecipe.symbolName, style: .primary, accessibilityLabel: "Als öffentliches Rezept speichern", title: "Als öffentliches Rezept speichern", controlSize: .regular) {
                                    showPublishWarning = true
                                }
                                .disabled(isPublishing)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                    
                    Group {
                        // MARK: Serving size or target dough weight
                        ServingScaleControl(selectedServingSize: $selectedServingSize,
                                            targetWeight: $targetWeight,
                                            baseWeight: recipeFB.totalWeight)

                        PortraitAdaptiveStack(spacing: 12) {
                            Text("Gewicht: \(Int((recipeFB.totalWeight * servingScale).rounded()), format: .number) g")
                                .font(Theme.bodyFont(15))
                            
                            // MARK: Url-Link
                            if let url = URL(string: recipeFB.urlLink) {
                                Link("Link zum Rezept", destination: url)
                                    .padding(.top, 2)
                                    .font(Theme.brandFont(15))
                            }
                        }
                    }
                    
                    TotalIngredientsView(
                        ingredients: recipeFB.components.flatMap(\.ingredients).map {
                            TotalIngredientData(
                                name: $0.name,
                                unit: $0.unit,
                                weight: $0.weight,
                                numerator: $0.num,
                                denominator: $0.denom
                            )
                        },
                        componentNames: recipeFB.components.map(\.name),
                        scale: servingScale
                    )

                    // MARK: Components
                    ComponentColumnsView(components: ComponentColumn.columns(of: recipeFB.components),
                                         scale: servingScale)

                    // MARK: Selections
                    InstructionSchedulingControlsView(
                        changeDurations: $changeDurationsFlag,
                        startSelection: $dateTimeStartSelection,
                        dateTime: $dateTime,
                        dateRange: dateRange,
                        onDateTapped: showNotificationMessage,
                        onDateChanged: setGlobalDateTime
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .onChange(of: dateTimeStartSelection) { _, _ in
                        refreshPlanIssues()
                    }

                    BakePlanIssuesView(issues: planIssues)


                    // MARK: Instructions
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Verarbeitungsschritte:")
                                .font(Theme.brandFont(16))
                                .foregroundColor(Theme.title)
                                .padding([.bottom, .top], 5)
                            
                            Spacer()
                            
                            Text("Bearbeitungsdauer: \(Rational.displayHoursMinutes(recipeFB.prepTime))")
                                .font(Theme.bodyFont(16))
                                .padding([.trailing], 5)
                        }
                        
                        LazyVGrid(columns: gridItemLayoutInstructions, spacing: 6) {
                            Text("S.").bold()
                            Text("Beschreibung").bold()
                            Text("Dauer").bold()
                            
                            if changeDurationsFlag {
                                
                                Text("Dauer [Min]").bold()
                                
                                ForEach(recipeFB.instructions.indices, id: \.self) { index in

                                    let step = Rational.decimalPlace(recipeFB.instructions[index].step, 10)

                                    Text(step)
                                    Text(recipeFB.instructions[index].instruction)
                                    Text(Rational.displayHoursMinutes(recipeFB.instructions[index].duration))
                                    TextField(String(recipeFB.instructions[index].duration), text: durationBinding(index))
                                        // The placeholder is the current number
                                        // of minutes, which says nothing on its
                                        // own when read aloud.
                                        .accessibilityLabel("Dauer in Minuten")
                                }
                                .font(Theme.bodyFont(15))
                            }
                            else {
                                
                                Text("Beginn").bold()
                                
                                ForEach(recipeFB.instructions.sorted(by: { $0.step < $1.step })) { i in
                                    
                                    let step = Rational.decimalPlace(i.step, 10)
                                    
                                    Text(step)
                                    Text(i.instruction)
                                    Text(Rational.displayHoursMinutes(i.duration))
                                    
                                    if dateTimeStartSelection == 0 {

                                        let date = manager.setNotification(recipeFB.id ?? "", i.instruction, step, i.startTime ?? 0, dateTime, false)
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                    else {
                                        let date = manager.setNotification(recipeFB.id ?? "", i.instruction, step, (i.startTime ?? 0) - recipeFB.prepTime, dateTime, false)
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                }
                                .font(Theme.bodyFont(15))
                                
                                Group {
                                    Text(verbatim: "99")
                                    Text("Fertig")
                                    Text(verbatim: "")
                                    if dateTimeStartSelection == 0 {
                                        let date = Calendar.current.date(byAdding: .minute, value: recipeFB.prepTime, to: dateTime) ?? dateTime
                                        StackedDateTime(date: date, alignment: .trailing)
                                    }
                                    else {
                                        StackedDateTime(date: dateTime, alignment: .trailing)
                                    }
                                }
                                .font(Theme.bodyFont(15))
                            }
                        }
                        .scrollsSidewaysAtLargeText()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    
                    // MARK: Reminder setzen
                    HStack {
                        
                        IconActionButton(systemImage: "bell.badge", style: .primary, accessibilityLabel: "Reminder setzen", title: "Reminder setzen", controlSize: .regular) {
                        if hasExistingPlan {
                            showingPlanChoice = true
                        } else {
                            scheduleReminders(replaceExisting: true)
                        }
                    }
                    .padding()
                    .confirmationDialog("Für dieses Rezept gibt es schon einen Plan", isPresented: $showingPlanChoice, titleVisibility: .visible) {
                        Button("Bestehenden Plan ersetzen", role: .destructive) {
                            scheduleReminders(replaceExisting: true)
                        }
                        Button("Zusätzlich planen") {
                            scheduleReminders(replaceExisting: false)
                        }
                        Button("Abbrechen", role: .cancel) { }
                    } message: {
                        Text("Du kannst den bestehenden Plan ersetzen oder beide behalten – etwa für zwei Backtage.")
                    }
                        .alert("Reminder wurden gesetzt", isPresented: $showingAlert) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            ReminderSummary.text(count: reminderCount, ovenOn: reminderOvenOnText,
                                                 temperature: reminderOvenTemperature,
                                                 finish: reminderFinishText, hints: reminderHintText)
                        }
                        .alert("Backzeiten überschneiden sich", isPresented: $showingPlanError) {
                            Button("OK", role: .cancel) { }
                        } message: {
                            Text(planErrorMessage)
                        }

                        if changeDurationsFlag {
                            
                            IconActionButton(systemImage: "checkmark", style: .primary, accessibilityLabel: "Dauer übernehmen", title: "Dauer übernehmen", controlSize: .regular) {
                                
                                for i in 0..<min(recipeFB.instructions.count, durations.count) {

                                    let cleanedDuration = durations[i].trimmingCharacters(in: .whitespacesAndNewlines)
                                    if Int(cleanedDuration) ?? 0 > 0 { recipeFB.instructions[i].duration = Int(cleanedDuration) ?? 0}
                                }
                                recipeFB.instructions = Rational.calculateStartTimes(
                                    recipeFB.instructions,
                                    dateTime,
                                    dependencies: Rational.ComponentDependency.from(recipeFB.components)
                                )
                                
                                if let lastInstruction = recipeFB.instructions.last {
                                    recipeFB.prepTime = (lastInstruction.startTime ?? 0) + lastInstruction.duration
                                }
                                
                                changeDurationsFlag = false
                                refreshPlanIssues()
                            }
                            .padding()
                        }
                    }
                }
                .padding()
                // A vertical ScrollView takes its content's ideal width in the
                // cross axis, so one over-long label used to stretch this whole
                // screen to 615 pt on a 402 pt phone and clip it at both edges.
                // A definite width forces that proposal back down so the labels
                // wrap; `maxWidth` is not enough — it caps the frame and then
                // centres the too-wide content inside it, which is exactly how
                // the content came to hang over both edges. This is what the
                // GeometryReader above is for: it bound `fullView` and used it
                // nowhere.
                .frame(width: fullView.size.width, alignment: .leading)
            }
            .warmBackground()
            .navigationTitle(recipeFB.name)
            .overlay {
                if isPublishing {
                    ProgressView("Rezept wird veröffentlicht …")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Rezept veröffentlichen?", isPresented: $showPublishWarning) {
                Button("Abbrechen", role: .cancel) { }
                Button("Veröffentlichen") { continuePublishAfterWarning() }
            } message: {
                Text("Das Rezept wird für alle Nutzer sichtbar und kann danach nicht mehr geändert werden. Veröffentliche nur Rezepte, die keine Urheberrechte verletzen. Deine private Fassung bleibt erhalten.")
            }
            .sheet(isPresented: $showPublishEULA) {
                EULAView {
                    publishRecipe()
                }
            }
            .alert("Rezept wurde gespeichert", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Das Rezept liegt jetzt unter „Eigene Rezepte“ auf diesem Gerät und wird über Deine iCloud gesichert. Dort kannst Du es bearbeiten, ohne das öffentliche Rezept zu verändern.")
            }
            .alert("Speichern fehlgeschlagen", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .alert("Rezept wurde veröffentlicht", isPresented: $showPublishedConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Das Rezept steht jetzt allen Nutzern zur Verfügung. Deine private Fassung ist unverändert — Du kannst sie über „Weitere Aktionen“ löschen, wenn Du sie nicht doppelt behalten willst.")
            }
            .alert("Veröffentlichen fehlgeschlagen", isPresented: Binding(
                get: { publishErrorMessage != nil },
                set: { if !$0 { publishErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { publishErrorMessage = nil }
            } message: {
                Text(publishErrorMessage ?? "")
            }
            .onAppear {
                refreshPlanIssues()
            }
        }
    }

    // MARK: - Veröffentlichen

    /// Publishing into the shared database requires accepting the content
    /// agreement first — the same gate as the other two publish paths.
    private func continuePublishAfterWarning() {
        if ModerationStore.shared.hasAcceptedEULA {
            publishRecipe()
        } else {
            showPublishEULA = true
        }
    }

    /// Uploads a copy of this private recipe as a public one. The private
    /// original stays untouched, so a failed upload costs nothing and the
    /// author keeps his own version.
    private func publishRecipe() {
        let publicCopy = recipeFB.copyForUpload()
        let image = GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()

        isPublishing = true
        modelFB.uploadRecipeToFirestore(r: publicCopy, i: image, visibility: .everyone) { result in
            isPublishing = false
            switch result {
            case .success:
                showPublishedConfirmation = true
            case .failure(let error):
                publishErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Backplanung

    /// The plan for the date and mode chosen above. Worked out in BakePlan,
    /// which the baking view of own recipes shares; the generated steps are
    /// worded in the language the recipe is shown in.
    private var bakePlan: BakePlan {
        BakePlan(recipeName: recipeFB.name,
                 steps: recipeFB.instructions.map {
                     PlanStep(instruction: $0.instruction, step: $0.step,
                              startTime: $0.startTime ?? 0, duration: $0.duration)
                 },
                 prepTime: recipeFB.prepTime,
                 anchor: PlanAnchor(selection: dateTimeStartSelection),
                 date: dateTime,
                 languageCode: languageCode.isEmpty ? locale.identifier : languageCode)
    }

    private func refreshPlanIssues() {
        planIssues = bakePlan.issues(in: viewContext)
    }

    /// Sets the reminders and the planned steps for the date chosen above.
    /// `replaceExisting` drops the recipe's earlier plans first; otherwise
    /// the new plan stands beside them — Saturday's and Sunday's loaf.
    private func scheduleReminders(replaceExisting: Bool) {
        // Check the plan before anything changes: overlapping bakes are an
        // error and stop the scheduling (and leave an existing plan alone);
        // the remaining findings are hints and travel with the summary.
        let plan = bakePlan
        let issues = plan.issues(in: viewContext)
        planIssues = issues

        let planErrors = issues.filter { $0.severity == .error }
        if !planErrors.isEmpty {
            planErrorMessage = planErrors.map(\.message).joined(separator: "\n\n")
            showingPlanError = true
            return
        }

        reminderHintText = issues
            .filter { $0.severity == .hint }
            .map(\.message)
            .joined(separator: "\n\n")

        let planID = UUID()
        let reminderPrefix = recipeFB.id ?? ""
        if replaceExisting {
            BakePlanScheduler.removePlans(recipeName: recipeFB.name, reminderPrefix: reminderPrefix,
                                          keeping: planID, in: viewContext)
        }

        showingNotificationMessage = true

        // A step that mixes a component carries that component's
        // ingredients in its reminder, in the serving size chosen above.
        let instructions = recipeFB.instructions
        let scheduler = BakePlanScheduler(plan: plan,
                                          reminderID: "\(reminderPrefix)-\(planID.uuidString)",
                                          manager: manager)
        let result = scheduler.scheduleReminders { index in
            let instruction = instructions[index]
            return ScheduledStepComponent.column(for: recipeFB,
                                                 instruction: instruction,
                                                 instructionText: instruction.instruction)
                .flatMap { ScheduledStepComponent.ingredientsText(for: $0, scale: servingScale) }
        }
        scheduler.writeScheduledSteps(planID: planID, in: viewContext)

        let bakeHistoryFB     = BakeHistoryFB()
        bakeHistoryFB.date    = plan.baseDate
        bakeHistoryFB.comment = AppSettings.generatedRecipeTexts().missingComment
        bakeHistoryFB.images  = [GlobalVariables.noImage]
        recipeFB.bakeHistories.append(bakeHistoryFB)
        recipeFB.bakeHistoryFlag = true

        // The reminders themselves are already set; this writes the
        // bake-history entry that belongs to them. Confirm only if that
        // actually worked.
        do {
            _ = try model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipeFB, context: viewContext, recipeImage: UIImage())

            // A human-readable summary of what was scheduled.
            let timeFormatter  = TimeCalculation()
            reminderCount      = result.reminderCount
            reminderOvenOnText = timeFormatter.calculateTime(t: result.ovenOnDate)
            reminderOvenTemperature = result.ovenTemperature ?? ""
            reminderFinishText = timeFormatter.calculateTime(t: result.finishDate)
            showingAlert       = true
        } catch {
            saveErrorMessage = error.localizedDescription
        }

        showingNotificationMessage = false
    }

    func showNotificationMessage() {
        showingNotificationMessage = true
    }
    
    func setGlobalDateTime(_ date: Date) {
        GlobalVariables.dateTimePicker = date
        refreshPlanIssues()
    }
}
