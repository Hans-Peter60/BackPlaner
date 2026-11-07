import BakePlannerCore
import SkipKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Changes a recipe — or starts a new one — as a whole: its details, the
/// components with their ingredients, and the steps. On saving, weights,
/// step times and the preparation time are worked out again the way the
/// iOS app does (RecipeExportData.recalculated).
struct RecipeEditor: View {
    /// The recipe as it was, or nil for a new one.
    let original: StoredRecipe?
    /// A new recipe's content to start from — an imported one — with what
    /// the editor does not show (picture, link) kept on saving.
    let template: RecipeExportData?
    /// Shown above the form: what the import says about its result.
    let notice: Text?
    let onSave: (StoredRecipe?, RecipeExportData) -> Void
    @State var draft: RecipeDraft
    @Environment(\.colorScheme) var colorScheme
    @State var picksImage = false
    @State var takesPhoto = false
    @State var pickedImageURL: URL?
    @State var pickedImageName: String?
    @State var pickedImageType: String?
    @Environment(\.dismiss) var dismiss

    /// True when the template is a published recipe being changed, so the
    /// title says "Bearbeiten" although there is no stored original.
    let editsPublished: Bool

    init(original: StoredRecipe?, template: RecipeExportData? = nil, notice: Text? = nil, editsPublished: Bool = false,
         onSave: @escaping (StoredRecipe?, RecipeExportData) -> Void) {
        self.original = original
        self.template = original == nil ? template : nil
        self.notice = notice
        self.editsPublished = editsPublished
        self.onSave = onSave
        _draft = State(initialValue: RecipeDraft(original?.content ?? template))
    }

