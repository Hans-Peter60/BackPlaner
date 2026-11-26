//
//  DishEntity.swift
//  CookPlanner
//
//  The dishes as App Intents entities, so Spotlight finds them by name,
//  component or ingredient and opens the app on the dish's plan, and so
//  Siri can be told which dish to cook. Indexed by DishSpotlightIndexer;
//  the query answers the system's lookups; OpenDishIntent is what
//  Spotlight runs on a tap. The id is the dish's own id, which travels
//  with it through iCloud.
//

import AppIntents
import BakePlannerCore
import CoreSpotlight
import Foundation

struct DishEntity: IndexedEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Gericht")
    static let defaultQuery = DishQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Komponenten")
    var components: [String]

    @Property(title: "Zutaten")
    var ingredients: [String]

    /// A small JPEG of the latest result's photo, for the search result.
    var thumbnail: Data?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: components.isEmpty ? nil : "\(components.joined(separator: " · "))",
            image: thumbnail.map { DisplayRepresentation.Image(data: $0) }
        )
    }

    /// What Spotlight indexes: the name, the components, the ingredients.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = name
        attributes.displayName = name
        attributes.contentDescription = components.isEmpty ? nil : components.joined(separator: " · ")
        attributes.keywords = components + ingredients
        attributes.thumbnailData = thumbnail
        return attributes
    }

    @MainActor
    init(dish: KitchenDish) {
        id = dish.id
        name = dish.name
        components = dish.components
        ingredients = Array(Set(dish.ingredients.map(\.name))).sorted()
        thumbnail = CookRunLog.shared.spotlightThumbnail(forDish: dish.id)
    }
}

/// Lookups for Spotlight, Siri and Shortcuts: the cook's own dishes and the
/// examples, by name, component or ingredient.
struct DishQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [DishEntity] {
        DishLookup.all().filter { identifiers.contains($0.id) }.map(DishEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [DishEntity] {
        DishLookup.all().filter { KitchenDishFilter.matches($0, searchText: string) }.map(DishEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [DishEntity] {
        DishLookup.all().prefix(20).map(DishEntity.init)
    }
}

/// What Spotlight runs when a dish is tapped: the app opens on its plan.
struct OpenDishIntent: OpenIntent {

    static let title: LocalizedStringResource = "Gericht öffnen"
    static let description = IntentDescription("Öffnet ein Gericht in CookPlanner.")
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Gericht")
    var target: DishEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DishDeepLink.url(dishID: target.id)))
    }
}

/// `cookplanner://dish/<id>`, with `?cook=1` to start cooking at once: the
/// app's own link to a dish, taken by DishListView.onOpenURL.
enum DishDeepLink {
    static let host = "dish"

    static func url(dishID: String, startsCooking: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = "cookplanner"
        components.host = host
        components.path = "/" + dishID
        if startsCooking { components.queryItems = [URLQueryItem(name: "cook", value: "1")] }
        return components.url ?? URL(string: "cookplanner://\(host)")!
    }

    /// The dish id and whether cooking should start, or nil for any other link.
    static func parse(_ url: URL) -> (dishID: String, startsCooking: Bool)? {
        guard url.scheme?.lowercased() == "cookplanner", url.host()?.lowercased() == host else { return nil }
        let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !id.isEmpty else { return nil }
        let cook = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .contains { $0.name == "cook" && $0.value == "1" } ?? false
        return (id, cook)
    }
}

/// The dishes the intents and the index work on: the cook's own first,
/// then the examples.
@MainActor
enum DishLookup {
    static func all() -> [KitchenDish] {
        (DishLibrary.current?.dishes ?? []) + KitchenSampleDishes.all
    }

    static func dish(id: String) -> KitchenDish? {
        all().first { $0.id == id }
    }
}

/// What a link or Siri asked the app to do once it is in front: start
/// cooking a dish. Observable, so the plan screen acts on it whenever it
/// appears — right after a cold launch as well as when it is already open.
@Observable @MainActor
final class AppRequests {
    static let shared = AppRequests()
    /// The dish whose cook mode should open; cleared once it did.
    var cookDishID: String?

    /// A keyboard command for the screen in front; cleared once taken.
    enum Command: Equatable {
        case newDish, newMenu, settings, focusSearch, startCooking
    }
    var command: Command?
}
