import BakePlannerCore
import BakePlannerStorage
import Foundation
import Observation
import SkipFuse

/// What the app shows, and where it keeps the user's recipes, shopping lists
/// and bake history: one SQLite database in the app's own storage.
@MainActor
@Observable
final class AppModel {
    /// The recipes, by name, without their pictures.
    var recipes: [StoredRecipe] = []
    /// Why the recipes could not be read, if they could not.
    var loadError: String?
    /// What the last import did, until the user has seen it.
    var importOutcome: ImportOutcome?

    enum ImportOutcome: Equatable {
        /// Recipes added, and pantry items the file added to the pantry.
        case imported(Int, pantryItems: Int)
        case failed(String)
    }

    /// The shopping lists, oldest first.
    var shoppingLists: [StoredShoppingList] = []

    /// Where a recipe's ingredients go.
    enum ShoppingListTarget {
        /// The list of that day — a new one when the day has none yet, as
        /// on the iPhone.
        case newList(Date)
        case existingList(String)
    }

    enum ShoppingListOutcome: Equatable {
        case added
        /// The recipe has nothing that is bought (only water, salt, starter).
        case nothingToBuy
        /// Everything the recipe needs is in the pantry; no list was made.
        case allInPantry
        case failed
    }

    /// The bake history of every recipe, newest first, without photos.
    var bakeHistory: [StoredBakeHistory] = []

    /// The bake history as it is shown: a starter is fed, not baked, so
    /// entries an older iPhone version wrote for a planned starter stay
    /// stored but are left out.
    var shownBakeHistory: [StoredBakeHistory] {
        let starters = Set(recipes.filter { StarterRecipe.isStarterFeeding($0.content) }.map(\.id))
        return bakeHistory.filter { !starters.contains($0.recipeID) }
    }

    private var store: SQLiteRecipeStore?
    private var listStore: SQLiteShoppingListStore?
    private var historyStore: SQLiteBakeHistoryStore?
    private var feedingStore: SQLiteStarterFeedingLogStore?
    private var stepStore: SQLiteScheduledStepStore?
    private var pantryStore: SQLitePantryStore?
    private var reservationStore: SQLitePantryReservationStore?

    /// The pantry, by name.
    var pantryItems: [StoredPantryItem] = []
    /// What the open plans have reserved of the pantry.
    var pantryReservations: [StoredPantryReservation] = []
    /// The last deductions made when plans ended, newest first; kept in the
    /// settings file so one can be undone.
    var pantryBookings: [PantryBooking] = []

    /// Whether the pantry comes off a recipe's shopping list; the iPhone's
    /// setting key.
    var deductsPantry = AppModel.storedBool("shoppingList.deductsPantry", default: true) {
        didSet { SettingsFile.set(deductsPantry, forKey: "shoppingList.deductsPantry") }
    }

    /// Every scheduled step of every plan, by date.
    var scheduledSteps: [StoredScheduledStep] = []
    /// The model the app shows, for work that arrives from outside a view
    /// (an action on a reminder notification); nil while no screen is up.
    static weak var current: AppModel?

    /// The visible public recipes, without components and steps until one
    /// is opened (PublicRecipeService).
    var publicRecipes: [RecipeFB] = []
    /// Why the public recipes could not be read, if they could not.
    var publicRecipesError: String?
    var isLoadingPublicRecipes = false
    /// The pictures of the public recipes opened so far, by recipe id.
    var publicRecipeImages: [String: Data] = [:]
    /// Small pictures of the public recipes for the list, by recipe id,
    /// read from Storage as the rows appear (the iPhone's list loads them
    /// all as well); an empty value marks a recipe without a picture, so
    /// it is not asked for again.
    var publicThumbnails: [String: Data] = [:]
    private var loadingPublicThumbnails: Set<String> = []

    /// Which recipes the list shows — the iPhone's three filter chips and
    /// their settings keys: the own recipes on the device, the public ones
    /// published from this account (`isOwn`), and the public ones of
    /// everyone else.
    var showsLocalRecipes = AppModel.storedBool(AppSettingsKeys.showLocalRecipes,
                                                default: AppSettings.defaultShowLocalRecipes) {
        didSet { SettingsFile.set(showsLocalRecipes, forKey: AppSettingsKeys.showLocalRecipes) }
    }
    var showsOwnPublishedRecipes = AppModel.storedBool(AppSettingsKeys.showOwnPublishedRecipes,
                                                       default: AppSettings.defaultShowOwnPublishedRecipes) {
        didSet { SettingsFile.set(showsOwnPublishedRecipes, forKey: AppSettingsKeys.showOwnPublishedRecipes) }
    }
    var showsPublicRecipes = AppModel.storedBool(AppSettingsKeys.showPublicCloudRecipes,
                                                 default: AppSettings.defaultShowPublicCloudRecipes) {
        didSet { SettingsFile.set(showsPublicRecipes, forKey: AppSettingsKeys.showPublicCloudRecipes) }
    }

    /// Whether the user has agreed to the cloud AI reading recipes, and
    /// whether the import uses it — the iPhone's keys
    /// (Settings → "Datenschutz & KI", the import's "Analyseart").
    /// Settings → Rezepte → "Bäckerprozente anzeigen": every weighed
    /// ingredient's share of its component's flour behind the line.
    /// Whether the list shows variants of recipes (the iPhone's key), or
    /// only the recipes of their own.
    var showsVariantRecipes = AppModel.storedBool(AppSettingsKeys.showVariantRecipes, default: true) {
        didSet { SettingsFile.set(showsVariantRecipes, forKey: AppSettingsKeys.showVariantRecipes) }
    }

    var showsBakersPercentages = AppModel.storedBool(AppSettingsKeys.bakersPercentages,
                                                     default: AppSettings.defaultBakersPercentages) {
        didSet { SettingsFile.set(showsBakersPercentages, forKey: AppSettingsKeys.bakersPercentages) }
    }
    var allowsCloudAnalysis = AppModel.storedBool(AppSettingsKeys.cloudRecipeAnalysisConsent, default: false) {
        didSet { SettingsFile.set(allowsCloudAnalysis, forKey: AppSettingsKeys.cloudRecipeAnalysisConsent) }
    }
    var usesCloudAnalysis = SettingsFile.value(forKey: AppSettingsKeys.recipeImageAnalysisMode) as? String == "protectedCloud" {
        didSet {
            SettingsFile.set(usesCloudAnalysis ? "protectedCloud" : "localOnly",
                             forKey: AppSettingsKeys.recipeImageAnalysisMode)
        }
    }

