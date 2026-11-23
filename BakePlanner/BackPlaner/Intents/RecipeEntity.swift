//
//  RecipeEntity.swift
//  BackPlaner
//
//  The user's own recipes as App Intents entities, so Spotlight finds them
//  by name, tag or description and opens the app on the recipe's page.
//  The entity is indexed by RecipeSpotlightIndexer; the query answers the
//  system's lookups and reindexing requests, and OpenRecipeIntent is what
//  Spotlight runs on a tap. The id is the recipe's own UUID
//  (`Recipe.reminderId`), which travels with the recipe through iCloud.
//

import AppIntents
import CoreData
import CoreSpotlight
import UIKit

struct RecipeEntity: IndexedEntity {

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rezept")
    static let defaultQuery = RecipeQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Beschreibung")
    var summary: String

    @Property(title: "Tags")
    var tags: [String]

    /// A small JPEG of the recipe's picture, for the search result.
    var thumbnail: Data?

    var displayRepresentation: DisplayRepresentation {
        let subtitle: String? = !tags.isEmpty ? tags.joined(separator: ", ") : (summary.isEmpty ? nil : summary)
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.map { "\($0)" },
            image: thumbnail.map { DisplayRepresentation.Image(data: $0) }
        )
    }

    /// What Spotlight indexes: the name, the description, the tags.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = name
        attributes.displayName = name
        attributes.contentDescription = summary.isEmpty ? nil : summary
        attributes.keywords = tags
        attributes.thumbnailData = thumbnail
        return attributes
    }

    /// On the main actor: the recipe comes from the view context.
    @MainActor
    init(recipe: Recipe) {
        id = recipe.reminderId
        name = recipe.name
        summary = recipe.summary
        tags = recipe.tags
        thumbnail = Self.thumbnailData(from: recipe.image)
    }

    /// Spotlight keeps every item's attributes in memory: a 120-point
    /// thumbnail instead of the photo.
    static func thumbnailData(from imageData: Data) -> Data? {
        guard !imageData.isEmpty, let image = UIImage(data: imageData) else { return nil }
        let size = CGSize(width: 120, height: 120)
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2,
                                  width: scaled.width, height: scaled.height))
        }
        return thumbnail.jpegData(compressionQuality: 0.7)
    }
}

/// Lookups for Spotlight, Siri and Shortcuts, on the view context. The
/// system's reindexing hooks (IndexedEntityQuery) need iOS 27; until then
/// RecipeSpotlightIndexer rebuilds the index itself once per launch.
struct RecipeQuery: EntityStringQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [RecipeEntity] {
        try RecipeLookup.recipes().filter { identifiers.contains($0.reminderId) }.map(RecipeEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RecipeEntity] {
        try RecipeLookup.recipes()
            .filter { $0.name.localizedStandardContains(string) || $0.tags.contains { $0.localizedStandardContains(string) } }
            .map(RecipeEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RecipeEntity] {
        try RecipeLookup.recipes().prefix(20).map(RecipeEntity.init)
    }
}

/// What Spotlight runs when a recipe is tapped: the app opens on its page.
struct OpenRecipeIntent: OpenIntent {

    static let title: LocalizedStringResource = "Rezept öffnen"
    static let description = IntentDescription("Öffnet ein eigenes Rezept in BakePlanner.")
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Rezept")
    var target: RecipeEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(RecipeDeepLink.url(recipeID: target.id)))
    }
}

/// `bakeplanner://recipe/<id>`: the app's own link to a recipe, taken by
/// ContentView.onOpenURL.
enum RecipeDeepLink {
    static let host = "recipe"

    static func url(recipeID: String) -> URL {
        var components = URLComponents()
        components.scheme = "bakeplanner"
        components.host = host
        components.path = "/" + recipeID
        return components.url ?? URL(string: "bakeplanner://\(host)")!
    }

    static func recipeID(from url: URL) -> String? {
        guard url.scheme == "bakeplanner", url.host == host else { return nil }
        let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return id.isEmpty ? nil : id
    }
}

/// The user's own recipes, by name, from the view context.
enum RecipeLookup {

    nonisolated static var context: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    @MainActor
    static func recipes(in context: NSManagedObjectContext = context) throws -> [Recipe] {
        let request = Recipe.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true,
                                                    selector: #selector(NSString.localizedStandardCompare(_:)))]
        return try context.fetch(request)
    }

    @MainActor
    static func recipe(withID id: String, in context: NSManagedObjectContext = context) throws -> Recipe? {
        try recipes(in: context).first { $0.reminderId == id }
    }
}
