//
//  StarterIntents.swift
//  BackPlaner
//
//  "Roggensauer gefüttert", "Alle Sauerteige gefüttert", "Wann habe ich den
//  Weizensauer zuletzt gefüttert?" — the feeding log by voice, for the
//  moment the hands are in the dough.
//
//  A starter is what the app already treats as one: a recipe that feeds a
//  starter instead of baking something (`StarterRecipe.isStarterFeeding`),
//  the same condition that shows the "+ Fütterung" tab. Siri tells them
//  apart by name, exactly like the recipe list does, and a fourth starter
//  appears by itself once its recipe exists.
//

import AppIntents
import CoreData
import Foundation

// MARK: - Rules

/// The pure decisions behind the feeding intents, kept apart from Core Data
/// so they can be tested on their own.
enum StarterFeedingRules {

    /// A feeding logged within this long before another one counts as the
    /// same feeding. "Roggensauer gefüttert" followed by "alle gefüttert"
    /// would otherwise write the Roggensauer twice; and a Siri request the
    /// system retries must not either.
    static let duplicateWindow: TimeInterval = 60 * 60

    static func isSameFeeding(lastFeeding: Date?, now: Date) -> Bool {
        guard let lastFeeding else { return false }
        let distance = now.timeIntervalSince(lastFeeding)
        return distance >= 0 && distance < duplicateWindow
    }

    /// Whether a starter's name matches what Siri understood. Spoken names
    /// come back loosely — "Roggen Sauer" for "Roggensauer", "Lievito madre"
    /// for "Lievito Madre", "suss" for "süß" — so case, accents, "ß" and
    /// everything that is not a letter or digit are ignored, and a partial
    /// name is enough.
    static func nameMatches(_ name: String, query: String) -> Bool {
        let folded = fold(name)
        let needle = fold(query)
        guard !needle.isEmpty else { return true }
        return folded.contains(needle)
    }

    private static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Store

/// The starters and their feeding logs for the intents. On the main actor
/// because everything goes through the view context.
@MainActor
enum StarterFeedingStore {

    /// The view context. Nonisolated so it can serve as the default of the
    /// `context` parameters below, which are evaluated outside the actor.
    nonisolated static var context: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    /// Every recipe that feeds a starter, by name. Decided from the steps
    /// and ingredients, which no fetch predicate can express; the recipes
    /// are few, so filtering them in memory costs nothing.
    static func starterRecipes(in context: NSManagedObjectContext = context) throws -> [Recipe] {
        let request = Recipe.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true,
                                                    selector: #selector(NSString.localizedStandardCompare(_:)))]
        return try context.fetch(request).filter(StarterRecipe.isStarterFeeding)
    }

    static func starterRecipe(withID id: String, in context: NSManagedObjectContext = context) throws -> Recipe? {
        try starterRecipes(in: context).first { $0.reminderId == id }
    }

    static func lastFeeding(of recipe: Recipe) -> StarterFeedingLog? {
        recipe.starterFeedingLogsArray.first
    }

    struct FeedingOutcome {
        var fed: [Recipe] = []
        var alreadyLogged: [Recipe] = []
    }

    /// Logs one feeding at `date` for every recipe that has none within the
    /// duplicate window, and saves. Returns who was fed and who was skipped.
    @discardableResult
    static func logFeedings(for recipes: [Recipe], at date: Date, note: String?,
                            in context: NSManagedObjectContext = context) throws -> FeedingOutcome {
        var outcome = FeedingOutcome()
        for recipe in recipes {
            if StarterFeedingRules.isSameFeeding(lastFeeding: lastFeeding(of: recipe)?.date, now: date) {
                outcome.alreadyLogged.append(recipe)
                continue
            }
            let entry = StarterFeedingLog(context: context)
            entry.id = UUID()
            entry.date = date
            entry.facts = StarterFeedingFacts(note: note ?? "")
            recipe.addToStarterFeedingLogs(entry)
            outcome.fed.append(recipe)
        }

        guard context.hasChanges else { return outcome }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return outcome
    }

    /// "1 : 5 : 5", or `nil` when the recipe does not state the ratio.
    static func ratioText(for recipe: Recipe) -> String? {
        guard let ratio = StarterFeedingRatio.ratio(for: recipe) else { return nil }
        return "\(ratio.starter) : \(ratio.flour) : \(ratio.water)"
    }
}

// MARK: - Entity

struct StarterEntity: AppEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sauerteig")
    static let defaultQuery = StarterQuery()

    /// The recipe's own UUID (see `Recipe.reminderId`), which syncs with the
    /// recipe through iCloud — so a saved shortcut keeps pointing at the
    /// same starter on every device, and renaming it changes nothing.
    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Zuletzt gefüttert")
    var lastFedAt: Date?

    /// "1 : 5 : 5" for the picker's subtitle.
    var ratioText: String?

    /// On the main actor: the recipe comes from the view context.
    @MainActor
    init(recipe: Recipe) {
        id = recipe.reminderId
        name = recipe.name
        lastFedAt = recipe.starterFeedingLogsArray.first?.date
        ratioText = StarterFeedingStore.ratioText(for: recipe)
    }

    var displayRepresentation: DisplayRepresentation {
        if let ratioText {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(ratioText)")
        }
        return DisplayRepresentation(title: "\(name)")
    }
}

