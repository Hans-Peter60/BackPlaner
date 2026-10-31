//
//  ShoppingCardSelectFormView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 13.01.22.
//

import BakePlannerCore
import SwiftUI
import CoreData
import Translation
import os

/// One ingredient on its way to a shopping list, independent of where it came
/// from — a recipe on the device or one from the cloud, which has no Core Data
/// object at all. Defined in BakePlannerCore, which holds the list's rules.
typealias ShoppingCartEntry = ShoppingListEntry

/// What is being put on the list.
enum ShoppingCartSource {
    case localRecipe(Recipe)
    case cloudRecipe(RecipeFB)

    var name: String {
        switch self {
        case .localRecipe(let recipe): return recipe.name
        case .cloudRecipe(let recipe): return recipe.name
        }
    }

    /// The recipe's total weight at factor 1.0, for the target-weight input.
    var baseWeight: Double {
        switch self {
        case .localRecipe(let recipe): return recipe.totalWeight
        case .cloudRecipe(let recipe): return recipe.totalWeight
        }
    }

    /// The language the recipe is written in, or nil when it cannot be told
    /// — a recipe of nothing but ingredient names gives the detector too
    /// little to go on, and then the names are taken as they are.
    var languageCode: String? {
        switch self {
        case .cloudRecipe(let recipe):
            return RecipeTranslator.sourceLanguageCode(for: recipe)
        case .localRecipe(let recipe):
            var parts = recipe.instructionsArray.map(\.instruction)
            parts.append(recipe.summary)
            parts.append(contentsOf: recipe.componentsArray.map(\.name))
            parts.append(contentsOf: recipe.componentsArray.flatMap(\.ingredientsArray).map(\.name))
            return RecipeLanguageDetector.detectedLanguage(in: parts.joined(separator: ". "))
        }
    }

    /// The ingredients with their names in `languageCode` where the recipe
    /// already holds them in that language, and whether every name is.
    ///
    /// A cloud recipe caches its translations; the shopping list uses them
    /// before asking the translator. Names it does not have are taken from
    /// the recipe's original language, not from whatever translation is on
    /// screen, so the translator gets the text the cache was made from.
    func entries(in languageCode: String) -> (entries: [ShoppingCartEntry], allInLanguage: Bool) {
        switch self {
        case .localRecipe(let recipe):
            let components = recipe.componentsArray
            let componentNames = components.map(\.name)
            let entries = components.enumerated().flatMap { index, component in
                component.ingredientsArray.filter { ingredient in
                    !ShoppingListAmount.standsForAnotherComponent(name: ingredient.name, weight: ingredient.weight,
                                                                  num: ingredient.num, denom: ingredient.denom,
                                                                  componentIndex: index, componentNames: componentNames)
                }
            }.map { ingredient in
                ShoppingCartEntry(
                    name: ingredient.name,
                    unit: ingredient.unit ?? "",
                    weight: ingredient.weight,
                    num: ingredient.num,
                    denom: ingredient.denom
                )
            }
            let language = self.languageCode
            return (entries, language == nil || language == languageCode)

        case .cloudRecipe(let recipe):
            let source = RecipeTranslator.sourceLanguageCode(for: recipe)
            var allInLanguage = true
            // Matched on the names as written; the translations are only
            // what the list shows.
            let componentNames = recipe.components.map(\.name)
            let entries = recipe.components.enumerated().flatMap { index, component in
                component.ingredients.filter { ingredient in
                    !ShoppingListAmount.standsForAnotherComponent(name: ingredient.name, weight: ingredient.weight,
                                                                  num: ingredient.num, denom: ingredient.denom,
                                                                  componentIndex: index, componentNames: componentNames)
                }
            }.map { ingredient in
                let name: String
                if let cached = ingredient.translations[languageCode]?.name, !cached.isEmpty {
                    name = cached
                } else {
                    name = ingredient.translations[source]?.name ?? ingredient.name
                    if source != languageCode { allInLanguage = false }
                }
                return ShoppingCartEntry(
                    name: name,
                    unit: ingredient.unit,
                    weight: ingredient.weight,
                    num: ingredient.num,
                    denom: ingredient.denom
                )
            }
            return (entries, allInLanguage)
        }
    }
}

