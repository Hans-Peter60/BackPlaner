//
//  RecipeDetailView.swift
//  PetersBackPlaner App
//
//  Created by Hans-Peter Müller on 2021-01-14.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct RecipeDetailView: View {

    @Environment(\.managedObjectContext) private var viewContext

    /// Observed, so an adjustment written into this recipe in place shows
    /// up without leaving the screen.
    @ObservedObject var recipe: Recipe

    // The description column's minimum stays well under a phone's width
    // less the two fixed columns, the card and the page padding: at 200 pt
    // the table ran past the right edge and cut "Dauer" to "Daue".
    // Number and duration sit at the top of their row, level with the first
    // line of a description that runs over several lines.
    var gridItemLayout = [GridItem(scaledColumnSize(40), alignment: .topLeading), GridItem(.flexible(minimum: 100), alignment: .topLeading), GridItem(scaledColumnSize(80), alignment: .topTrailing)]

    // At the accessibility text sizes the step table becomes a stacked list
    // and the "Verarbeitungsschritte" header no longer shares its row.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Owned by RecipePageView and shared with its sheets, so the factor
    /// chosen here is the one a plan and the shopping list use.
    @Binding var selectedServingSize: Int
    /// A target dough weight in grams; overrides the serving-size factor.
    @Binding var targetWeight: Int?

    /// What the page's buttons open (sheets of RecipePageView): the plan,
    /// the shopping list, a bake entry, or a starter's feeding diary.
    var onPlan: () -> Void = {}
    var onShoppingList: () -> Void = {}
    var onBakeEntry: () -> Void = {}
    var onFeedingDiary: () -> Void = {}

    private let dateFormat = DateFormat()

    /// The flour line tapped for a substitution, while its sheet is up.
    @State private var flourSubstitution: FlourSubstitutionRequest?
    /// The starter line tapped for a TA adjustment, while its sheet is up.
    @State private var starterAdjustment: StarterYieldRequest?
    /// The copy an adjustment sheet wrote, waiting for the sheet to close.
    /// Pushing from inside the sheet's callback would race its dismissal.
    @State private var pendingCopy: NSManagedObjectID?
    /// The copy being opened on top of this recipe.
    @State private var openedCopy: AdjustedRecipeCopy?

    /// 1.0 is the recipe as stored.
    private var servingScale: Double {
        ServingScale.factor(servingSize: selectedServingSize, targetWeight: targetWeight, baseWeight: recipe.totalWeight)
    }

    /// An adjusted copy takes further adjustments itself; any other recipe
    /// gets a copy.
    private var adjustmentTarget: NSManagedObjectID? {
        recipe.adjustedOn != nil ? recipe.objectID : nil
    }

    private func openPendingCopy() {
        guard let pendingCopy else { return }
        self.pendingCopy = nil
        openedCopy = AdjustedRecipeCopy(id: pendingCopy)
    }

    var body: some View {

        // Reads the width available so the content below can be pinned to it —
        // see InstructionsFBView for why a vertical ScrollView otherwise grows
        // past both screen edges at the large text sizes.
        GeometryReader { fullView in

        ScrollView {

            VStack (alignment: .leading) {
                
                // The other three recipe screens use this for the same header;
                // a plain HStack left the image's 100 pt minimum beside a row of
                // five rating stars that grows to 375 pt at the largest text
                // size, which together overran a 402 pt screen by 183 pt.
                PortraitAdaptiveStack(spacing: 12) {
                    // MARK: Recipe Image
                    NavigationLink(
                        destination: ShowBigImageView(image: recipe.image)
                    )
                    {
                        let image = UIImage(data: recipe.image) ?? UIImage()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                            .cornerRadius(5)
                    }
                    // The image is the link's only content, so without this the
                    // link would be announced with no name at all.
                    .accessibilityLabel("Rezeptbild vergrößern")

                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipe.name)
                            .font(Theme.brandFont(18))
                            .foregroundColor(Theme.title)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bewertung")
                                .font(Theme.brandFont(16))
                                .foregroundColor(Theme.title)

                            RatingStarsView(rating: recipe.rating, label: "")
                                .font(.title3)
                        }
                    }
                    .padding(.leading, 4)

                    Spacer(minLength: 8)
                }

                
                // MARK: Recipe summary
                Text(recipe.summary)
                    .padding(.top, 2)
                    .font(Theme.bodyFont(15))

                // MARK: Where a variant came from, and what it changes
                if let origin = recipe.origin, !origin.isDeleted {
                    VariantOriginRow(recipe: recipe, origin: origin)
                }
                    
                // MARK: Serving size or target dough weight
                ServingScaleControl(selectedServingSize: $selectedServingSize,
                                    targetWeight: $targetWeight,
                                    baseWeight: recipe.totalWeight,
                                    suggestedDoughType: DoughWeightFromTin.doughType(for: DoughComposition.components(of: recipe)))

                HStack {
                    Text("Gewicht: \(Int((recipe.totalWeight * servingScale).rounded()), format: .number) g")
                            .font(Theme.bodyFont(15))

                    Spacer()

                    // MARK: Recipe urlLink
                    if let url = URL(string: recipe.urlLink ?? "") {
                        Link("Link zum Rezept", destination: url)
                            .padding(.top, 2)
                            .padding(.leading)
                            .font(Theme.brandFont(15))
                    }

                    // MARK: Share as PDF, at the serving size shown (Pro)
                    ProGate(.pdfExport) {
                        FileShareLink(
                            item: RecipePDFExport(data: RecipePrintData(recipe: recipe, scale: servingScale)),
                            preview: SharePreview(recipe.name, image: Image(uiImage: UIImage(data: recipe.image) ?? UIImage()))
                        ) {
                            Label("Rezept teilen", systemImage: "square.and.arrow.up")
                                .font(Theme.brandFont(15))
                        }
                    } label: {
                        Label("Rezept teilen", systemImage: "square.and.arrow.up")
                            .font(Theme.brandFont(15))
                    }
                    .padding(.leading)

                    // MARK: Export as a re-importable file (hand to someone else) (Pro)
                    ProGate(.recipeSharing) {
                        FileShareLink(
                            item: RecipeFileExport(recipe: recipe),
                            preview: SharePreview(recipe.name, image: Image(uiImage: UIImage(data: recipe.image) ?? UIImage()))
                        ) {
                            Label("Rezept exportieren", systemImage: "doc.badge.arrow.up")
                                .font(Theme.brandFont(15))
                        }
                    } label: {
                        Label("Rezept exportieren", systemImage: "doc.badge.arrow.up")
                            .font(Theme.brandFont(15))
                    }
                    .padding(.leading)
                }

                // MARK: Dough yield and hydration over all components, and
                // for a recipe on a rhythm the date it comes round next.
                HStack(alignment: .firstTextBaseline) {
                    DoughYieldView(result: DoughComposition.compute(DoughComposition.components(of: recipe)))

                    if recipe.recurrenceIntervalDays > 0, Entitlements.shared.isUnlocked(.recurringPlans) {
                        Spacer(minLength: 12)
                        // Wraps on a narrow screen rather than pushing the
                        // dough yield off its line.
                        // When the first step is next due: the feeding of a
                        // starter, the first mixing of a bread.
                        NextFeedingView(date: RecurringBakePlanner.nextStart(for: recipe),
                                        isStarter: StarterRecipe.isStarterFeeding(recipe))
                            .multilineTextAlignment(.trailing)
                    }
                }

                // MARK: Actions
                // Planning at the amount chosen above, the shopping list,
                // and the bake history or the starter's diary — each a
                // sheet over this page. A starter is fed, not baked.
                // The two short buttons share a line; the long third one
                // ("Backvorgang eintragen") gets a line of its own on a
                // phone, all three sit in a row where they fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { planButton; shoppingListButton; historyButton }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) { planButton; shoppingListButton }
                        historyButton
                    }
                }
                .padding(.vertical, 4)

                // MARK: Pantry
                // What of this is in the house, at the amount shown (Pro).
                if Entitlements.shared.isUnlocked(.pantry) {
                    PantryCheckCard(recipe: RecipeExportData(recipe: recipe, includingImage: false), scale: servingScale)
                }

                TotalIngredientsView(components: ComponentColumn.columns(of: recipe.componentsArray),
                                     scale: servingScale)

                // MARK: Components
                // One snapshot for the card and the substitution sheet, so a
                // tapped line's index means the same ingredient in both.
                let recipeSnapshot = RecipeExportData(recipe: recipe)
                ComponentColumnsView(components: ComponentColumn.columns(of: recipeSnapshot),
                                     scale: servingScale,
                                     onFlourTap: { componentIndex, ingredientIndex in
                                         flourSubstitution = FlourSubstitutionRequest(
                                             recipe: recipeSnapshot,
                                             componentIndex: componentIndex,
                                             ingredientIndex: ingredientIndex,
                                             scale: servingScale,
                                             updateTarget: adjustmentTarget,
                                             origin: recipe.objectID,
                                             onCopyCreated: { pendingCopy = $0 })
                                     },
                                     onStarterTap: { componentIndex, ingredientIndex in
                                         starterAdjustment = StarterYieldRequest(
                                             recipe: recipeSnapshot,
                                             componentIndex: componentIndex,
                                             ingredientIndex: ingredientIndex,
                                             scale: servingScale,
                                             updateTarget: adjustmentTarget,
                                             origin: recipe.objectID,
                                             onCopyCreated: { pendingCopy = $0 })
                                     })

                // MARK: Last time
                // How the last bake of this recipe went, right where the
                // next one is planned from. Only a bake that already
                // happened: setting reminders creates an entry dated at the
                // planned end, which has nothing to say yet.
                if !StarterRecipe.isStarterFeeding(recipe), let lastBake = recipe.lastCompletedBakeHistory() {
                    LastBakeCardView(bakeHistory: lastBake, recipeName: recipe.name)
                }

                // MARK: Instructions
                VStack(alignment: .leading) {
                    // The heading and the total time share a line where both
                    // fit whole; otherwise the time goes underneath, instead
                    // of wrapping to "Bearbeitungsdauer: / 9h 17m" beside the
                    // heading on a phone.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            instructionsHeader
                            Spacer()
                            processingTimeText.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            instructionsHeader
                            processingTimeText
                        }
                    }

                    if dynamicTypeSize.isAccessibilitySize {
                        InstructionStepsStackedView(rows: recipe.instructionsArray.enumerated().map { index, i in
                            InstructionStepRow(id: index,
                                               step: Rational.decimalPlace(i.step, 10),
                                               // The oven's stored settings follow the text.
                                               instruction: [i.instruction, i.oven?.summary()].compactMap { $0 }.joined(separator: "\n"),
                                               duration: i.planDurationWindow.map {
                                                   "\(Rational.displayHoursMinutes(i.duration)) (\(DurationWindow.text($0)))"
                                               } ?? Rational.displayHoursMinutes(i.duration))
                        })
                        .font(Theme.bodyFont(16))
                        .padding([.bottom, .top], 5)
                    } else {
                        LazyVGrid(columns: gridItemLayout, spacing: 5) {
                            Text("Nr.").bold()
                            Text("Beschreibung").bold()
                            Text("Dauer").bold()

                            ForEach(recipe.instructionsArray, id: \.self) { i in

                                let step = Rational.decimalPlace(i.step, 10)
                                Text(step)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(i.instruction)
                                    // The oven's stored settings, when the step has any.
                                    if let oven = i.oven?.summary() {
                                        Text(oven)
                                            .font(Theme.bodyFont(11))
                                            .foregroundColor(Theme.subtitle)
                                    }
                                }
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text(Rational.displayHoursMinutes(i.duration))
                                    // The window the plan may use: stored, or
                                    // read from the wording ("12–18 Stunden").
                                    if let window = i.planDurationWindow {
                                        Text(DurationWindow.text(window))
                                            .font(Theme.bodyFont(11))
                                            .foregroundColor(Theme.subtitle)
                                    }
                                }
                            }
                        }
                        .font(Theme.bodyFont(16))
                        .padding([.bottom, .top], 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                // MARK: Earlier bakes
                // Every bake of this recipe, newest first: the date, the
                // recorded facts in one line, and the comment. An entry still
                // ahead is the one just planned and is marked as such.
                if !StarterRecipe.isStarterFeeding(recipe), !recipe.bakeHistoriesArray.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {

                        Text("Bisherige Backvorgänge")
                            .font(Theme.brandFont(16))
                            .foregroundColor(Theme.title)

                        ForEach(recipe.bakeHistoriesArray) { bakeHistory in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(dateFormat.calculateDate(dT: bakeHistory.date))
                                        .font(Theme.brandFont(15))
                                        .foregroundColor(Theme.cardTitle)
                                    if bakeHistory.date > Date() {
                                        Text("geplant")
                                            .font(Theme.bodyFont(13))
                                            .foregroundColor(Theme.subtitle)
                                    }
                                }

                                BakeHistoryFactsLineView(facts: bakeHistory.facts)
                                    .font(Theme.bodyFont(14))
                                    .foregroundColor(Theme.subtitle)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !BakeHistoryFacts.isPlaceholderComment(bakeHistory.comment) {
                                    Text(bakeHistory.comment)
                                        .font(Theme.bodyFont(15))
                                        .foregroundColor(Theme.cardTitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if !bakeHistory.hasNotes && bakeHistory.date <= Date() {
                                    Text("Noch nichts notiert")
                                        .font(Theme.bodyFont(14))
                                        .foregroundColor(Theme.subtitle)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }

                // MARK: Variants
                // The recipes made from this one, each with what it changes
                // and how it baked, so the results can be compared.
                VariantsCard(recipe: recipe)
            }
            .padding()
            .frame(width: fullView.size.width, alignment: .leading)
        }
        .warmBackground()
        .navigationTitle(recipe.name)
        .sheet(item: $flourSubstitution, onDismiss: openPendingCopy) { request in
            FlourSubstitutionSheet(request: request)
        }
        .sheet(item: $starterAdjustment, onDismiss: openPendingCopy) { request in
            StarterYieldSheet(request: request)
        }
        // The copy opens on top of the original, so the way back leads to
        // the recipe the adjustment started from.
        .navigationDestination(item: $openedCopy) { copy in
            if let recipe = try? viewContext.existingObject(with: copy.id) as? Recipe {
                RecipePageView(recipe: recipe)
            }
        }

        }
    }

    /// The two halves of the step table's header row; see the ViewThatFits
    /// in body for how they are arranged.
    private var instructionsHeader: some View {
        Text("Verarbeitungsschritte")
            .font(Theme.brandFont(16))
            .foregroundColor(Theme.title)
            .padding([.bottom, .top], 5)
    }

    private var processingTimeText: some View {
        Text("Bearbeitungsdauer: \(Rational.displayHoursMinutes(recipe.prepTime))")
            .font(Theme.bodyFont(16))
            .padding([.trailing], 5)
    }

    // The page's buttons. Stable identifiers for the UI tests.

    private var planButton: some View {
        IconActionButton(systemImage: "calendar", style: .primary, accessibilityLabel: "Planen",
                         title: "Planen", controlSize: .regular, action: onPlan)
            .accessibilityIdentifier("recipe.plan")
    }

    private var shoppingListButton: some View {
        IconActionButton(systemImage: "cart.badge.plus", style: .primary, accessibilityLabel: "Einkaufsliste",
                         title: "Einkaufsliste", controlSize: .regular, action: onShoppingList)
            .accessibilityIdentifier("recipe.shoppingList")
    }

    /// The bake history for a bread, the feeding diary for a starter.
    @ViewBuilder private var historyButton: some View {
        if StarterRecipe.isStarterFeeding(recipe) {
            IconActionButton(systemImage: "drop.degreesign", style: .primary, accessibilityLabel: "Anstellgut-Tagebuch",
                             title: "Anstellgut-Tagebuch", controlSize: .regular, action: onFeedingDiary)
                .accessibilityIdentifier("recipe.feedingDiary")
        } else {
            IconActionButton(systemImage: "rectangle.and.pencil.and.ellipsis", style: .primary,
                             accessibilityLabel: "Backvorgang eintragen", title: "Backvorgang eintragen",
                             controlSize: .regular, action: onBakeEntry)
                .accessibilityIdentifier("recipe.bakeEntry")
        }
    }
}
