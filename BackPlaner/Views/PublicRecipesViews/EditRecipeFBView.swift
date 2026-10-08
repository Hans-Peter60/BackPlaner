//
//  EditRecipeFBView.swift
//  BackPlaner
//

import SwiftUI

/// Edits a recipe that lives in the recipe database: the author's own, or —
/// as an admin — any public one. The form works on a copy, and the recipe on
/// screen only changes once the save has gone through, so cancelling or a
/// failed save leaves everything as it was.
struct EditRecipeFBView: View {

    /// The recipe as shown on screen; it takes over the edited content on save.
    let recipeFB: RecipeFB
    /// Called after a successful save, before the sheet closes.
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var modelFB: RecipeFBModel

    @State private var draft: RecipeFB

    /// A replacement picture; nil while the stored one is kept.
    @State private var recipeImage: UIImage?
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary

    @State private var newTag = ""

    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    /// See AddRecipeView: room below the form while the keyboard is up, so
    /// the last rows can still be scrolled clear of it.
    @State private var keyboardIsUp = false
    private var keyboardRoom: CGFloat { keyboardIsUp ? 240 : 0 }

    private let tagGridLayout = [GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(44), alignment: .trailing)]

    init(recipeFB: RecipeFB, onSaved: @escaping () -> Void) {
        self.recipeFB = recipeFB
        self.onSaved  = onSaved

        // Whatever language the screen was showing, the editor works on the
        // original text; the other languages are translated from it again.
        let copy   = recipeFB.editableCopy()
        let source = RecipeTranslator.sourceLanguageCode(for: copy)
        if copy.hasCachedTranslation(languageCode: source) {
            copy.showLocalization(languageCode: source)
        }
        _draft = State(initialValue: copy)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// The replacement picture if one was picked, otherwise the stored one.
    private var shownImage: UIImage {
        recipeImage ?? GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                form(scrollProxy: proxy)
            }
            .navigationTitle("Rezept bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView("Rezept wird gespeichert …")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Speichern fehlgeschlagen", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private func form(scrollProxy: ScrollViewProxy) -> some View {
        Form {
            Section {
                Image(uiImage: shownImage)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 50, idealWidth: 100, maxWidth: 150, minHeight: 50, idealHeight: 100, maxHeight: 150, alignment: .center)
                    .accessibilityLabel("Rezeptbild")

                HStack {
                    IconActionButton(systemImage: "photo.on.rectangle", style: .primary, accessibilityLabel: "Fotomediathek öffnen", title: "Fotomediathek", controlSize: .regular) {
                        selectedImageSource  = .photoLibrary
                        isShowingImagePicker = true
                    }

                    // Only where a camera exists (never on the Simulator).
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Spacer()

                        IconActionButton(systemImage: "camera", style: .primary, accessibilityLabel: "Kamera öffnen", title: "Kamera", controlSize: .regular) {
                            selectedImageSource  = .camera
                            isShowingImagePicker = true
                        }
                    }
                }
                .sheet(isPresented: $isShowingImagePicker) {
                    ImagePicker(selectedSource: selectedImageSource, recipeImage: $recipeImage)
                }
            } footer: {
                Text("Die Änderungen werden in der Rezept-Datenbank gespeichert. Vorhandene Übersetzungen werden danach neu erstellt.")
            }

            Section {
                AddMetaDataView(name:    $draft.name,
                                summary: $draft.summary,
                                urlLink: $draft.urlLink)

                tagsEditor
            }

            Section {
                AddComponentDataView(components: $draft.components)
            }

            Section {
                AddInstructionDataView(instructions: $draft.instructions, scrollProxy: scrollProxy)
            }
        }
        .font(Theme.bodyFont(15))
        .clearScrollBackground()
        .contentMargins(.bottom, keyboardRoom, for: .scrollContent)
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                keyboardIsUp = true
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                keyboardIsUp = false
            }
        }
        .warmBackground()
        // The number pads have no Return key, and in a Form neither a tap
        // beside the fields nor scrolling closes them; see AddRecipeView.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    /// Unlike the add form, an editor has to be able to take a tag away
    /// again, so the tags are listed one per row with a delete button.
    @ViewBuilder
    private var tagsEditor: some View {
        LazyVGrid(columns: tagGridLayout, spacing: 2) {
            TextField("Tags", text: $newTag)
                .textFieldStyle(.roundedBorder)

            IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Tag hinzufügen", controlSize: .regular) {
                let cleanedTag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedTag.isEmpty else { return }
                draft.tags.append(cleanedTag)
                newTag = ""
            }
        }
        .scrollsSidewaysAtLargeText()

        ForEach(draft.tags.indices, id: \.self) { index in
            LazyVGrid(columns: tagGridLayout, spacing: 2) {
                Text(draft.tags[index])
                    .font(Theme.bodyFont(15))

                IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Tag löschen", controlSize: .regular) {
                    guard draft.tags.indices.contains(index) else { return }
                    draft.tags.remove(at: index)
                }
            }
            .scrollsSidewaysAtLargeText()
        }
    }

    private func save() {
        isSaving = true
        modelFB.saveEdits(of: recipeFB, from: draft, newImage: recipeImage) { result in
            isSaving = false
            switch result {
            case .success:
                onSaved()
                dismiss()
            case .failure(let error):
                saveErrorMessage = error.localizedDescription
            }
        }
    }
}