    /// Authors blocked and recipes reported on this device — the iPhone's
    /// keys (ModerationStore). Their public recipes stay out of the list.
    /// Kept as one text, an id per line: UserDefaults on Android has no
    /// string arrays (`stringArray(forKey:)` is unavailable there).
    var blockedAuthors = AppModel.storedIDs(AppModel.blockedAuthorsKey) {
        didSet { AppModel.storeIDs(blockedAuthors, AppModel.blockedAuthorsKey) }
    }
    var reportedRecipeIDs = AppModel.storedIDs(AppModel.reportedRecipesKey) {
        didSet { AppModel.storeIDs(reportedRecipeIDs, AppModel.reportedRecipesKey) }
    }
    private static let blockedAuthorsKey = "ugc.blockedAuthors"
    private static let reportedRecipesKey = "ugc.hiddenRecipes"

    private static func storedIDs(_ key: String) -> Set<String> {
        let text = SettingsFile.value(forKey: key) as? String ?? ""
        return Set(text.split(separator: "\n").map(String.init))
    }

    private static func storeIDs(_ ids: Set<String>, _ key: String) {
        SettingsFile.set(ids.sorted().joined(separator: "\n"), forKey: key)
    }

    /// The public recipes the list shows: neither reported here nor by a
    /// blocked author.
    var visiblePublicRecipes: [RecipeFB] {
        publicRecipes.filter { recipe in
            !(recipe.id.map { reportedRecipeIDs.contains($0) } ?? false)
                && !(recipe.authorId.map { !$0.isEmpty && blockedAuthors.contains($0) } ?? false)
        }
    }

    private static func storedBool(_ key: String, default defaultValue: Bool) -> Bool {
        SettingsFile.value(forKey: key) as? Bool ?? defaultValue
    }

    func load() {
        do {
            let store = try openedStore()
            linkDatedCopiesIfNeeded(in: store)
            recipes = try store.recipes(includingImages: false)
            loadError = nil
        } catch {
            logger.error("could not read the recipes: \(error)")
            loadError = "\(error)"
        }
    }

    private static let variantLinkKey = "maintenance.variantLinkV1"

    /// Links the copies the flour substitution and the starter adjustment
    /// wrote before variants existed to their origin, once: a recipe whose
    /// name carries the dated suffix becomes a variant of the recipe named
    /// like its base, when there is exactly one — as the iPhone does.
    private func linkDatedCopiesIfNeeded(in store: RecipeStore) {
        guard !AppModel.storedBool(AppModel.variantLinkKey, default: false) else { return }
        do {
            let all = try store.recipes(includingImages: false)
            let originals = Dictionary(grouping: all.filter { !AdjustedRecipe.hasDatedSuffix($0.content.name) },
                                       by: { $0.content.name.trimmingCharacters(in: .whitespaces) })
            var linked = 0
            for copy in all where copy.originID == nil {
                guard let base = AdjustedRecipe.baseName(of: copy.content.name),
                      let candidates = originals[base], candidates.count == 1,
                      let origin = candidates.first, origin.id != copy.id else { continue }
                var variant = copy
                variant.originID = origin.id
                try store.update(variant)
                linked += 1
            }
            SettingsFile.set(true, forKey: AppModel.variantLinkKey)
            logger.info("variant linking attached \(linked) dated copies to their origin")
        } catch {
            logger.error("variant linking failed, will retry on next start: \(error)")
        }
    }

    /// The variants of recipe `id`, by name, from the loaded list.
    func variants(of id: String) -> [StoredRecipe] {
        recipes.filter { $0.originID == id }
    }

    /// A new variant of `origin` made by hand: a copy numbered within its
    /// family ("Landbrot V2"), marked as adjusted so later adjustments change
    /// it in place, with `note` on what it is meant to change. The variant,
    /// or nil when saving failed.
    func addVariant(of origin: StoredRecipe, note: String) -> StoredRecipe? {
        guard let full = recipe(id: origin.id) else { return nil }
        var content = full.content
        content.name = AdjustedRecipe.variantName(original: content.name, among: recipes.map { $0.content.name })
        do {
            let variant = try openedStore().addVariant(content, of: origin.id, note: note, adjustedOn: Date())
            load()
            return variant
        } catch {
            logger.error("could not add a variant: \(error)")
            return nil
        }
    }

    /// One recipe with its picture, read afresh.
    func recipe(id: String) -> StoredRecipe? {
        do {
            return try openedStore().recipe(id: id)
        } catch {
            logger.error("could not read recipe \(id): \(error)")
            return nil
        }
    }

    /// Keeps the changed recipe (everything but its picture) and refreshes
    /// the list. Whether it worked.
    @discardableResult
    func save(_ recipe: StoredRecipe) -> Bool {
        do {
            try openedStore().update(recipe)
            load()
            return true
        } catch {
            logger.error("could not save recipe \(recipe.id): \(error)")
            return false
        }
    }

