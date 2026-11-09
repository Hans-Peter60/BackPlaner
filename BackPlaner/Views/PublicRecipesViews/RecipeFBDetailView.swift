//
//  RecipeFBDetailView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 23.11.21.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct RecipeFBDetailView: View {

    var recipeFB:RecipeFB

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model: RecipeModel

    // Saving a public recipe onto the device gave no feedback at all, so it
    // was impossible to tell whether the tap had done anything.
    @State private var showSavedConfirmation = false
    @State private var saveErrorMessage: String?

    @State private var totalWeight = 0.0
    /// Owned by PublicRecipePageView and shared with its sheets, so the
    /// factor chosen here is the one a plan and the shopping list use.
    @Binding var selectedServingSize: Int
    /// A target dough weight in grams; overrides the serving-size factor.
    @Binding var targetWeight: Int?

    /// What the page's buttons open (sheets of PublicRecipePageView).
    var onPlan: () -> Void = {}
    var onShoppingList: () -> Void = {}

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
        ServingScale.factor(servingSize: selectedServingSize, targetWeight: targetWeight, baseWeight: recipeFB.totalWeight)
    }

    private func openPendingCopy() {
        guard let pendingCopy else { return }
        self.pendingCopy = nil
        openedCopy = AdjustedRecipeCopy(id: pendingCopy)
    }
    // Admin/owner moderation: confirm before deleting any public recipe.
    @State private var showAdminDeleteConfirm = false
    // Error message shown when a delete fails (e.g. Firestore rules deny it), so
    // the screen no longer silently dismisses as if it had worked.
    @State private var deleteErrorMessage: String?
    // Error message shown when releasing a reported recipe fails.
    @State private var releaseErrorMessage: String?

    var gridItemLayout = [GridItem(scaledColumnSize(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(80), alignment: .trailing)]

    // At the accessibility text sizes the step table becomes a stacked list
    // and the "Verarbeitungsschritte" header no longer shares its row.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        
        GeometryReader { fullView in
            
            ScrollView(.vertical, showsIndicators: false) {
                
                VStack (alignment: .leading) {
                                    
                    HStack {
                        
                        // MARK: Recipe image
                        NavigationLink(
                            destination: ShowBigImageView(image: (GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()).jpegData(compressionQuality: 1.0) ?? Data() )
                        )
                        {
                            Image(uiImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                                .cornerRadius(5)
                        }
                        // The image is the link's only content, so without this the
                        // link would be announced with no name at all.
                        .accessibilityLabel("Rezeptbild vergrößern")
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(recipeFB.name)
                                .font(Theme.brandFont(18))
                                .foregroundColor(Theme.title)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            // MARK: Recipe summary
                            Text(recipeFB.summary)
                                .font(Theme.bodyFont(15))
                        }
                            .padding(.leading, 4)
                    }
                    
                    // MARK: Serving size or target dough weight
                    ServingScaleControl(selectedServingSize: $selectedServingSize,
                                        targetWeight: $targetWeight,
                                        baseWeight: recipeFB.totalWeight,
                                        suggestedDoughType: DoughWeightFromTin.doughType(for: DoughComposition.components(of: recipeFB)))

                    HStack {
                        Text("Gewicht: \(Int((recipeFB.totalWeight * servingScale).rounded()), format: .number) g")
                            .font(Theme.bodyFont(15))

                        Spacer()
                        
                        // MARK: Recipe urlLink
                        if let url = URL(string: recipeFB.urlLink) {
                            Link("Link zum Rezept", destination: url)
                                .padding(.top, 2)
                                .padding(.leading)
                                .font(Theme.brandFont(15))
                        }

                        // MARK: Share as PDF, at the serving size shown (Pro)
                        ProGate(.pdfExport) {
                            FileShareLink(
                                item: RecipePDFExport(data: RecipePrintData(
                                    recipeFB: recipeFB,
                                    image: GlobalVariables.recipesImage[recipeFB.id ?? ""],
                                    scale: servingScale
                                )),
                                preview: SharePreview(recipeFB.name, image: Image(uiImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()))
                            ) {
                                Label("Rezept teilen", systemImage: "square.and.arrow.up")
                                    .font(Theme.brandFont(15))
                            }
                        } label: {
                            Label("Rezept teilen", systemImage: "square.and.arrow.up")
                                .font(Theme.brandFont(15))
                        }
                        .padding(.leading)
                    }

                    // MARK: Dough yield and hydration over all components
                    DoughYieldView(result: DoughComposition.compute(DoughComposition.components(of: recipeFB)))

                    // MARK: Actions
                    // Planning at the amount chosen above, the shopping
                    // list, and the recipe as one's own — each a sheet or a
                    // step from this page.
                    // The two short buttons share a line; the long "Als
                    // eigenes Rezept speichern" gets a line of its own on a
                    // phone, all three sit in a row where they fit.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { planButton; shoppingListButton; saveAsOwnButton }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) { planButton; shoppingListButton }
                            saveAsOwnButton
                        }
                    }
                    .padding(.vertical, 4)

                    TotalIngredientsView(components: ComponentColumn.columns(of: recipeFB.components),
                                         scale: servingScale)

                    // MARK: Components
                    // One snapshot for the card and the substitution sheet, so a
                    // tapped line's index means the same ingredient in both.
                    let recipeSnapshot = RecipeExportData(recipeFB: recipeFB,
                                                          image: GlobalVariables.recipesImage[recipeFB.id ?? ""])
                    ComponentColumnsView(components: ComponentColumn.columns(of: recipeSnapshot),
                                         scale: servingScale,
                                         onFlourTap: { componentIndex, ingredientIndex in
                                             flourSubstitution = FlourSubstitutionRequest(
                                                 recipe: recipeSnapshot,
                                                 componentIndex: componentIndex,
                                                 ingredientIndex: ingredientIndex,
                                                 scale: servingScale,
                                                 onCopyCreated: { pendingCopy = $0 })
                                         },
                                         onStarterTap: { componentIndex, ingredientIndex in
                                             starterAdjustment = StarterYieldRequest(
                                                 recipe: recipeSnapshot,
                                                 componentIndex: componentIndex,
                                                 ingredientIndex: ingredientIndex,
                                                 scale: servingScale,
                                                 onCopyCreated: { pendingCopy = $0 })
                                         })

                    Divider()
                    
                    // MARK: Instructions
                    VStack(alignment: .leading) {
                        // The heading and the total time share a line where
                        // both fit whole; otherwise the time goes underneath,
                        // instead of wrapping to "Bearbeitungsdauer: / 1h 5m"
                        // beside the heading on a phone.
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

                        let sortedInstructions = recipeFB.instructions.sorted(by: { $0.step < $1.step })

                        if dynamicTypeSize.isAccessibilitySize {
                            InstructionStepsStackedView(rows: sortedInstructions.enumerated().map { index, i in
                                InstructionStepRow(id: index,
                                                   step: Rational.decimalPlace(i.step, 10),
                                                   instruction: i.instruction,
                                                   duration: Rational.displayHoursMinutes(i.duration))
                            })
                            .font(Theme.bodyFont(16))
                            .padding([.bottom, .top], 5)
                        } else {
                            LazyVGrid(columns: gridItemLayout, spacing: 5) {
                                Text("Nr.").bold()
                                Text("Beschreibung").bold()
                                Text("Dauer").bold()

                                ForEach(sortedInstructions) { i in

                                    let step = Rational.decimalPlace(i.step, 10)
                                    Text(step)
                                    Text(i.instruction)
                                    Text(Rational.displayHoursMinutes(i.duration))
                                }
                            }
                            .font(Theme.bodyFont(16))
                            .padding([.bottom, .top], 5)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    // MARK: Admin/owner moderation — review reported recipes and
                    // delete ANY public recipe.
                    if modelFB.isAdmin {
                        if recipeFB.hidden {
                            Text("Dieses Rezept wurde gemeldet und ist für alle anderen Nutzer ausgeblendet.")
                                .font(.footnote)
                                .foregroundColor(Theme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top)

                            IconActionButton(systemImage: "eye", style: .primary, accessibilityLabel: "Rezept wieder freigeben", title: "Rezept wieder freigeben", controlSize: .regular) {
                                modelFB.setRecipeHidden(recipeFB, hidden: false) { result in
                                    if case .failure(let error) = result {
                                        releaseErrorMessage = error.localizedDescription
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Rezept löschen (Admin)", title: "Rezept löschen (Admin)", controlSize: .regular) {
                            showAdminDeleteConfirm = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top)
                    }
                }
                .padding()
                // See InstructionsFBView: a vertical ScrollView adopts its
                // content's ideal width, so a single long label stretches the
                // screen past both edges until the width is pinned down.
                .frame(width: fullView.size.width, alignment: .leading)
            }
            .warmBackground()
            .navigationTitle(Text(recipeFB.name))
            .alert("Rezept wurde gespeichert", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Das Rezept liegt jetzt unter „Eigene Rezepte“ auf diesem Gerät und wird über Deine iCloud gesichert. Dort kannst Du es bearbeiten, ohne das öffentliche Rezept zu verändern.")
            }
            .alert("Speichern fehlgeschlagen", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .sheet(item: $flourSubstitution, onDismiss: openPendingCopy) { request in
                FlourSubstitutionSheet(request: request)
            }
            .sheet(item: $starterAdjustment, onDismiss: openPendingCopy) { request in
                StarterYieldSheet(request: request)
            }
            // The copy is one of the user's own recipes; it opens on top of
            // the public one it was made from.
            .navigationDestination(item: $openedCopy) { copy in
                if let recipe = try? viewContext.existingObject(with: copy.id) as? Recipe {
                    RecipePageView(recipe: recipe)
                }
            }
            .confirmationDialog("Öffentliches Rezept löschen?", isPresented: $showAdminDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    modelFB.deleteRecipeAsAdmin(recipeFB) { result in
                        switch result {
                        case .success:
                            dismiss()
                        case .failure(let error):
                            deleteErrorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Dieses Rezept wird als Administrator endgültig aus der öffentlichen Datenbank entfernt.")
            }
            .alert("Löschen fehlgeschlagen", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            .alert("Freigeben fehlgeschlagen", isPresented: Binding(
                get: { releaseErrorMessage != nil },
                set: { if !$0 { releaseErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { releaseErrorMessage = nil }
            } message: {
                Text(releaseErrorMessage ?? "")
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
        Text("Bearbeitungsdauer: \(Rational.displayHoursMinutes(recipeFB.prepTime))")
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

    private var saveAsOwnButton: some View {
        IconActionButton(systemImage: "square.and.arrow.down", style: .primary, accessibilityLabel: "Als eigenes Rezept speichern",
                         title: "Als eigenes Rezept speichern", controlSize: .regular) {
            do {
                _ = try model.uploadRecipeIntoCoreData(recipeId: nil, recipeFB: recipeFB, context: viewContext,
                                                       recipeImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                showSavedConfirmation = true
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }
        .accessibilityIdentifier("recipe.saveAsOwn")
    }
}