    var body: some View {
        Form {
            if let notice {
                Section {
                    notice
                        .font(AppFont.caption)
                }
            }

            Section {
                TextField("Rezeptname", text: $draft.name)
            } header: {
                Text("Name")
            }

            // The picture, as the iPhone's form has it; picked through the
            // system's file chooser like in the recipe view.
            Section {
                if let image = draft.image {
                    EditorPicture(data: image)
                }
                HStack(spacing: 16) {
                    Button(draft.image == nil ? LocalizedStringKey("Bild hinzufügen") : LocalizedStringKey("Bild ändern")) {
                        picksImage = true
                    }
                    Button("Kamera") {
                        takesPhoto = true
                    }
                    if draft.image != nil {
                        Button("Bild entfernen", role: .destructive) {
                            draft.image = nil
                        }
                    }
                }
            } header: {
                Text("Rezeptbild")
            }

            Section {
                TextField("Beschreibung", text: $draft.summary, axis: .vertical)
            } header: {
                Text("Beschreibung")
            }

            Section {
                // Five stars to tap, as the iPhone's RatingStarsView; the
                // star tapped again takes the rating back.
                HStack(spacing: 6) {
                    ForEach(1..<6, id: \.self) { number in
                        Button {
                            draft.rating = draft.rating == number ? number - 1 : number
                        } label: {
                            // SkipUI has no star symbols; the characters do.
                            Text(verbatim: number <= draft.rating ? "★" : "☆")
                                .font(AppFont.title2)
                                .foregroundStyle(number <= draft.rating
                                                 ? Palette.accentText(colorScheme) : Palette.subtitle(colorScheme))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: "\(number)"))
                    }
                }
                TextField("Tags, durch Komma getrennt", text: $draft.tags)
            } header: {
                Text("Bewertung")
            }

            Section {
                Toggle(draft.isStarter ? LocalizedStringKey("Regelmäßig auffrischen") : LocalizedStringKey("Regelmäßig planen"),
                       isOn: Binding(get: { draft.recurrenceIntervalDays > 0 },
                                     set: { draft.recurrenceIntervalDays = $0 ? max(draft.recurrenceIntervalDays, 5) : 0 }))
                if draft.recurrenceIntervalDays > 0 {
                    Stepper(value: $draft.recurrenceIntervalDays, in: 1...60) {
                        Text("alle \(draft.recurrenceIntervalDays) Tage")
                    }
                }
            }

            ForEach($draft.components) { $component in
                Section {
                    TextField("Komponente", text: $component.name)
                    ForEach($component.ingredients) { $ingredient in
                        HStack {
                            TextField("Menge", text: $ingredient.amount)
                                .frame(width: 72)
                                .foregroundStyle(ingredient.isValid ? Color.primary : Color.red)
                            TextField("Einheit", text: $ingredient.unit)
                                .frame(width: 72)
                            TextField("Zutat", text: $ingredient.name)
                        }
                    }
                    .onDelete { offsets in
                        component.ingredients.remove(atOffsets: offsets)
                    }
                    Button("Zutat hinzufügen") {
                        component.ingredients.append(IngredientDraft())
                    }
                    Button("Komponente entfernen", role: .destructive) {
                        let id = component.id
                        draft.components.removeAll { $0.id == id }
                    }
                } header: {
                    Text("Komponente")
                }
            }

            Section {
                Button("Komponente hinzufügen") {
                    draft.components.append(ComponentDraft())
                }
            }

            Section {
                ForEach($draft.steps) { $step in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            // The step's number, editable as on the iPhone:
                            // 3.1 is a sub-step of 3 (a fold during the rest).
                            TextField("Nr.", text: $step.numberText)
                                .keyboardType(.decimalPad)
                                .frame(width: 64)
                                .foregroundStyle(step.step == nil ? Color.red : Color.primary)
                            TextField("Schritt", text: $step.text, axis: .vertical)
                        }
                        HStack {
                            Text("Minuten")
                            TextField("Dauer", text: $step.minutes)
                                .foregroundStyle(step.hasValidDuration ? Color.primary : Color.red)
                        }
                        // The step's time window, as on the iPhone: how
                        // short and how long it may take; both empty for a
                        // fixed duration.
                        HStack {
                            Text("Zeitfenster")
                            TextField("Mindestens", text: $step.minimumText)
                                .foregroundStyle(step.hasValidWindow ? Color.primary : Color.red)
                            TextField("Höchstens", text: $step.maximumText)
                                .foregroundStyle(step.hasValidWindow ? Color.primary : Color.red)
                        }
                        // The oven's settings as fields, as on the iPhone:
                        // the plan takes them before the wording.
                        HStack {
                            Text("Ofen")
                            TextField("°C", text: $step.ovenTemperatureText)
                                .keyboardType(.numberPad)
                                .foregroundStyle(step.hasValidOven ? Color.primary : Color.red)
                            TextField("Fallend auf", text: $step.ovenFallingText)
                                .keyboardType(.numberPad)
                                .foregroundStyle(step.hasValidOven ? Color.primary : Color.red)
                        }
                        Picker("Schwaden", selection: $step.steamChoice) {
                            Text("Nicht angegeben").tag(0)
                            Text("Mit Schwaden").tag(1)
                            Text("Ohne Schwaden").tag(2)
                        }
                    }
                }
                .onDelete { offsets in
                    draft.steps.remove(atOffsets: offsets)
                }
                HStack(spacing: 16) {
                    Button("Schritt hinzufügen") {
                        draft.addStep()
                    }
                    Button("Unterschritt hinzufügen") {
                        draft.addSubStep()
                    }
                    .disabled(draft.steps.isEmpty)
                }
            } header: {
                Text("Verarbeitungsschritte")
            }
        }
        .navigationTitle(original == nil && !editsPublished ? LocalizedStringKey("Neues Rezept") : LocalizedStringKey("Bearbeiten"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    onSave(original, draft.content(keeping: original?.content ?? template))
                    dismiss()
                }
                .disabled(!draft.canSave)
            }
        }
        .withDocumentPicker(isPresented: $picksImage,
                            allowedContentTypes: [.image],
                            selectedDocumentURL: $pickedImageURL,
                            selectedFilename: $pickedImageName,
                            selectedFileMimeType: $pickedImageType)
        .onChange(of: pickedImageURL) { _, url in
            guard let url else { return }
            pickedImageURL = nil
            // A file that is no picture leaves the picture as it is.
            if let data = RecipeDetailView.pictureData(at: url) {
                draft.image = data
            }
        }
        .cameraPicker(isPresented: $takesPhoto) { data in
            draft.image = data
        }
    }
}

/// The draft's picture as a small preview in the form.
struct EditorPicture: View {
    let data: Data

    var body: some View {
        #if canImport(UIKit) || os(Android)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        #endif
    }
}