    /// Keeps a new recipe and refreshes the list. Whether it worked.
    @discardableResult
    func add(_ content: RecipeExportData) -> Bool {
        do {
            _ = try openedStore().add(content, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
            load()
            return true
        } catch {
            logger.error("could not add a recipe: \(error)")
            return false
        }
    }

    /// Keeps a copy a flour substitution or starter adjustment produced,
    /// marked as adjusted today and, when it was made from an own recipe,
    /// as that recipe's variant with `note` on what it changes; refreshes
    /// the list. The copy, or nil.
    func addAdjustedCopy(_ content: RecipeExportData, originID: String? = nil, note: String? = nil) -> StoredRecipe? {
        do {
            let store = try openedStore()
            var content = content
            // A variant is numbered within its family; a copy of a public
            // recipe keeps the dated name the adjustment gave it.
            if let originID, let origin = recipes.first(where: { $0.id == originID }) {
                content.name = AdjustedRecipe.variantName(original: origin.content.name,
                                                          among: recipes.map { $0.content.name })
            }
            let copy = if let originID {
                try store.addVariant(content, of: originID, note: note, adjustedOn: Date())
            } else {
                try store.add(content, firestoreId: nil, adjustedOn: Date(), bakeHistoryFlag: false)
            }
            load()
            return copy
        } catch {
            logger.error("could not add an adjusted copy: \(error)")
            return nil
        }
    }

    /// Small pictures for the recipe list, made once per recipe from the
    /// stored picture and kept; the list itself loads no pictures.
    private var thumbnails: [String: Data] = [:]

    /// The list thumbnail of an own recipe, read and shrunk on first use;
    /// nil without a picture.
    func thumbnail(forRecipe id: String) -> Data? {
        if let cached = thumbnails[id] { return cached.isEmpty ? nil : cached }
        let data = recipe(id: id)?.content.image.flatMap { PhotoShrinker.thumbnail($0) }
        thumbnails[id] = data ?? Data()
        return data
    }

    /// Forgets a recipe's thumbnail after its picture changed.
    func forgetThumbnail(forRecipe id: String) {
        thumbnails[id] = nil
    }

    /// The list thumbnail of a public recipe: at once when its picture is
    /// known (opened before, or loaded for the list earlier), else nil now
    /// and the picture is fetched, which refreshes the row.
    func publicThumbnail(of recipe: RecipeFB) -> Data? {
        let id = recipe.id ?? ""
        if let cached = publicThumbnails[id] { return cached.isEmpty ? nil : cached }
        if let full = publicRecipeImages[id] {
            let small = PhotoShrinker.thumbnail(full)
            publicThumbnails[id] = small ?? Data()
            return small
        }
        guard !recipe.image.isEmpty else {
            publicThumbnails[id] = Data()
            return nil
        }
        guard !loadingPublicThumbnails.contains(id) else { return nil }
        loadingPublicThumbnails.insert(id)
        Task {
            let data = await PublicRecipeService.imageData(of: recipe)
            if let data {
                publicRecipeImages[id] = data
            }
            publicThumbnails[id] = data.flatMap { PhotoShrinker.thumbnail($0) } ?? Data()
            loadingPublicThumbnails.remove(id)
        }
        return nil
    }

    /// Gives the recipe a new picture, or none for `nil`. Whether it worked.
    @discardableResult
    func setImage(_ image: Data?, forRecipe id: String) -> Bool {
        do {
            try openedStore().setImage(image, forRecipe: id)
            forgetThumbnail(forRecipe: id)
            return true
        } catch {
            logger.error("could not change the picture of recipe \(id): \(error)")
            return false
        }
    }

    /// Removes the recipe and refreshes the list. Its ingredients stay on
    /// the shopping lists; the recipe's name goes from them.
    func delete(id: String) {
        do {
            try openedStore().delete(id: id)
        } catch {
            logger.error("could not delete recipe \(id): \(error)")
        }
        load()
        loadShoppingLists()
        loadBakeHistory()
    }

    // MARK: Bake history

    func loadBakeHistory() {
        do {
            bakeHistory = try openedHistoryStore().entries(includingImages: false)
        } catch {
            logger.error("could not read the bake history: \(error)")
        }
    }

    /// Every entry with its photos, for the gallery and the photo cloud;
    /// read on demand, the list itself goes without the photos.
    func bakeHistoryWithImages() -> [StoredBakeHistory] {
        do {
            return try openedHistoryStore().entries(includingImages: true)
        } catch {
            logger.error("could not read the bake history with photos: \(error)")
            return []
        }
    }

    /// One entry with its photos, read afresh.
    func bakeEntry(id: String) -> StoredBakeHistory? {
        do {
            return try openedHistoryStore().entry(id: id)
        } catch {
            logger.error("could not read bake history entry \(id): \(error)")
            return nil
        }
    }

    /// Keeps a new entry for the recipe, which then counts as baked. Whether
    /// it worked.
    @discardableResult
    func addBakeEntry(toRecipe recipeID: String, date: Date, comment: String, images: [Data],
                      facts: BakeHistoryFacts) -> Bool {
        do {
            _ = try openedHistoryStore().add(toRecipe: recipeID, date: date, comment: comment, images: images,
                                             facts: facts)
            loadBakeHistory()
            load()
            return true
        } catch {
            logger.error("could not add a bake history entry to recipe \(recipeID): \(error)")
            return false
        }
    }

    /// Keeps a changed entry. Whether it worked.
    @discardableResult
    func updateBakeEntry(_ entry: StoredBakeHistory) -> Bool {
        do {
            try openedHistoryStore().update(entry)
            loadBakeHistory()
            return true
        } catch {
            logger.error("could not change bake history entry \(entry.id): \(error)")
            return false
        }
    }

    func deleteBakeEntry(id: String) {
        do {
            try openedHistoryStore().delete(id: id)
        } catch {
            logger.error("could not delete bake history entry \(id): \(error)")
        }
        loadBakeHistory()
    }

    /// The recipe's name for an entry; empty when the list has not caught up.
    func recipeName(id: String) -> String {
        recipes.first { $0.id == id }?.content.name ?? ""
    }

    // MARK: Planning

    func loadScheduledSteps() {
        do {
            scheduledSteps = try openedStepStore().allSteps()
        } catch {
            logger.error("could not read the scheduled steps: \(error)")
        }
    }

    /// The plan of `recipe` for `date`, read as its start or its finish —
    /// worked out in BakePlan, as on the iPhone.
    static func plan(of recipe: StoredRecipe, anchor: PlanAnchor, date: Date) -> BakePlan {
        BakePlan(recipeName: recipe.content.name,
                 steps: recipe.content.instructions.map {
                     PlanStep(instruction: $0.instruction, step: $0.step, startTime: $0.startTime,
                              duration: $0.duration, componentName: $0.componentName,
                              durationWindow: DurationWindow.effective(stored: $0.durationWindow,
                                                                       instruction: $0.instruction,
                                                                       duration: $0.duration),
                              oven: $0.oven)
                 },
                 prepTime: recipe.content.prepTime,
                 anchor: anchor,
                 date: date,
                 languageCode: AppSettings.locale.identifier,
                 isStarterFeeding: StarterRecipe.isStarterFeeding(recipe.content))
    }

    /// What speaks against the plan: bakes at the same time than there are
    /// ovens (errors), steps in the night (hints).
    func issues(of plan: BakePlan) -> [BakePlanIssue] {
        guard let store = try? openedStepStore() else { return [] }
        return plan.issues(from: store)
    }

    /// The findings when the plan is kept beside the recipe's earlier plans
    /// ("Zusätzlich planen"), those included.
    func additionalPlanIssues(of plan: BakePlan) -> [BakePlanIssue] {
        guard let store = try? openedStepStore() else { return [] }
        return plan.additionalPlanIssues(from: store)
    }

    /// Dates for which no step falls into the night, when some do.
    func nightFreeDates(for plan: BakePlan) -> [NightFreeDate] {
        guard BakePlanAdvisor.hasNightSteps(plan), let store = try? openedStepStore() else { return [] }
        return BakePlanAdvisor.nightFreeDates(for: plan, from: store)
    }

    /// Dates at which the oven is free for the plan's bake, when it clashes
    /// with another scheduled bake — the baking day with several loaves.
    func ovenFreeDates(for plan: BakePlan) -> [PlanDateSuggestion] {
        guard let store = try? openedStepStore(), BakePlanAdvisor.hasOvenConflict(plan, from: store) else { return [] }
        return BakePlanAdvisor.ovenFreeDates(for: plan, from: store)
    }

    /// The smallest change to the steps with a duration window that fits
    /// the plan into the day and the ovens, the date left as chosen.
    func windowSuggestion(for plan: BakePlan, of recipe: StoredRecipe) -> PlanWindowSuggestion? {
        guard let store = try? openedStepStore() else { return nil }
        return BakePlanAdvisor.windowSuggestion(for: plan,
                                                dependencies: Rational.ComponentDependency.from(recipe.content.components),
                                                from: store)
    }

    func hasPlan(recipeName: String) -> Bool {
        (try? openedStepStore().hasSteps(recipeName: recipeName)) ?? false
    }

    enum PlanOutcome: Equatable {
        case saved
        /// Saved, but the user does not allow notifications.
        case savedWithoutReminders
        case failed
    }

    /// Keeps the plan's steps — replacing the recipe's earlier plan, or
    /// beside it — with a reminder for each step ahead, and, as on the
    /// iPhone, a bake-history entry for the end of a bake, or for a starter
    /// a feeding at its start whose result is entered when it is over.
    func putIntoEffect(_ plan: BakePlan, recipeID: String, servingScale: Double, replacing: Bool,
                       isAutomaticRecurrence: Bool = false) async -> PlanOutcome {
        let planID = UUID()
        let newSteps = plan.scheduledStepData(planID: planID, servingScale: servingScale,
                                              isAutomaticRecurrence: isAutomaticRecurrence)
        let content: RecipeExportData
        do {
            guard let recipe = try openedStore().recipe(id: recipeID) else { return .failed }
            content = recipe.content
            let steps = try openedStepStore()
            if replacing {
                Reminders.cancel(scheduledSteps.map(\.data).filter { $0.recipeName == plan.recipeName })
                steps.removeSteps(recipeName: plan.recipeName)
                // The replaced plan's history entry or diary feeding goes
                // with it; the new plan writes its own below.
                try PlannedBakeEntries.remove(ofRecipe: recipeID, from: openedHistoryStore())
                try PlannedFeedingEntries.remove(ofRecipe: recipeID, from: openedFeedingStore())
                // The replaced plans give their pantry back; the new one
                // reserves below.
                releasePantry(recipeName: plan.recipeName)
            }
            steps.add(newSteps)
            reservePantry(recipe: content, planID: planID, scale: servingScale, planEnd: plan.date(of: plan.endStep))
            if StarterRecipe.isStarterFeeding(recipe.content) {
                _ = try openedFeedingStore().add(toRecipe: recipeID, date: plan.baseDate, facts: StarterFeedingFacts())
            } else {
                _ = try openedHistoryStore().add(toRecipe: recipeID, date: plan.date(of: plan.endStep),
                                                 comment: AppSettings.generatedRecipeTexts().missingComment,
                                                 images: [], facts: BakeHistoryFacts())
            }
            loadScheduledSteps()
            loadBakeHistory()
            load()
        } catch {
            logger.error("could not plan \(plan.recipeName): \(error)")
            loadScheduledSteps()
            return .failed
        }
        if isAutomaticRecurrence {
            // Nobody to ask for permission here: reminders where allowed.
            await Reminders.reschedule(newSteps, recipe: content)
            return .saved
        }
        return await Reminders.schedule(newSteps, recipe: content) ? .saved : .savedWithoutReminders
    }

    // MARK: Rhythm

    /// The recipe as the automatic pass looks at it: its last bake and,
    /// for a starter, its last feeding.
    func rhythmRecipe(_ recipe: StoredRecipe) -> RecurringBakePlanner.RhythmRecipe {
        RecurringBakePlanner.RhythmRecipe(
            content: recipe.content,
            lastBakeFinish: bakeHistory.filter { $0.recipeID == recipe.id }.map(\.date).max(),
            lastFeedingStart: feedings(ofRecipe: recipe.id).first?.date)
    }

    /// When the recipe's rhythm next comes round — the start of its first
    /// step — or nil before its first bake or feeding.
    func nextRhythmStart(of recipe: StoredRecipe, now: Date = Date()) -> Date? {
        let rhythm = rhythmRecipe(recipe)
        let duration = RecurringBakePlanner.planDuration(of: recipe.content)
        let isStarter = StarterRecipe.isStarterFeeding(recipe.content)
        return RecurringBakePlanner.nextStart(
            lastFinish: RecurringBakePlanner.rhythmFinish(lastBakeFinish: rhythm.lastBakeFinish,
                                                          lastFeedingStart: isStarter ? rhythm.lastFeedingStart : nil,
                                                          duration: duration),
            duration: duration, intervalDays: recipe.content.recurrenceIntervalDays, now: now)
    }

    /// The automatic pass, as on the iPhone whenever the app comes to the
    /// foreground: every recipe on a rhythm that is due gets its next plan
    /// — steps marked as automatic (shown two days ahead), reminders, and
    /// the bake-history entry or, for a starter, the feeding. Recipe by
    /// recipe, so two due at once do not take the same oven.
    func scheduleDueOccurrences() async {
        guard let store = try? openedStepStore() else { return }
        // The serving size from the settings, as the iPhone takes it
        // (2 is the recipe as stored).
        let scale = Double(AppSettings.storedServingSize) / 2
        for recipe in recipes where recipe.content.recurrenceIntervalDays > 0 {
            guard let plan = RecurringBakePlanner.dueOccurrence(of: rhythmRecipe(recipe), steps: store) else { continue }
            logger.info("automatic occurrence of \(recipe.content.name) at \(plan.baseDate)")
            _ = await putIntoEffect(plan, recipeID: recipe.id, servingScale: scale, replacing: false,
                                    isAutomaticRecurrence: true)
        }
    }

    enum ShiftOutcome: Equatable {
        case moved
        /// The step would land at or before now.
        case dateInPast
        case failed
    }

    /// Moves a planned step by `minutes` (negative for earlier) — with the
    /// later steps of its plan if `includeFollowing` — by the rule the
    /// iPhone follows (ScheduledStepShift), reminders included.
    func shift(_ step: StoredScheduledStep, byMinutes minutes: Int, includeFollowing: Bool) async -> ShiftOutcome {
        let dates: [String: Date]
        do {
            dates = try ScheduledStepShift.newDates(shifting: step.key, byMinutes: minutes,
                                                    includeFollowing: includeFollowing, in: scheduledSteps)
            try openedStepStore().setDates(dates)
        } catch ScheduledStepShift.Failure.dateInPast {
            return .dateInPast
        } catch {
            logger.error("could not move step \(step.key): \(error)")
            loadScheduledSteps()
            return .failed
        }
        loadScheduledSteps()
        let moved = scheduledSteps.filter { dates[$0.key] != nil }.map(\.data)
        let recipe = recipes.first { $0.content.name == step.data.recipeName }?.content
        await Reminders.reschedule(moved, recipe: recipe)
        return .moved
    }

    /// The step is done: it goes from the timeline, its reminder with it.
    func markDone(_ step: StoredScheduledStep) {
        Reminders.cancel([step.data])
        try? openedStepStore().removeStep(key: step.key)
        loadScheduledSteps()
        // The last step done: the plan has ended, its reservations become
        // deductions.
        reconcilePantry()
    }

    /// Removes every step of one plan, and their reminders. A recipe
    /// without any plan left loses the history entries its plans wrote,
    /// unless someone has written into them (PlannedBakeEntries).
    func deletePlan(_ steps: [StoredScheduledStep]) {
        Reminders.cancel(steps.map(\.data))
        if let store = try? openedStepStore() {
            for step in steps {
                store.removeStep(key: step.key)
            }
            releasePantry(planIDs: steps.compactMap(\.data.planID))
            for name in Set(steps.map(\.data.recipeName)) where !store.hasSteps(recipeName: name) {
                // Steps stored before they had a plan id: nothing of the
                // recipe is planned any more, so nothing stays reserved.
                releasePantry(recipeName: name)
                guard let recipe = recipes.first(where: { $0.content.name == name }) else { continue }
                do {
                    try PlannedBakeEntries.remove(ofRecipe: recipe.id, from: openedHistoryStore())
                    try PlannedFeedingEntries.remove(ofRecipe: recipe.id, from: openedFeedingStore())
                } catch {
                    logger.error("could not remove the planned history entries of \(name): \(error)")
                }
            }
        }
        loadScheduledSteps()
        loadBakeHistory()
    }

    // MARK: Starter feeding diary

    /// The feedings of a starter's recipe, newest first.
    func feedings(ofRecipe recipeID: String) -> [StoredStarterFeeding] {
        do {
            return try openedFeedingStore().feedings(ofRecipe: recipeID)
        } catch {
            logger.error("could not read the feedings of recipe \(recipeID): \(error)")
            return []
        }
    }

    /// Keeps a new feeding. Whether it worked.
    @discardableResult
    func addFeeding(toRecipe recipeID: String, date: Date, facts: StarterFeedingFacts) -> Bool {
        do {
            _ = try openedFeedingStore().add(toRecipe: recipeID, date: date, facts: facts)
            return true
        } catch {
            logger.error("could not add a feeding to recipe \(recipeID): \(error)")
            return false
        }
    }

    /// Enters the result of a feeding — peak time, float test, note.
    /// Whether it worked.
    @discardableResult
    func updateFeeding(_ feeding: StoredStarterFeeding) -> Bool {
        do {
            try openedFeedingStore().update(feeding)
            return true
        } catch {
            logger.error("could not enter the result of feeding \(feeding.id): \(error)")
            return false
        }
    }

    func deleteFeeding(id: String) {
        do {
            try openedFeedingStore().delete(id: id)
        } catch {
            logger.error("could not delete feeding \(id): \(error)")
        }
    }

    // MARK: Shopping lists

    func loadShoppingLists() {
        do {
            shoppingLists = try openedListStore().lists()
        } catch {
            logger.error("could not read the shopping lists: \(error)")
        }
    }

    /// Puts the ingredients of recipe `recipeID`, at `scale` (1 is the
    /// recipe as stored), on a shopping list — sifted, converted and merged
    /// as on the iPhone (ShoppingListBuilder).
    /// Whose ingredients go on a shopping list.
    enum ShoppingListSource {
        /// One of the own recipes, by its key.
        case own(String)
        /// A public recipe, as shown; the list names it, as on the iPhone.
        case shared(RecipeExportData)
    }

    func addToShoppingList(_ source: ShoppingListSource, scale: Double, target: ShoppingListTarget) -> ShoppingListOutcome {
        do {
            let content: RecipeExportData
            let recipeSource: ShoppingListRecipe
            switch source {
            case .own(let recipeID):
                guard let recipe = try openedStore().recipe(id: recipeID) else { return .failed }
                content = recipe.content
                recipeSource = .own(id: recipeID)
            case .shared(let shared):
                content = shared
                recipeSource = .publicRecipe(name: shared.name)
            }
            let needed = ShoppingListBuilder.entriesToBuy(ShoppingListBuilder.entries(of: content), scale: scale)
            guard !needed.isEmpty else { return .nothingToBuy }
            // What the pantry covers stays off the list, as on the iPhone.
            let entries = deductsPantry ? PantryMatcher.reduce(needed, pantry: availablePantry) : needed
            guard !entries.isEmpty else { return .allInPantry }

            let lists = try openedListStore()
            let listID: String
            switch target {
            case .newList(let date):
                listID = try lists.list(onSameDayAs: date)?.id ?? lists.addList(on: date).id
            case .existingList(let id):
                listID = id
            }
            try lists.add(entries, from: recipeSource, toList: listID)
            loadShoppingLists()
            return .added
        } catch {
            logger.error("could not put a recipe on a shopping list: \(error)")
            loadShoppingLists()
            return .failed
        }
    }

    /// Keeps a changed line of a shopping list.
    func update(_ item: StoredShoppingListItem) {
        do {
            try openedListStore().update(item)
        } catch {
            logger.error("could not change shopping list line \(item.id): \(error)")
        }
        loadShoppingLists()
    }

    /// Takes one line off its shopping list.
    func deleteShoppingListItem(id: String) {
        do {
            try openedListStore().deleteItem(id: id)
        } catch {
            logger.error("could not remove shopping list line \(id): \(error)")
        }
        loadShoppingLists()
    }

    /// Removes a shopping list with its lines; the recipes stay.
    func deleteShoppingList(id: String) {
        do {
            try openedListStore().delete(id: id)
        } catch {
            logger.error("could not delete shopping list \(id): \(error)")
        }
        loadShoppingLists()
    }

    /// Writes the recipes `ids` into a backup file, as the iPhone app reads
    /// it, and returns where it lies — in the app's cache, ready to be
    /// handed to the system's "save as". The full backup carries the bake
    /// history and the feeding diary along; a single recipe saved to pass
    /// on does not.
    func exportFile(recipeIDs ids: [String], named name: String, includingBakeHistory: Bool) -> URL? {
        do {
            let file: RecipeExportFile
            if includingBakeHistory {
                // Photos picked before they were made small on picking
                // are made small here, as the iPhone does.
                file = try RecipeExportFile(recipeIDs: ids, from: openedStore(), bakeHistory: openedHistoryStore(),
                                            starterFeedings: openedFeedingStore(), pantry: openedPantryStore(),
                                            shrinkPhoto: PhotoShrinker.shrunk)
            } else {
                file = try RecipeExportFile(recipeIDs: ids, from: openedStore())
            }
            let folder = URL.cachesDirectory.appendingPathComponent("Export", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
            let url = folder.appendingPathComponent(safeName.isEmpty ? "Rezept" : safeName).appendingPathExtension("json")
            try file.encoded().write(to: url, options: .atomic)
            return url
        } catch {
            logger.error("could not write a backup file: \(error)")
            return nil
        }
    }

    /// "BakePlanner-Rezepte-2026-10-31", as the iPhone app names its backups.
    static var backupFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "BakePlanner-Rezepte-\(formatter.string(from: Date()))"
    }

    /// Reads a backup or recipe file — as the iPhone app writes it — into
    /// the database, every recipe as a new one, with the bake history the
    /// file carries.
    func importFile(at url: URL) {
        #if !os(Android)
        // On iOS the picked file is only readable while its access lasts;
        // on Android the picker hands over a copy in the app's cache.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let data = try Data(contentsOf: url)
            // The file's pantry items the pantry does not have by name
            // come along, as on the iPhone.
            let result = try RecipeImport.importFile(data, into: openedStore(), bakeHistory: openedHistoryStore(),
                                                     starterFeedings: openedFeedingStore(), pantry: openedPantryStore())
            importOutcome = .imported(result.recipes, pantryItems: result.pantryItems)
        } catch {
            logger.error("could not import \(url.lastPathComponent): \(error)")
            importOutcome = .failed(error.localizedDescription)
        }
        load()
        loadBakeHistory()
        loadPantry()
    }

