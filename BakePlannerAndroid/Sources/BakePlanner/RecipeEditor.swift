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
    @State var picksImage = false
    @State var pickedImageURL: URL?
    @State var pickedImageName: String?
    @State var pickedImageType: String?
    @Environment(\.dismiss) var dismiss

    init(original: StoredRecipe?, template: RecipeExportData? = nil, notice: Text? = nil,
         onSave: @escaping (StoredRecipe?, RecipeExportData) -> Void) {
        self.original = original
        self.template = original == nil ? template : nil
        self.notice = notice
        self.onSave = onSave
        _draft = State(initialValue: RecipeDraft(original?.content ?? template))
    }

    var body: some View {
        Form {
            if let notice {
                Section {
                    notice
                        .font(.caption)
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
                Stepper(value: $draft.rating, in: 0...5) {
                    Text(verbatim: draft.rating == 0 ? "–" : String(repeating: "★", count: draft.rating))
                        .foregroundStyle(.orange)
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
                        TextField("Schritt", text: $step.text, axis: .vertical)
                        HStack {
                            Text("Minuten")
                            TextField("Dauer", text: $step.minutes)
                                .foregroundStyle(step.isValid ? Color.primary : Color.red)
                        }
                    }
                }
                .onDelete { offsets in
                    draft.steps.remove(atOffsets: offsets)
                }
                Button("Schritt hinzufügen") {
                    draft.addStep()
                }
            } header: {
                Text("Verarbeitungsschritte")
            }
        }
        .navigationTitle(original == nil ? LocalizedStringKey("Neues Rezept") : LocalizedStringKey("Bearbeiten"))
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
        let next = (steps.map { Int($0.step) }.max() ?? 0) + 1
        steps.append(StepDraft(step: Double(next)))
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
            instructions: steps.sorted { $0.step < $1.step }.map(\.instruction)
        ).recalculated()
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
    var step: Double
    var bakeFlag = false
    var componentName: String?

    init(step: Double) {
        self.step = step
    }

    init(_ instruction: RecipeExportInstruction) {
        text = instruction.instruction
        minutes = instruction.duration == 0 ? "" : String(instruction.duration)
        step = instruction.step
        bakeFlag = instruction.bakeFlag
        componentName = instruction.componentName
    }

    var isValid: Bool { duration != nil }

    /// Minutes, or hours and minutes as a baker writes them ("1:30",
    /// "1,5 h"), as on the iPhone (DurationInput).
    private var duration: Int? {
        DurationInput.minutes(from: minutes)
    }

    var instruction: RecipeExportInstruction {
        RecipeExportInstruction(instruction: text.trimmingCharacters(in: .whitespacesAndNewlines), step: step,
                                duration: duration ?? 0, startTime: 0, bakeFlag: bakeFlag,
                                componentName: componentName)
    }
}