/// A recipe as the editor holds it: text the user types, turned into a
/// recipe on saving.
struct RecipeDraft {
    var name: String
    var summary: String
    var rating: Int
    var tags: String
    var components: [ComponentDraft]
    var steps: [StepDraft]
    /// The recipe's picture, as the app keeps pictures (JPEG, PhotoShrinker).
    var image: Data?
    /// Days between two plans the app makes on its own; 0 for none.
    var recurrenceIntervalDays: Int
    /// Whether the recipe feeds a starter, for the rhythm's wording.
    let isStarter: Bool

    init(_ content: RecipeExportData?) {
        recurrenceIntervalDays = content?.recurrenceIntervalDays ?? 0
        isStarter = content.map { StarterRecipe.isStarterFeeding($0) } ?? false
        name = content?.name ?? ""
        image = content?.image
        summary = content?.summary ?? ""
        rating = content?.rating ?? 0
        tags = content?.tags.joined(separator: ", ") ?? ""
        components = content?.components.map(ComponentDraft.init) ?? [ComponentDraft()]
        steps = content?.instructions.map(StepDraft.init) ?? []
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && components.allSatisfy { $0.ingredients.allSatisfy(\.isValid) }
            && steps.allSatisfy(\.isValid)
    }

    /// A new step after the last, as the next whole step number.
    mutating func addStep() {
        let next = (steps.compactMap { $0.step.map { Int($0) } }.max() ?? 0) + 1
        steps.append(StepDraft(step: Double(next)))
    }

    /// A sub-step of the last step — 3.1 after 3, 3.2 after 3.1 — as the
    /// iPhone numbers on after a sub-step.
    mutating func addSubStep() {
        guard let last = steps.compactMap(\.step).max() else { return }
        steps.append(StepDraft(step: (last * 10).rounded() / 10 + 0.1))
    }

    /// The recipe this draft describes. What the editor does not show — the
    /// link, the preparation time — comes from `original`.
    func content(keeping original: RecipeExportData?) -> RecipeExportData {
        RecipeExportData(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            urlLink: original?.urlLink,
            prepTime: original?.prepTime ?? 0,
            totalWeight: 0,
            tags: tags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            rating: rating,
            recurrenceIntervalDays: recurrenceIntervalDays,
            image: image,
            components: components.enumerated().map { index, component in
                RecipeExportComponent(name: component.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                      number: index + 1,
                                      ingredients: component.ingredients.enumerated().map { number, ingredient in
                                          ingredient.ingredient(number: number + 1)
                                      })
            },
            instructions: steps.sorted { ($0.step ?? 0) < ($1.step ?? 0) }.map(\.instruction)
        )
        // A fold line typed by hand ("nach 30 und 60 Minuten dehnen und
        // falten") becomes one sub-step per fold, as on the iPhone.
        .expandingTimedFolds()
        .recalculated()
    }
}

struct ComponentDraft: Identifiable {
    let id = UUID()
    var name = ""
    var ingredients: [IngredientDraft] = [IngredientDraft()]

    init() {}

    init(_ component: RecipeExportComponent) {
        name = component.name
        ingredients = component.ingredients.map(IngredientDraft.init)
    }
}

struct IngredientDraft: Identifiable {
    let id = UUID()
    var amount = ""
    var unit = ""
    var name = ""
    /// The amount as stored and as first shown: kept as it was while the
    /// text is untouched, so "1/1" of a whole component stays exactly that.
    private var stored: (text: String, value: IngredientAmountText)?

    init() {}

    init(_ ingredient: RecipeExportIngredient) {
        let value = IngredientAmountText(weight: ingredient.weight, numerator: ingredient.num,
                                         denominator: ingredient.denom)
        amount = IngredientAmountText.text(weight: ingredient.weight, numerator: ingredient.num,
                                           denominator: ingredient.denom)
        unit = ingredient.unit ?? ""
        name = ingredient.name
        stored = (amount, value)
    }

    var isValid: Bool { value != nil }

    private var value: IngredientAmountText? {
        if let stored, stored.text == amount { return stored.value }
        return IngredientAmountText.parse(amount)
    }

    func ingredient(number: Int) -> RecipeExportIngredient {
        let value = value ?? IngredientAmountText(weight: 0, numerator: 0, denominator: 0)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecipeExportIngredient(name: name.trimmingCharacters(in: .whitespacesAndNewlines), number: number,
                                      unit: unit.isEmpty ? nil : unit, weight: value.weight, normWeight: 0,
                                      num: value.numerator, denom: value.denominator)
    }
}