    // MARK: Public recipes

    /// Reads the public recipes afresh, in the app's language.
    func loadPublicRecipes() async {
        guard !isLoadingPublicRecipes else { return }
        isLoadingPublicRecipes = true
        defer { isLoadingPublicRecipes = false }
        do {
            // An admin sees the reported recipes too, to review them.
            await refreshAccount()
            publicRecipes = try await PublicRecipeService.recipes(includingHidden: account.isAdmin)
            publicRecipesError = nil
        } catch PublicRecipeService.ServiceError.unavailable {
            publicRecipes = []
            publicRecipesError = nil
        } catch {
            logger.error("could not read the public recipes: \(error)")
            publicRecipesError = error.localizedDescription
        }
    }

    /// The recipe behind a planned step, for its ingredients and picture:
    /// the own recipe of that name, else the public recipe of that name
    /// once its components have been read (opening its page does that; a
    /// plan is made from the page, so they are there). A step planned from
    /// the database has no copy on the device.
    func plannedRecipeContent(named name: String) -> RecipeExportData? {
        if let own = recipes.first(where: { $0.content.name == name }) {
            return own.content
        }
        if let shared = visiblePublicRecipes.first(where: { $0.name == name }), !shared.components.isEmpty {
            return RecipeExportData(recipeFB: shared, imageData: nil)
        }
        return nil
    }

