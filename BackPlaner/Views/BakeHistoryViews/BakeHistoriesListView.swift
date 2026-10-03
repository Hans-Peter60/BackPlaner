//
//  BakeHistoriesHitListView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.02.22.
//

import SwiftUI
import CoreData

/// How the baking history is laid out: the table-like list, or a gallery of
/// photo tiles. Persisted, since whoever prefers the gallery prefers it
/// every time.
enum BakeHistoryLayout: String {
    case list
    case gallery
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
    
    private var filteredBakeHistories: [BakeHistory] {
        
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
        
        Group {
            if filteredBakeHistories.isEmpty {
                emptyState
            } else if layout == .gallery {
                gallery
            } else {
                list
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
                Button {
                    layoutRawValue = (layout == .list ? BakeHistoryLayout.gallery : .list).rawValue
                } label: {
                    Label(layout == .list ? "Als Galerie zeigen" : "Als Liste zeigen",
                          systemImage: layout == .list ? "square.grid.2x2" : "list.bullet")
                }
            }
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

    // MARK: - Empty

    /// Without any history the screen says where entries come from and leads
    /// there; with a filter that matches nothing it says so instead.
    @ViewBuilder
    private var emptyState: some View {
        if filterBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rating == 0 {
            ContentUnavailableView {
                Label("Noch keine Backhistorie", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Jeder Backvorgang, für den Du Reminder setzt, landet hier – mit Datum, Kommentar und Fotos.")
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
                                    Text(bakeHistory.comment)
                                        .font(Theme.bodyFont(16))
                                }
                            }
                            HStack {
                                
                                if bakeHistory.images != nil {
                                    
                                    // MARK: History Images
                                    ForEach(bakeHistory.images!, id: \.self) { image in
                                        
                                        NavigationLink(
                                            destination: ShowBigImagesView(images: bakeHistory.images!, index: 0)
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
                                else {
                                    Image(systemName: "photo")
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 50, height: 50, alignment: .center)
                                        .clipped()
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
}