struct StepDraft: Identifiable {
    let id = UUID()
    var text = ""
    var minutes = ""
    /// The step number as typed: "3" or "3.1" (a comma does as well).
    var numberText: String
    /// The step's time window as typed, both empty for a fixed duration.
    var minimumText = ""
    var maximumText = ""
    /// The oven's settings as typed: degrees Celsius, the temperature the
    /// heat falls to; steam 0 = not stated, 1 = with, 2 = without.
    var ovenTemperatureText = ""
    var ovenFallingText = ""
    var steamChoice = 0
    var bakeFlag = false
    var componentName: String?

    init(step: Double) {
        numberText = Self.numberText(for: step)
    }

    init(_ instruction: RecipeExportInstruction) {
        text = instruction.instruction
        minutes = instruction.duration == 0 ? "" : String(instruction.duration)
        numberText = Self.numberText(for: instruction.step)
        minimumText = instruction.durationWindow.map { String($0.lowerBound) } ?? ""
        maximumText = instruction.durationWindow.map { String($0.upperBound) } ?? ""
        // A step without stored settings starts with what its wording says,
        // as on the iPhone; saving keeps it.
        let oven = instruction.oven ?? BakePlan.suggestedOvenSettings(in: instruction.instruction)
        ovenTemperatureText = oven?.temperature.map(String.init) ?? ""
        ovenFallingText = oven?.fallingTo.map(String.init) ?? ""
        steamChoice = oven?.steam.map { $0 ? 1 : 2 } ?? 0
        bakeFlag = instruction.bakeFlag
        componentName = instruction.componentName
    }

    /// The window typed, when both bounds are there and in order.
    var durationWindow: ClosedRange<Int>? {
        DurationWindow.range(minimum: Self.bound(minimumText), maximum: Self.bound(maximumText))
    }

    /// Both bounds empty, or both durations in order.
    var hasValidWindow: Bool {
        let minimumEmpty = minimumText.trimmingCharacters(in: .whitespaces).isEmpty
        let maximumEmpty = maximumText.trimmingCharacters(in: .whitespaces).isEmpty
        if minimumEmpty && maximumEmpty { return true }
        return durationWindow != nil
    }

    /// The oven settings typed, nil when all are empty.
    var oven: OvenSettings? {
        OvenSettings.from(temperature: Self.degrees(ovenTemperatureText),
                          fallingTo: Self.degrees(ovenFallingText),
                          steam: steamChoice == 0 ? nil : steamChoice == 1)
    }

    /// Every typed temperature is a whole number of degrees.
    var hasValidOven: Bool {
        [ovenTemperatureText, ovenFallingText].allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).isEmpty || Self.degrees($0) != nil
        }
    }

    /// A temperature as typed, nil when empty or no number.
    private static func degrees(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    /// A bound as typed, nil when empty or no duration.
    private static func bound(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let minutes = DurationInput.minutes(from: trimmed), minutes > 0 else { return nil }
        return minutes
    }

    /// "3" or "3.1": the number rounded to a tenth. Rounded, not cut off
    /// — a stored 4.1999999 is the step 4.2, and cutting it to 4.1 would
    /// renumber the step on saving.
    static func numberText(for step: Double) -> String {
        let tenths = Int((step * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    /// The step number, nil for text that is none.
    var step: Double? {
        let trimmed = numberText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    var hasValidDuration: Bool { duration != nil }

    var isValid: Bool { hasValidDuration && hasValidWindow && hasValidOven && step != nil }

    /// Minutes, or hours and minutes as a baker writes them ("1:30",
    /// "1,5 h"), as on the iPhone (DurationInput).
    private var duration: Int? {
        DurationInput.minutes(from: minutes)
    }

    var instruction: RecipeExportInstruction {
        RecipeExportInstruction(instruction: text.trimmingCharacters(in: .whitespacesAndNewlines), step: step ?? 0,
                                duration: duration ?? 0, startTime: 0, bakeFlag: bakeFlag,
                                componentName: componentName,
                                minDuration: durationWindow?.lowerBound, maxDuration: durationWindow?.upperBound,
                                oven: oven)
    }
}