    /// A public recipe as the recipe page shows it: components, steps and
    /// picture read on first opening, then kept.
    func publicRecipeContent(_ recipe: RecipeFB) async throws -> RecipeExportData {
        try await PublicRecipeService.loadDetails(of: recipe)
        let id = recipe.id ?? ""
        if publicRecipeImages[id] == nil, let data = await PublicRecipeService.imageData(of: recipe) {
            publicRecipeImages[id] = data
        }
        return RecipeExportData(recipeFB: recipe, imageData: publicRecipeImages[id])
    }

    /// Anonymous or signed in with Apple (Settings → "Konto").
    var account = PublicRecipeService.Account()

    func refreshAccount() async {
        account = await PublicRecipeService.account()
    }

    /// Signs in with Apple; nil when it worked, else why not. The public
    /// recipes are read again under the new account.
    func signInWithApple() async -> String? {
        await changeAccount { try await PublicRecipeService.signInWithApple() }
    }

    func signOut() async -> String? {
        await changeAccount { try await PublicRecipeService.signOut() }
    }

    func deleteAccount() async -> String? {
        await changeAccount { try await PublicRecipeService.deleteAccount() }
    }

    private func changeAccount(_ change: () async throws -> Void) async -> String? {
        var failure: String?
        do {
            try await change()
        } catch {
            logger.error("account change failed: \(error)")
            // The full description: an error coming from Kotlin reads only
            // "SwiftJNI.ThrowableError error 1." as localizedDescription,
            // its description carries the Kotlin exception's message.
            failure = String(describing: error)
        }
        await refreshAccount()
        await loadPublicRecipes()
        return failure
    }

