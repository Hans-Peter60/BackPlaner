//
//  BakeHistoriesListView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.02.22.
//

import BakePlannerCore
import SwiftUI
import CoreData

/// How the baking history is laid out: the table-like list or a gallery of
/// photo tiles, one entry per bake — or summed up per recipe, as the hit
/// list (most baked first) or the photo cloud (one circle per recipe, its
/// size following the count). Persisted, since whoever prefers one view
/// prefers it every time. The hit list used to be a screen of its own in
/// the main menu; it is the same history, grouped and sorted.
enum BakeHistoryLayout: String, CaseIterable, Identifiable {
    case list
    case gallery
    case hitList
    case cloud

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .list:    "Liste"
        case .gallery: "Galerie"
        case .hitList: "Hit-Liste"
        case .cloud:   "Fotowolke"
        }
    }

    var systemImage: String {
        switch self {
        case .list:    "list.bullet"
        case .gallery: "square.grid.2x2"
        case .hitList: "trophy"
        case .cloud:   "circle.hexagongrid"
        }
    }
}

struct BakeHistoriesListView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(format: "recipe != nil"))
    private var bakeHistories: FetchedResults<BakeHistory>
    
    @State private var filterBy           = ""
    @State private var nameOrTag          = 1
    @State private var rating             = 0
    @State private var bakeHistoryComment = ""
    @State private var bakeHistoryImages  = [Data]()
    
    @State var isBigImageShowing          = false

    @AppStorage(AppSettingsKeys.bakeHistoryLayout) private var layoutRawValue = BakeHistoryLayout.list.rawValue

    // At the accessibility text sizes the gallery shows one tile per row and
    // the list stacks date, recipe and comment instead of using columns.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: BakeHistoryLayout {
        BakeHistoryLayout(rawValue: layoutRawValue) ?? .list
    }
    
    /// The entries of recipes that are baked. A starter is fed, not baked:
    /// entries older versions wrote when it was planned stay stored but are
    /// not shown.
    private var bakedHistories: [BakeHistory] {
        var isStarter: [NSManagedObjectID: Bool] = [:]
        return bakeHistories.filter { history in
            guard let recipe = history.recipe else { return false }
            if let known = isStarter[recipe.objectID] { return !known }
            let starter = StarterRecipe.isStarterFeeding(recipe)
            isStarter[recipe.objectID] = starter
            return !starter
        }
    }

    private var filteredBakeHistories: [BakeHistory] {
        let bakeHistories = bakedHistories

        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            // No filter text, so return all recipes (skip any history without a recipe)
            return bakeHistories.filter { b in
                guard let recipe = b.recipe else { return false }
                return recipe.rating >= rating
            }
        }
        else {
            // Filter by the search term and return
            // a subset of recipes which contain the search term in the name
            if nameOrTag == 1 {
                return bakeHistories.filter { b in
                    guard let recipe = b.recipe else { return false }
                    return recipe.name.contains(filterBy)
                }
            }
            else {
                return bakeHistories.filter { b in
                    guard let recipe = b.recipe else { return false }
                    return recipe.tags.contains(filterBy)
                }
            }
        }
    }

    /// The filtered history summed up per recipe, for the hit list and the
    /// photo cloud, with the recipe objects to open from them.
    private var talliedRecipes: (recipes: [BakeHistoryTally.Recipe], byID: [NSManagedObjectID: Recipe]) {
        var byID: [NSManagedObjectID: Recipe] = [:]
        let entries = filteredBakeHistories.compactMap { history -> BakeHistoryTally.Entry? in
            guard let recipe = history.recipe else { return nil }
            byID[recipe.objectID] = recipe
            return BakeHistoryTally.Entry(recipeID: recipe.objectID, recipeName: recipe.name, rating: recipe.rating,
                                          date: history.date, photos: history.images ?? [])
        }
        return (BakeHistoryTally.recipes(from: entries), byID)
    }
    
    // 90 pt, not 76: a French or English date ("04/10/2026") did not fit
    // and wrapped inside its year.
    var gridItemLayout = [
        GridItem(scaledColumnSize(90), alignment: .leading),
        GridItem(.flexible(minimum: 80), alignment: .leading),
        GridItem(.flexible(minimum: 80), alignment: .leading)
    ]
    var gridItemLayoutImages = [GridItem(scaledColumnSize(54), alignment: .leading), GridItem(scaledColumnSize(54), alignment: .leading)]

    /// Tiles of at least 160 pt: two across on an iPhone, more on an iPad.
    ///
    /// One per row at the accessibility sizes: five rating stars alone are
    /// then wider than half an iPhone, so two tiles side by side pushed the
    /// grid 14 pt past both screen edges.
    private var galleryColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 12, alignment: .top)]
        }
        return [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]
    }
    
    var dateFormat:DateFormat = DateFormat()
    
    @State private var confirmationShown = false
    
    var body: some View {
        
        VStack(spacing: 0) {
            layoutPicker

            Group {
                if filteredBakeHistories.isEmpty {
                    emptyState
                } else {
                    switch layout {
                    case .list:    list
                    case .gallery: gallery
                    case .hitList: hitList
                    case .cloud:   cloud
                    }
                }
            }
        }
        .warmBackground()
        .navigationTitle("Backhistorie")
        .searchable(text: $filterBy, prompt: "Rezept suchen")
        .searchScopes($nameOrTag) {
            Text("Name").tag(1)
            Text("Tags").tag(2)
        }
        .autocorrectionDisabled()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Mindestbewertung", selection: $rating) {
                        Text("Alle Bewertungen").tag(0)
                        ForEach(1...5, id: \.self) { stars in
                            Text("\(stars) Sterne und mehr").tag(stars)
                        }
                    }
                } label: {
                    Label("Nach Bewertung filtern",
                          systemImage: rating > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    /// The four views as a segmented control under the title: icons, with
    /// the names for VoiceOver.
    private var layoutPicker: some View {
        Picker("Darstellung", selection: Binding(
            get: { layout },
            set: { layoutRawValue = $0.rawValue }
        )) {
            ForEach(BakeHistoryLayout.allCases) { layout in
                Image(systemName: layout.systemImage)
                    .accessibilityLabel(layout.title)
                    .tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Empty

    /// Without any history the screen says where entries come from and leads
    /// there; with a filter that matches nothing it says so instead.
    @ViewBuilder
    private var emptyState: some View {
        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rating == 0 {
            ContentUnavailableView {
                Label("Noch keine Backhistorie", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Jeder Backvorgang, für den Du Erinnerungen setzt, landet hier – mit Datum, Kommentar und Fotos.")
            } actions: {
                NavigationLink("Eigene Rezepte öffnen") {
                    RecipeListView()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentTop)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Keine passenden Backvorgänge",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Passe Suche, Tags oder Bewertung an.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Gallery

    /// The photos are the most personal thing the app holds; here they lead.
    private var gallery: some View {
        ScrollView {
            LazyVGrid(columns: galleryColumns, spacing: 12) {
                ForEach(filteredBakeHistories, id: \.self) { bakeHistory in
                    NavigationLink {
                        BakeHistoryUpdateFormView(recipeName: bakeHistory.recipe?.name ?? "", bakeHistory: bakeHistory)
                            .environment(\.managedObjectContext, self.viewContext)
                    } label: {
                        galleryTile(bakeHistory)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func galleryTile(_ bakeHistory: BakeHistory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                // A square that takes whatever width the column offers: the
                // picture is only an overlay, so its own pixel size never
                // reaches the layout. Sizing the image itself made every
                // tile 232 pt wide and the grid wider than the screen.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let data = bakeHistory.images?.first, let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else if let recipeImage = bakeHistory.recipe.flatMap({ UIImage(data: $0.image) }) {
                            // No photo of this bake yet: the recipe's own
                            // picture keeps the tile from being an empty box.
                            Image(uiImage: recipeImage)
                                .resizable()
                                .scaledToFill()
                                .opacity(0.6)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundColor(Theme.subtitle)
                        }
                    }
                    .background(Theme.accentText.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // Otherwise the overlaid picture's full size leaks into
                    // the tap area and the accessibility frame.
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Several photos: say so.
                if let count = bakeHistory.images?.count, count > 1 {
                    Label("\(count)", systemImage: "photo.on.rectangle")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(8)
                        .accessibilityLabel("\(count) Fotos")
                }
            }

            // Everything below the picture must be able to shrink to the
            // column: a vertical ScrollView adopts its content's minimum
            // width, and date and five stars side by side wanted 195 pt
            // where a column on an iPhone has 179 — which pushed the whole
            // grid past both screen edges.
            Text(bakeHistory.recipe?.name ?? "")
                .font(Theme.brandFont(15))
                .foregroundColor(Theme.cardTitle)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(dateFormat.calculateDate(dT: bakeHistory.date))
                .font(Theme.bodyFont(13))
                .foregroundColor(Theme.subtitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            RatingStarsView(rating: bakeHistory.recipe?.rating ?? 0, label: "")
                .font(.caption2)

            BakeHistoryFactsLineView(facts: bakeHistory.facts)
                .font(Theme.bodyFont(13))
                .foregroundColor(Theme.subtitle)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !bakeHistory.comment.isEmpty {
                Text(bakeHistory.comment)
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {

        // The column titles only make sense above columns; the stacked rows
        // at the accessibility sizes carry their own labels.
        if !dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: gridItemLayout, spacing: 6) {

                Text("Datum")
                Text("Rezept")
                Text("Kommentar")
                Text(verbatim: "")
                Text(verbatim: "")
                Text(verbatim: "")
            }
            .padding(.horizontal, 16)
            .font(Theme.brandFont(18))
        }

        List {
            
            ForEach(filteredBakeHistories, id: \.self) { bakeHistory in
                
                NavigationLink(
                    destination: BakeHistoryUpdateFormView(recipeName: bakeHistory.recipe?.name ?? "", bakeHistory: bakeHistory)
                        .environment(\.managedObjectContext, self.viewContext),
                    label: {
                        
                        VStack {
                            if dynamicTypeSize.isAccessibilitySize {
                                // Three columns pushed "Kommentar" off the
                                // screen and cut the recipe name at the
                                // chevron; stacked, everything is read in
                                // full.
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dateFormat.calculateDate(dT: bakeHistory.date))
                                        .font(Theme.brandFont(16))
                                        .foregroundColor(Theme.subtitle)
                                    Text(bakeHistory.recipe?.name ?? "")
                                        .font(Theme.brandFont(16))
                                        .fixedSize(horizontal: false, vertical: true)
                                    BakeHistoryFactsLineView(facts: bakeHistory.facts)
                                        .font(Theme.bodyFont(14))
                                        .foregroundColor(Theme.subtitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !bakeHistory.comment.isEmpty {
                                        Text(bakeHistory.comment)
                                            .font(Theme.bodyFont(16))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                LazyVGrid(columns: gridItemLayout, spacing: 6) {

                                    Text(dateFormat.calculateDate(dT: bakeHistory.date))
                                        .font(Theme.brandFont(16))
                                    Text(bakeHistory.recipe?.name ?? "")
                                        .font(Theme.brandFont(16))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bakeHistory.comment)
                                            .font(Theme.bodyFont(16))
                                        BakeHistoryFactsLineView(facts: bakeHistory.facts)
                                            .font(Theme.bodyFont(13))
                                            .foregroundColor(Theme.subtitle)
                                    }
                                }
                            }
                            HStack {
                                
                                if let images = bakeHistory.images, !images.isEmpty {
                                    
                                    // MARK: History Images
                                    ForEach(images, id: \.self) { image in
                                        
                                        NavigationLink(
                                            destination: ShowBigImagesView(images: images, index: 0)
                                        )
                                        {
                                            let i = UIImage(data: image) ?? UIImage()
                                            Image(uiImage: i)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 50, height: 50, alignment: .center)
                                                .clipped()
                                                .cornerRadius(5)
                                        }
                                        // The photo is the link's only content.
                                        .accessibilityLabel("Backfoto anzeigen")
                                    }
                                }
                                else if let recipeImage = bakeHistory.recipe.flatMap({ UIImage(data: $0.image) }) {
                                    // No photo of this bake yet: the recipe's own
                                    // picture stands in, dimmed, as on the gallery tile.
                                    Image(uiImage: recipeImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50, alignment: .center)
                                        .clipped()
                                        .cornerRadius(5)
                                        .opacity(0.6)
                                        .accessibilityHidden(true)
                                }
                                else {
                                    // A small glyph in a tinted box the size of a
                                    // photo, like the gallery tile — not the symbol
                                    // stretched to fill the whole 50 pt.
                                    Image(systemName: "photo")
                                        .font(.system(size: 20))
                                        .foregroundColor(Theme.subtitle)
                                        .frame(width: 50, height: 50, alignment: .center)
                                        .background(Theme.accentText.opacity(0.12))
                                        .cornerRadius(5)
                                        // Placeholder for "no photo": nothing to announce.
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    })
            }
            .onDelete { indexSet in
                guard let index = indexSet.first, filteredBakeHistories.indices.contains(index) else { return }
                let deleteBakeHistory = self.filteredBakeHistories[index]
                
                self.viewContext.delete(deleteBakeHistory)

                do {
                    try viewContext.save()
                }
                catch {
                    // handle the Core Data error
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

        }
        .listStyle(.plain)
        .clearScrollBackground()
        }
    }

    // MARK: - Hit list

    /// The recipes, most baked first — the classics at the top. Each row:
    /// the recipe's picture, its name, how often and when last, its rating,
    /// the newest photos, and the count large at the right. A tap opens the
    /// recipe.
    private var hitList: some View {
        let tally = talliedRecipes
        return List {
            ForEach(Array(tally.recipes.enumerated()), id: \.element.id) { index, summary in
                if let recipe = summary.id.base as? NSManagedObjectID, let recipe = tally.byID[recipe] {
                    NavigationLink {
                        TabsView(recipe: recipe)
                    } label: {
                        hitListRow(summary, rank: index + 1, recipe: recipe)
                    }
                } else {
                    hitListRow(summary, rank: index + 1, recipe: nil)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
        .clearScrollBackground()
    }

    private func hitListRow(_ summary: BakeHistoryTally.Recipe, rank: Int, recipe: Recipe?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(rank).")
                .font(Theme.brandFont(16))
                .foregroundColor(Theme.subtitle)
                .frame(minWidth: 26, alignment: .trailing)

            recipePicture(recipe, size: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.name)
                    .font(Theme.brandFont(16))
                    .foregroundColor(Theme.cardTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(summary.count)× gebacken · zuletzt \(summary.lastDate, format: .dateTime.day().month().year())")
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                RatingStarsView(rating: summary.rating, label: "")
                    .font(.caption2)
                if !summary.photos.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(summary.photos.prefix(4).enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipped()
                                    .cornerRadius(5)
                            }
                        }
                        if summary.photos.count > 4 {
                            Text(verbatim: "+\(summary.photos.count - 4)")
                                .font(Theme.bodyFont(12))
                                .foregroundColor(Theme.subtitle)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: "\(summary.count)")
                .font(Theme.brandFont(20))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.accent))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(summary.name), \(summary.count) Backvorgänge"))
    }

    // MARK: - Photo cloud

    /// One circle per recipe with its newest bake photo, as big as the
    /// recipe is often baked, the most baked in the middle and the others
    /// wound around it; the whole cloud scaled to fit the screen. A tap opens
    /// the recipe; the name stands under circles with room for it.
    private var cloud: some View {
        let tally = talliedRecipes
        let maxCount = tally.recipes.first?.count ?? 1
        let radii = tally.recipes.map {
            CirclePacking.radius(count: $0.count, maxCount: maxCount,
                                 minimum: CloudMetrics.minimumRadius, maximum: CloudMetrics.maximumRadius)
        }
        let packing = CirclePacking(radii: radii, spacing: CloudMetrics.spacing)

        return GeometryReader { geo in
            let available = CGSize(width: geo.size.width - 2 * CloudMetrics.inset,
                                   height: geo.size.height - 2 * CloudMetrics.inset)
            let scale = min(available.width / max(packing.bounds.width, 1),
                            available.height / max(packing.bounds.height, 1),
                            CloudMetrics.maximumScale)
            let origin = CGPoint(x: geo.size.width / 2 - packing.bounds.midX * scale,
                                 y: geo.size.height / 2 - packing.bounds.midY * scale)

            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(tally.recipes, packing.placements)), id: \.0.id) { summary, placement in
                    let diameter = placement.radius * 2 * scale
                    let recipe = (summary.id.base as? NSManagedObjectID).flatMap { tally.byID[$0] }
                    let bubble = cloudBubble(summary, recipe: recipe, diameter: diameter)
                        .position(x: origin.x + placement.center.x * scale,
                                  y: origin.y + placement.center.y * scale)
                    if let recipe {
                        NavigationLink {
                            TabsView(recipe: recipe)
                        } label: {
                            bubble
                        }
                        .buttonStyle(.plain)
                    } else {
                        bubble
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func cloudBubble(_ summary: BakeHistoryTally.Recipe, recipe: Recipe?, diameter: CGFloat) -> some View {
        let named = diameter >= CloudMetrics.namedFrom
        return ZStack {
            Group {
                if let data = summary.photos.first, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    recipePicture(recipe, size: diameter)
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())

            // The name inside the circle, on a dark band along its lower
            // edge, so no neighbour can cover it; a small circle names
            // itself in the detail and for VoiceOver.
            if named {
                VStack {
                    Spacer(minLength: 0)
                    Text(summary.name)
                        .font(Theme.brandFont(diameter >= 120 ? 13 : 11))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.45)))
                        .frame(maxWidth: diameter * 0.9)
                        .padding(.bottom, diameter * 0.12)
                }
                .frame(width: diameter, height: diameter)
            }

            // How often, at the upper edge of the circle.
            VStack {
                Text(verbatim: "\(summary.count)")
                    .font(Theme.brandFont(diameter >= 90 ? 14 : 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, diameter >= 90 ? 9 : 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent))
                    .padding(.top, diameter * 0.06)
                Spacer(minLength: 0)
            }
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(summary.name), \(summary.count) Backvorgänge"))
    }

    /// The recipe's own picture, or the photo glyph on a tinted square.
    @ViewBuilder
    private func recipePicture(_ recipe: Recipe?, size: CGFloat) -> some View {
        if let recipe, let image = UIImage(data: recipe.image) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
        } else {
            Image(systemName: "photo")
                .font(.system(size: size * 0.4))
                .foregroundColor(Theme.subtitle)
                .frame(width: size, height: size)
                .background(Theme.accentText.opacity(0.12))
        }
    }
}

/// The sizes of the photo cloud, to tune once seen on a device.
private enum CloudMetrics {
    /// The least and the most baked recipe's circle radius before scaling to the screen.
    static let minimumRadius: CGFloat = 34
    static let maximumRadius: CGFloat = 100
    static let spacing: CGFloat = 6
    static let inset: CGFloat = 24
    /// A few recipes must not blow up into one giant circle.
    static let maximumScale: CGFloat = 1.3
    /// From this diameter on the name stands in the circle.
    static let namedFrom: CGFloat = 64
}

// MARK: - Previews

/// Seven recipes baked between one and nine times, with coloured squares
/// for photos, in a store that lives only for the preview.
private enum BakeHistoryPreviewData {
    static func context() -> NSManagedObjectContext {
        let context = PersistenceController(inMemory: true).container.viewContext
        let recipes: [(String, Int, UIColor)] = [
            ("Roggenbrot", 9, .brown), ("Baguette", 5, .orange), ("Dinkelzopf", 4, .systemYellow),
            ("Kartoffelbrot mit Saaten", 3, .systemOrange), ("Ciabatta", 2, .systemTeal),
            ("Brioche", 1, .systemPink), ("Vollkornbrot", 1, .darkGray),
        ]
        for (index, (name, count, color)) in recipes.enumerated() {
            let recipe = Recipe(context: context)
            recipe.id = UUID()
            recipe.name = name
            recipe.image = Data()
            recipe.tags = []
            recipe.summary = ""
            recipe.rating = 3 + index % 3
            recipe.bakeHistoryFlag = true
            for bake in 0..<count {
                let history = BakeHistory(context: context)
                history.id = UUID()
                history.date = Date().addingTimeInterval(TimeInterval(-(bake * 9 + index) * 86_400))
                history.comment = ""
                history.images = [square(color, shade: CGFloat(bake) / CGFloat(max(count, 2)))]
                recipe.addToBakeHistories(history)
            }
        }
        try? context.save()
        return context
    }

    private static func square(_ color: UIColor, shade: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
        return renderer.image { context in
            color.withAlphaComponent(1 - shade * 0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }.pngData() ?? Data()
    }
}

#Preview("Fotowolke") {
    UserDefaults.standard.set(BakeHistoryLayout.cloud.rawValue, forKey: AppSettingsKeys.bakeHistoryLayout)
    return NavigationStack {
        BakeHistoriesListView()
            .environment(\.managedObjectContext, BakeHistoryPreviewData.context())
    }
}

#Preview("Hit-Liste") {
    UserDefaults.standard.set(BakeHistoryLayout.hitList.rawValue, forKey: AppSettingsKeys.bakeHistoryLayout)
    return NavigationStack {
        BakeHistoriesListView()
            .environment(\.managedObjectContext, BakeHistoryPreviewData.context())
    }
}