struct StarterQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [StarterEntity] {
        try StarterFeedingStore.starterRecipes()
            .filter { identifiers.contains($0.reminderId) }
            .map(StarterEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [StarterEntity] {
        try StarterFeedingStore.starterRecipes()
            .filter { StarterFeedingRules.nameMatches($0.name, query: string) }
            .map(StarterEntity.init)
    }

    /// Every starter: there are a handful, so the picker shows them all.
    @MainActor
    func suggestedEntities() async throws -> [StarterEntity] {
        try StarterFeedingStore.starterRecipes().map(StarterEntity.init)
    }
}

// MARK: - Errors

enum StarterIntentError: Error, CustomLocalizedStringResourceConvertible {
    case starterNotFound
    case noStarters
    case couldNotSave

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .starterNotFound: return "Diesen Sauerteig gibt es nicht mehr."
        case .noStarters:      return "Es gibt noch kein Anstellgut-Rezept zum Füttern."
        case .couldNotSave:    return "Die Fütterung konnte nicht gespeichert werden."
        }
    }
}

// MARK: - One starter fed

struct LogStarterFeedingIntent: AppIntent {

    static let title: LocalizedStringResource = "Sauerteig gefüttert"
    static let description = IntentDescription("Trägt eine Fütterung in das Anstellgut-Tagebuch des Sauerteigs ein.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Sauerteig",
               requestValueDialog: "Welchen Sauerteig hast du gefüttert?",
               requestDisambiguationDialog: "Welchen Sauerteig meinst du?")
    var starter: StarterEntity

    @Parameter(title: "Notiz")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$starter) gefüttert") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        guard let recipe = try StarterFeedingStore.starterRecipe(withID: starter.id) else {
            throw StarterIntentError.starterNotFound
        }
        let now = Date()
        let name = recipe.name

        let outcome: StarterFeedingStore.FeedingOutcome
        do {
            outcome = try StarterFeedingStore.logFeedings(for: [recipe], at: now, note: note)
        } catch {
            throw StarterIntentError.couldNotSave
        }

        if outcome.fed.isEmpty, let last = StarterFeedingStore.lastFeeding(of: recipe) {
            let when = IntentPhrasing.dateText(last.date, now: now)
            return .result(dialog: "\(name) war schon eingetragen, gefüttert \(when).")
        }
        if let ratio = StarterFeedingStore.ratioText(for: recipe) {
            return .result(dialog: "\(name) gefüttert, Verhältnis \(ratio).")
        }
        return .result(dialog: "\(name) gefüttert.")
    }
}

// MARK: - All starters fed

struct LogAllStarterFeedingsIntent: AppIntent {

    static let title: LocalizedStringResource = "Alle Sauerteige gefüttert"
    static let description = IntentDescription("Trägt für jeden Sauerteig eine Fütterung zur selben Zeit ein. Ein Sauerteig, der in der letzten Stunde schon eingetragen wurde, wird übersprungen.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Notiz")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Alle Sauerteige gefüttert") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        let recipes = try StarterFeedingStore.starterRecipes()
        guard !recipes.isEmpty else {
            throw StarterIntentError.noStarters
        }

        let outcome: StarterFeedingStore.FeedingOutcome
        do {
            outcome = try StarterFeedingStore.logFeedings(for: recipes, at: Date(), note: note)
        } catch {
            throw StarterIntentError.couldNotSave
        }

        let fed = outcome.fed.map(\.name).formatted(.list(type: .and))
        let skipped = outcome.alreadyLogged.map(\.name).formatted(.list(type: .and))

        switch (outcome.fed.isEmpty, outcome.alreadyLogged.count) {
        case (false, 0):
            return .result(dialog: "\(fed) gefüttert.")
        case (false, 1):
            return .result(dialog: "\(fed) gefüttert. \(skipped) war schon eingetragen.")
        case (false, _):
            return .result(dialog: "\(fed) gefüttert. \(skipped) waren schon eingetragen.")
        case (true, 1):
            return .result(dialog: "\(skipped) war in der letzten Stunde schon eingetragen.")
        case (true, _):
            return .result(dialog: "\(skipped) waren in der letzten Stunde schon eingetragen.")
        }
    }
}

// MARK: - Last feeding

struct LastStarterFeedingIntent: AppIntent {

    static let title: LocalizedStringResource = "Letzte Fütterung"
    static let description = IntentDescription("Sagt, wann ein Sauerteig zuletzt gefüttert wurde.")
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Sauerteig",
               requestValueDialog: "Welcher Sauerteig?",
               requestDisambiguationDialog: "Welchen Sauerteig meinst du?")
    var starter: StarterEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Letzte Fütterung von \(\.$starter)")
    }

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        guard let recipe = try StarterFeedingStore.starterRecipe(withID: starter.id) else {
            throw StarterIntentError.starterNotFound
        }
        let name = recipe.name
        guard let last = StarterFeedingStore.lastFeeding(of: recipe) else {
            return .result(dialog: "Für \(name) ist noch keine Fütterung eingetragen.")
        }

        let now = Date()
        let when = IntentPhrasing.dateText(last.date, now: now)
        let ago = last.date.formatted(.relative(presentation: .named))
        return .result(dialog: "\(name) wurde zuletzt \(when) gefüttert, \(ago).")
    }
}