    // MARK: Publishing

    /// Whether the user has accepted the terms for public recipes, once,
    /// as on the iPhone (same key).
    var hasAcceptedTerms: Bool {
        get { Self.storedBool("ugc.eulaAccepted", default: false) }
        set { SettingsFile.set(newValue, forKey: "ugc.eulaAccepted") }
    }

    /// Whether a public recipe is the user's own: published under the
    /// account signed in here. Empty author ids (old recipes) never match.
    func isOwn(_ recipe: RecipeFB) -> Bool {
        guard let author = recipe.authorId, !author.isEmpty, let uid = PublicRecipeService.currentUID else { return false }
        return author == uid
    }

    /// Whether an own recipe may be published: not yet, or its public copy
    /// is gone again (deleted elsewhere), as the iPhone decides.
    func canPublish(_ recipe: StoredRecipe) -> Bool {
        guard let firestoreID = recipe.firestoreId, !firestoreID.isEmpty else { return true }
        return !publicRecipes.contains { $0.id == firestoreID }
    }

    /// Publishes an own recipe; nil when it worked, else why not. The
    /// recipe remembers its public id, as on the iPhone, and the public
    /// list is read again.
    func publish(recipeID: String) async -> String? {
        guard var recipe = recipe(id: recipeID), let image = recipe.content.image,
              let upload = PhotoShrinker.uploadPhoto(image) else { return nil }
        do {
            let publicID = try await PublicRecipeService.publish(recipe.content, image: upload)
            recipe.firestoreId = publicID
            try openedStore().update(recipe)
            load()
        } catch {
            logger.error("could not publish recipe \(recipeID): \(error)")
            return String(describing: error)
        }
        await loadPublicRecipes()
        return nil
    }