struct ShoppingCartSelectFormView: View {

    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) var viewContext

    var source: ShoppingCartSource

    /// The serving scale of the recipe, owned by TabsView/TabsFBView and
    /// shared with the Details and Backen tabs: the factor chosen there is
    /// the one the amounts are put on the list with.
    @Binding var selectedServingSize: Int
    /// A target dough weight in grams; overrides the serving-size factor.
    @Binding var targetWeight: Int?

    init(recipe: Recipe, selectedServingSize: Binding<Int>, targetWeight: Binding<Int?>) {
        self.source = .localRecipe(recipe)
        _selectedServingSize = selectedServingSize
        _targetWeight = targetWeight
    }

    init(recipeFB: RecipeFB, selectedServingSize: Binding<Int>, targetWeight: Binding<Int?>) {
        self.source = .cloudRecipe(recipeFB)
        _selectedServingSize = selectedServingSize
        _targetWeight = targetWeight
    }

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)])
    private var shoppingCarts: FetchedResults<ShoppingCart>

    @EnvironmentObject var model: RecipeModel

    private enum ShoppingCartMode: Int {
        case newList
        case existingList
    }

    private var sortedShoppingCarts: [ShoppingCart] {
        shoppingCarts.sorted { $0.date < $1.date }
    }

    /// 1.0 is the recipe as stored.
    private var servingScale: Double {
        ServingScale.factor(servingSize: selectedServingSize, targetWeight: targetWeight, baseWeight: source.baseWeight)
    }

    /// "2,0" / "1,37" — the factor as the confirmation names it.
    private var servingScaleText: String {
        servingScale.formatted(
            .number
                .precision(.fractionLength(1...2))
                .locale(AppSettings.locale)
        )
    }

    /// The language the list is kept in: the app's. A French recipe baked
    /// in a German app puts "Weizenmehl" on the list, not "farine de blé".
    private var appLanguage: String { RecipeFB.preferredLanguageCode }

    private let dateFormat = DateFormat()
    private let dateRange: ClosedRange<Date> = GlobalVariables.planningDateRange()

    @State private var date = Date()
    @State private var mode = ShoppingCartMode.newList
    @State private var showingAlert = false
    @State private var showingNoIngredientsAlert = false
    @State private var createdShoppingCart = false
    /// The list whose deletion is waiting to be confirmed — an object, not a
    /// flag: one flag shared by every row lets the dialog delete a list other
    /// than the one that was swiped.
    @State private var cartPendingDeletion: ShoppingCart?

    /// An addition waiting for its ingredient names to be translated.
    private struct PendingAddition {
        let cart: ShoppingCart
        let entries: [ShoppingCartEntry]
        let isNewList: Bool
        let sourceLanguage: String
    }

    @State private var pendingAddition: PendingAddition?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false
    /// True when the translator failed and the names went on the list in
    /// the recipe's language; the confirmation says so.
    @State private var keptOriginalNames = false

    var body: some View {
        Form {
            // The same control as under Details and Backen, bound to the same
            // value: the list used to take the recipe as stored, whatever
            // factor had been chosen one tab further left.
            Section {
                ServingScaleControl(selectedServingSize: $selectedServingSize,
                                    targetWeight: $targetWeight,
                                    baseWeight: source.baseWeight)

                Text("Gewicht: \(Int((source.baseWeight * servingScale).rounded()), format: .number) g")
                    .font(Theme.bodyFont(15))
            } header: {
                Text("Portionsgröße")
            } footer: {
                Text("Die Zutaten kommen mit dem Faktor \(servingScaleText) auf die Liste – so wie unter Details und Backen gewählt.")
            }

            Section("Einkaufsliste") {
                Picker("Ziel", selection: $mode) {
                    Text("Neue Liste").tag(ShoppingCartMode.newList)
                    Text("Bestehende Liste").tag(ShoppingCartMode.existingList)
                }
                .pickerStyle(.segmented)

                if mode == .newList {
                    DatePicker(
                        "Datum",
                        selection: $date,
                        in: dateRange,
                        displayedComponents: [.date]
                    )
                    .environment(\.locale, AppSettings.locale)

                    IconActionButton(systemImage: "cart.badge.plus", style: .primary, accessibilityLabel: "Einkaufsliste erstellen", title: "Erstellen", controlSize: .regular) {
                        createShoppingCart()
                    }
                    .disabled(isTranslating)
                }

                if isTranslating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Zutatennamen werden übersetzt …")
                            .font(Theme.bodyFont(14))
                            .foregroundColor(Theme.subtitle)
                    }
                }
            }

            if mode == .existingList {
                Section("Bestehende Einkaufslisten") {
                    if sortedShoppingCarts.isEmpty {
                        ContentUnavailableView(
                            "Keine Einkaufsliste vorhanden",
                            systemImage: "cart",
                            description: Text("Erstelle zuerst eine neue Liste.")
                        )
                    } else {
                        ForEach(sortedShoppingCarts, id: \.self) { shoppingCart in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Einkaufsliste vom \(dateFormat.calculateDate(dT: shoppingCart.date))")
                                        .font(Theme.brandFont(16))
                                    Text("\(shoppingCart.ingredientsArray.count) Zutaten")
                                        .font(Theme.bodyFont(13))
                                        .foregroundColor(Theme.subtitle)
                                }

                                Spacer()

                                IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Rezept zur Einkaufsliste hinzufügen", controlSize: .regular) {
                                    beginAdding(to: shoppingCart, isNewList: false)
                                }
                                .disabled(isTranslating)
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    cartPendingDeletion = shoppingCart
                                } label: {
                                    // A swipe action reached by VoiceOver's actions
                                    // rotor needs a name; the icon alone gives none.
                                    Label("Einkaufsliste löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            if createdShoppingCart {
                Section {
                    NavigationLink("Einkaufslisten anzeigen", destination: ShoppingCartsView())
                }
            }
        }
        // The one recipe tab that stood out as grey: a Form draws its own
        // system background, so it needs both of these to let the warm
        // gradient through, exactly as ShoppingCartsView does.
        .clearScrollBackground()
        .warmBackground()
        .alert("Zutaten wurden auf die Einkaufsliste gesetzt", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if servingScale != 1 {
                Text("Die Mengen entsprechen dem Faktor \(servingScaleText).")
            }
            if keptOriginalNames {
                Text("Die Zutatennamen konnten nicht übersetzt werden und stehen in der Sprache des Rezepts.")
            }
        }
        .alert("Keine Zutaten vorhanden", isPresented: $showingNoIngredientsAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Für dieses Rezept sind keine Zutaten hinterlegt, die auf eine Einkaufsliste passen.")
        }
        // Attached once, outside the loop, so the dialog belongs to the list
        // that was actually swiped.
        .confirmationDialog(
            "Bist Du sicher?",
            isPresented: Binding(
                get: { cartPendingDeletion != nil },
                set: { if !$0 { cartPendingDeletion = nil } }
            ),
            presenting: cartPendingDeletion
        ) { shoppingCart in
            Button("Ja, löschen", role: .destructive) {
                withAnimation {
                    viewContext.delete(shoppingCart)
                    do {
                        try viewContext.save()
                    } catch {
                        AppLog.shoppingCart.error("Einkaufsliste konnte nicht gelöscht werden: \(error)")
                    }
                }
            }
            Button("Nein", role: .cancel) { }
        }
        // Ingredient names of a recipe in another language are translated
        // on the device before they go on the list, through the baker's
        // glossary like every recipe translation. Should that fail — no
        // language pack, no network to fetch one — the names go on the list
        // as they are and the confirmation says so.
        .translationTask(translationConfig) { session in
            guard let pending = pendingAddition else { return }
            var entries = pending.entries

            do {
                let plan = GlossaryTranslationPlan(texts: entries.map(\.name),
                                                   from: pending.sourceLanguage,
                                                   into: appLanguage)
                let requests = plan.sourceTexts.enumerated().map { index, text in
                    TranslationSession.Request(sourceText: text, clientIdentifier: "\(index)")
                }
                let translated = requests.isEmpty ? [] : try await session.translations(from: requests).map(\.targetText)
                let names = plan.results(translated: translated)
                for index in entries.indices where index < names.count {
                    entries[index].name = names[index]
                }
            } catch {
                AppLog.shoppingCart.error("Zutatennamen für die Einkaufsliste konnten nicht übersetzt werden: \(error.localizedDescription)")
                keptOriginalNames = true
            }

            isTranslating = false
            pendingAddition = nil
            finishAdding(entries, to: pending.cart, isNewList: pending.isNewList)
        }
        .navigationTitle(Text("Einkaufsliste erstellen"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createShoppingCart() {
        let calendar = Calendar.current
        let shoppingCart: ShoppingCart

        if let existingShoppingCart = shoppingCarts.first(where: {
            calendar.isDate($0.date, inSameDayAs: date)
        }) {
            shoppingCart = existingShoppingCart
        } else {
            let newShoppingCart = ShoppingCart(context: viewContext)
            newShoppingCart.id = UUID()
            newShoppingCart.date = date
            shoppingCart = newShoppingCart
        }

        beginAdding(to: shoppingCart, isNewList: true)
    }

    /// Scales and sifts the recipe's ingredients and puts them on the list —
    /// at once when their names are already in the app's language, otherwise
    /// after the translation round the `translationTask` above runs.
    private func beginAdding(to shoppingCart: ShoppingCart, isNewList: Bool) {
        showingAlert = false
        keptOriginalNames = false

        // Scaled to the chosen factor first and sifted on the original
        // names, which the water/salt/starter check reads in any language.
        let prepared = source.entries(in: appLanguage)
        let entries = ShoppingListBuilder.entriesToBuy(prepared.entries, scale: servingScale)

        guard !entries.isEmpty else {
            showingNoIngredientsAlert = true
            return
        }

        let detectedLanguage = source.languageCode
        let canTranslate = RecipeTranslator.supportedLanguages.contains { $0.code == appLanguage }

        guard !prepared.allInLanguage, canTranslate,
              let recipeLanguage = detectedLanguage, recipeLanguage != appLanguage
        else {
            finishAdding(entries, to: shoppingCart, isNewList: isNewList)
            return
        }

        pendingAddition = PendingAddition(cart: shoppingCart, entries: entries, isNewList: isNewList, sourceLanguage: recipeLanguage)
        isTranslating = true

        let configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: recipeLanguage),
            target: Locale.Language(identifier: appLanguage)
        )
        // The task only runs again when its configuration changes; the same
        // pair a second time has to be invalidated instead.
        if translationConfig == configuration {
            translationConfig?.invalidate()
        } else {
            translationConfig = configuration
        }
    }

    private func finishAdding(_ entries: [ShoppingCartEntry], to shoppingCart: ShoppingCart, isNewList: Bool) {
        // The list as it stands, each line keyed by its place, so the
        // result can be written back onto the same objects.
        let ingredients = shoppingCart.ingredientsArray
        let lines = ingredients.enumerated().map { index, ingredient in
            ShoppingListLine(key: String(index), name: ingredient.name, unit: ingredient.unit,
                             weight: ingredient.weight, normWeight: ingredient.normWeight,
                             num: ingredient.num, denom: ingredient.denom)
        }
        let result = ShoppingListBuilder.adding(entries, to: lines)
        write(result, onto: ingredients, of: shoppingCart)

        switch source {
        case .localRecipe(let recipe):
            shoppingCart.addToRecipes(recipe)
        case .cloudRecipe(let recipe):
            // A cloud recipe has no Core Data object to relate to, so only its
            // name is recorded — enough to see where the ingredients came from.
            shoppingCart.addCloudRecipeName(recipe.name)
        }

        do {
            try viewContext.save()
            showingAlert = true
            if isNewList {
                createdShoppingCart = true
                mode = .existingList
            }
        } catch {
            AppLog.shoppingCart.error("Einkaufsliste konnte nicht gespeichert werden: \(error)")
        }
    }

    /// Updates the list's ingredients to `lines`: lines kept from before
    /// change their object, new lines get one, and objects whose line was
    /// merged into another are deleted.
    private func write(_ lines: [ShoppingListLine], onto ingredients: [Ingredient], of shoppingCart: ShoppingCart) {
        var kept = Set<Int>()

        for line in lines {
            let ingredient: Ingredient
            if let key = line.key, let index = Int(key), ingredients.indices.contains(index) {
                ingredient = ingredients[index]
                kept.insert(index)
            } else {
                ingredient = Ingredient(context: viewContext)
                ingredient.id = UUID()
                ingredient.number = 0
                shoppingCart.addToIngredients(ingredient)
            }
            // Assigned only where something changed, so an untouched line is
            // not sent through iCloud again.
            if ingredient.name != line.name { ingredient.name = line.name }
            if ingredient.unit != line.unit { ingredient.unit = line.unit }
            if ingredient.weight != line.weight { ingredient.weight = line.weight }
            if ingredient.normWeight != line.normWeight { ingredient.normWeight = line.normWeight }
            if ingredient.num != line.num { ingredient.num = line.num }
            if ingredient.denom != line.denom { ingredient.denom = line.denom }
        }

        for (index, ingredient) in ingredients.enumerated() where !kept.contains(index) {
            viewContext.delete(ingredient)
        }
    }
}