    /// Saves an edit of a published recipe; nil when it worked. The new
    /// picture, if the edit changed it, goes along.
    func saveEdits(of recipe: RecipeFB, content: RecipeExportData) async -> String? {
        let id = recipe.id ?? ""
        let newImage = content.image != publicRecipeImages[id] ? content.image.flatMap { PhotoShrinker.uploadPhoto($0) } : nil
        do {
            try await PublicRecipeService.saveEdits(of: recipe, content: content, newImage: newImage)
            if let newImage {
                publicRecipeImages[id] = newImage
                publicThumbnails[id] = nil
            }
        } catch {
            logger.error("could not save edits of public recipe \(id): \(error)")
            return String(describing: error)
        }
        await loadPublicRecipes()
        return nil
    }

    /// Removes a published recipe (own, or any as an admin); nil when it
    /// worked.
    func deletePublic(_ recipe: RecipeFB) async -> String? {
        do {
            try await PublicRecipeService.delete(recipe)
        } catch {
            logger.error("could not delete public recipe \(recipe.id ?? ""): \(error)")
            return String(describing: error)
        }
        publicRecipes.removeAll { $0.id == recipe.id }
        return nil
    }

    /// Releases a reported recipe again (admins); nil when it worked.
    func release(_ recipe: RecipeFB) async -> String? {
        do {
            try await PublicRecipeService.setHidden(recipe, hidden: false)
        } catch {
            logger.error("could not release public recipe \(recipe.id ?? ""): \(error)")
            return String(describing: error)
        }
        return nil
    }

    /// Reports a public recipe. It leaves this device's list at once, even
    /// should the report not get through (as on the iPhone); the server
    /// withholds it from everybody else.
    func report(_ recipe: RecipeFB, reason: String) async {
        if let id = recipe.id, !id.isEmpty {
            reportedRecipeIDs.insert(id)
        }
        do {
            try await PublicRecipeService.report(recipe, reason: reason)
        } catch {
            logger.error("could not report public recipe \(recipe.id ?? ""): \(error)")
        }
    }

    /// Hides every public recipe of the recipe's author, on this device only.
    func blockAuthor(of recipe: RecipeFB) {
        guard let author = recipe.authorId, !author.isEmpty else { return }
        blockedAuthors.insert(author)
    }

    /// What the public recipe becomes as an own copy (PublicRecipeCopy):
    /// what planning and taking over work from.
    func publicRecipeCopyContent(_ recipe: RecipeFB) async throws -> RecipeExportData {
        try await PublicRecipeService.loadDetails(of: recipe)
        let id = recipe.id ?? ""
        if publicRecipeImages[id] == nil, let data = await PublicRecipeService.imageData(of: recipe) {
            publicRecipeImages[id] = data
        }
        return PublicRecipeCopy.content(of: recipe, imageData: publicRecipeImages[id])
    }

    /// The own copy of a public recipe — the one taken over before, if there
    /// is one, else a new one. An earlier copy is never written over: the
    /// user may have changed it, and its bake history is his own (as on the
    /// iPhone). Nil when it could not be read or kept.
    func takeOver(_ recipe: RecipeFB) async -> StoredRecipe? {
        guard let firestoreID = recipe.id, !firestoreID.isEmpty else { return nil }
        do {
            let store = try openedStore()
            if let copy = try store.recipe(firestoreId: firestoreID) {
                return copy
            }
            let content = try await publicRecipeCopyContent(recipe)
            let copy = try store.add(content, firestoreId: firestoreID, adjustedOn: nil, bakeHistoryFlag: false)
            load()
            return copy
        } catch {
            logger.error("could not take over public recipe \(firestoreID): \(error)")
            return nil
        }
    }

    // MARK: Pantry

    /// Reads the pantry, its reservations and the last bookings.
    func loadPantry() {
        do {
            pantryItems = try openedPantryStore().items()
            pantryReservations = try openedReservationStore().reservations()
        } catch {
            logger.error("could not read the pantry: \(error)")
        }
        pantryBookings = Self.storedBookings()
    }

    /// The pantry as the recipes compare against it: the stock less what
    /// the open plans have reserved.
    var availablePantry: [StoredPantryItem] {
        PantryLedger.available(pantryItems, reservations: pantryReservations)
    }

    /// The names of the recipes' bought ingredients, most used first, for
    /// the editor's suggestions.
    var pantrySuggestions: [String] {
        Pantry.suggestedNames(from: recipes.map(\.content))
    }

    func addPantryItem(name: String, amount: Double, unit: PantryUnit, bestBefore: Date?, note: String) -> Bool {
        defer { loadPantry() }
        do {
            _ = try openedPantryStore().add(name: name, amount: amount, unit: unit, bestBefore: bestBefore, note: note)
            return true
        } catch {
            logger.error("could not add a pantry item: \(error)")
            return false
        }
    }

    func updatePantryItem(_ item: StoredPantryItem) -> Bool {
        defer { loadPantry() }
        do {
            try openedPantryStore().update(item)
            return true
        } catch {
            logger.error("could not change pantry item \(item.id): \(error)")
            return false
        }
    }

    func deletePantryItem(id: String) {
        do {
            try openedPantryStore().delete(id: id)
        } catch {
            logger.error("could not remove pantry item \(id): \(error)")
        }
        loadPantry()
    }

    /// A bought shopping-list line as it is booked: what was bought of it.
    struct PantryIntakeLine {
        var item: StoredShoppingListItem
        var amount: Double
        var unit: PantryUnit
    }

    /// What an intake ended with.
    struct PantryIntakeResult: Equatable {
        let booked: Int
        /// The list had no lines left and was deleted.
        let finished: Bool
    }

    /// Books every line with an amount onto the item of the same name — or
    /// a new one — and takes it off its list. Lines at 0 stay; a list
    /// without lines is deleted.
    func receiveIntoPantry(_ lines: [PantryIntakeLine], fromList listID: String) -> PantryIntakeResult {
        var booked = 0
        do {
            let pantry = try openedPantryStore()
            let lists = try openedListStore()
            for line in lines where line.amount > 0 {
                try pantry.receive(name: line.item.name, amount: line.amount, unit: line.unit)
                try lists.deleteItem(id: line.item.id)
                booked += 1
            }
            let finished = try lists.lists().first { $0.id == listID }?.items.isEmpty ?? false
            if finished {
                try lists.delete(id: listID)
            }
            loadPantry()
            loadShoppingLists()
            return PantryIntakeResult(booked: booked, finished: finished)
        } catch {
            logger.error("could not book the shopping list into the pantry: \(error)")
            loadPantry()
            loadShoppingLists()
            return PantryIntakeResult(booked: booked, finished: false)
        }
    }

    /// Reserves what the plan's bread uses of the available pantry, item by
    /// item, under the plan's id. The arithmetic is PantryLedger in the
    /// package, as on the iPhone (PantryLedgerService).
    func reservePantry(recipe: RecipeExportData, planID: UUID, scale: Double, planEnd: Date) {
        do {
            let items = try openedPantryStore()
            let reservations = try openedReservationStore()
            // A plan replaced under the same id must not reserve twice.
            try reservations.delete(planID: planID)
            let available = PantryLedger.available(try items.items(), reservations: try reservations.reservations())
            for deduction in PantryMatcher.deductions(for: recipe, scale: scale, pantry: available) where deduction.taken > 0 {
                _ = try reservations.add(planID: planID, recipeName: recipe.name, itemID: deduction.item.uuid,
                                         amount: deduction.taken, unit: deduction.item.unit, planEnd: planEnd)
            }
        } catch {
            logger.error("could not reserve the pantry for \(recipe.name): \(error)")
        }
        loadPantry()
    }

    /// Releases every reservation of these plans — plans deleted.
    func releasePantry(planIDs: [UUID]) {
        guard !planIDs.isEmpty, let store = try? openedReservationStore() else { return }
        for planID in Set(planIDs) {
            do {
                try store.delete(planID: planID)
            } catch {
                logger.error("could not release the pantry of plan \(planID): \(error)")
            }
        }
        loadPantry()
    }

    /// Releases the reservations of every plan of the recipe — the plans
    /// replaced by a new one.
    func releasePantry(recipeName: String) {
        guard let all = try? openedReservationStore().reservations() else { return }
        releasePantry(planIDs: all.filter { $0.recipeName == recipeName }.map(\.planID))
    }

    /// Turns every reservation whose plan has ended into a deduction and
    /// notes the booking so it can be undone. Run when the app comes
    /// forward and after a step is marked done.
    func reconcilePantry(now: Date = Date()) {
        do {
            let itemStore = try openedPantryStore()
            let reservationStore = try openedReservationStore()
            let due = PantryLedger.dueForConversion(try reservationStore.reservations(), now: now)
            guard !due.isEmpty else { return }
            var items = try itemStore.items()
            var bookings = Self.storedBookings()
            for reservation in due {
                if let index = items.firstIndex(where: { $0.uuid == reservation.itemID }) {
                    let after = PantryLedger.converted(items[index], by: reservation)
                    try itemStore.update(after)
                    items[index] = after
                    bookings.insert(PantryBooking(date: now, recipeName: reservation.recipeName, itemID: reservation.itemID,
                                                  itemName: after.name, amount: reservation.amount, unit: reservation.unit), at: 0)
                }
                // The item is gone: nothing to take from, the reservation goes too.
                try reservationStore.delete(id: reservation.id)
            }
            Self.storeBookings(Array(bookings.prefix(Self.keptBookings)))
        } catch {
            logger.error("could not book the ended plans against the pantry: \(error)")
        }
        loadPantry()
    }

    /// Puts a booking back: the amount returns to the item, the booking
    /// leaves the list.
    func undoPantryBooking(_ booking: PantryBooking) {
        do {
            let store = try openedPantryStore()
            if var item = try store.items().first(where: { $0.uuid == booking.itemID }) {
                let base = item.baseAmount + booking.amount * (booking.unit.grams ?? 1)
                item.amount = base / (item.unit.grams ?? 1)
                try store.update(item)
            }
        } catch {
            logger.error("could not undo a pantry booking: \(error)")
        }
        Self.storeBookings(Self.storedBookings().filter { $0.id != booking.id })
        loadPantry()
    }

    private static let bookingsKey = "pantryBookings"
    private static let keptBookings = 20

    private static func storedBookings() -> [PantryBooking] {
        guard let text = SettingsFile.value(forKey: bookingsKey) as? String,
              let data = text.data(using: .utf8),
              let bookings = try? JSONDecoder().decode([PantryBooking].self, from: data) else { return [] }
        return bookings
    }

    private static func storeBookings(_ bookings: [PantryBooking]) {
        guard let data = try? JSONEncoder().encode(bookings), let text = String(data: data, encoding: .utf8) else { return }
        SettingsFile.set(text, forKey: bookingsKey)
    }

    private func openedPantryStore() throws -> SQLitePantryStore {
        if let pantryStore { return pantryStore }
        let opened = SQLitePantryStore(file: try openedStore().file)
        pantryStore = opened
        return opened
    }

    private func openedReservationStore() throws -> SQLitePantryReservationStore {
        if let reservationStore { return reservationStore }
        let opened = SQLitePantryReservationStore(file: try openedStore().file)
        reservationStore = opened
        return opened
    }

    private func openedStore() throws -> SQLiteRecipeStore {
        if let store { return store }
        let folder = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let opened = try SQLiteRecipeStore(path: folder.appendingPathComponent("recipes.sqlite").path)
        store = opened
        return opened
    }

    /// The scheduled steps, in the same database file as the recipes.
    private func openedStepStore() throws -> SQLiteScheduledStepStore {
        if let stepStore { return stepStore }
        let opened = SQLiteScheduledStepStore(file: try openedStore().file)
        stepStore = opened
        return opened
    }

    /// The starter feeding diary, in the same database file as the recipes.
    private func openedFeedingStore() throws -> SQLiteStarterFeedingLogStore {
        if let feedingStore { return feedingStore }
        let opened = SQLiteStarterFeedingLogStore(file: try openedStore().file)
        feedingStore = opened
        return opened
    }

    /// The bake history, in the same database file as the recipes.
    private func openedHistoryStore() throws -> SQLiteBakeHistoryStore {
        if let historyStore { return historyStore }
        let opened = SQLiteBakeHistoryStore(file: try openedStore().file)
        historyStore = opened
        return opened
    }

    /// The shopping lists, in the same database file as the recipes.
    private func openedListStore() throws -> SQLiteShoppingListStore {
        if let listStore { return listStore }
        let opened = SQLiteShoppingListStore(file: try openedStore().file)
        listStore = opened
        return opened
    }
}
