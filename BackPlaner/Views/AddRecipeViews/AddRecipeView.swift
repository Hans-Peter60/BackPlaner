//
//  AddRecipeView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import SwiftUI
import CoreData

struct AddRecipeView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    
    @State private var recipeFB: RecipeFB
    
    // Recipe Image
    @State private var recipeImage: UIImage?
    
    // Image Picker
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary
    @State private var placeHolderImage: Image
    @State private var showingAlert         = false
    @State private var storage              = AppSettings.defaultStoragePreference
    @State private var showEULA             = false
    @State private var showPublicSaveWarning = false
    @State private var showPrivateCloudSaveWarning = false
    /// A private cloud recipe needs a permanent account; ask for it when the
    /// user chose that option while still being anonymous.
    @State private var showSignInRequest    = false
    @State private var pendingPrivateCloudSave = false
    // Public-upload feedback: a spinner while the recipe is being sent and an
    // error message if it fails, so the save is no longer silent "fire and forget".
    @State private var isUploading          = false
    @State private var uploadErrorMessage: String?
    @State private var showMissingImageAlert = false
    
    init(initialRecipe: RecipeFB? = nil, initialImage: UIImage? = nil) {
        _recipeFB = State(initialValue: initialRecipe ?? RecipeFB())
        _recipeImage = State(initialValue: initialImage)
        _placeHolderImage = State(initialValue: initialImage.map(Image.init(uiImage:)) ?? Image(systemName: "photo"))
        // An imported recipe comes from someone else's page, so it must not
        // default to being published — it starts out local.
        _storage = State(initialValue: initialRecipe == nil ? AppSettings.defaultStoragePreference : .privateRecipe)
        UITableView.appearance().sectionFooterHeight = 0
    }

    /// A recipe needs at least a (non-whitespace) name before it can be saved,
    /// so the save button is disabled until one is entered.
    private var canSave: Bool {
        !recipeFB.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasRecipeImage: Bool {
        guard let recipeImage else { return false }
        return recipeImage.size.width > 0 && recipeImage.size.height > 0
    }

    var body: some View {
        // The alerts and sheets hang off a separate property: as one single
        // expression, body grew beyond what the type checker resolves in
        // reasonable time.
        styledForm
            .alert("Upload fehlgeschlagen", isPresented: uploadErrorPresented) {
                Button("OK", role: .cancel) { uploadErrorMessage = nil }
            } message: {
                Text(uploadErrorMessage ?? "")
            }
            .alert("Bild erforderlich", isPresented: $showMissingImageAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Das Rezept kann nicht gespeichert werden. Bitte füge zuerst ein Rezeptbild hinzu.")
            }
            .alert("Öffentliches Rezept kann nicht geändert werden", isPresented: $showPublicSaveWarning) {
                Button("Abbrechen", role: .cancel) { }
                Button("Öffentlich speichern") {
                    continuePublicSaveAfterWarning()
                }
            } message: {
                Text("Ein öffentliches Rezept kann nach dem Speichern nicht mehr geändert werden.")
            }
            // Presenting the warning from the sheet's callback would race with
            // the sheet's own dismissal, so it waits until the sheet is gone.
            .sheet(isPresented: $showSignInRequest, onDismiss: {
                guard pendingPrivateCloudSave else { return }
                pendingPrivateCloudSave = false
                showPrivateCloudSaveWarning = true
            }) {
                PrivateCloudSignInSheet {
                    pendingPrivateCloudSave = true
                }
            }
            .alert("Cloud-Rezept kann nicht geändert werden", isPresented: $showPrivateCloudSaveWarning) {
                Button("Abbrechen", role: .cancel) { }
                Button("Privat speichern") {
                    addRecipe(to: .privateCloudRecipe)
                }
            } message: {
                Text("Ein Rezept in der Rezept-Datenbank kann nach dem Speichern nicht mehr geändert werden. Es ist nur für Dich sichtbar.")
            }
            .navigationTitle("Neues Rezept erfassen")
    }

    /// True while an upload error is waiting to be acknowledged.
    private var uploadErrorPresented: Binding<Bool> {
        Binding(get: { uploadErrorMessage != nil },
                set: { if !$0 { uploadErrorMessage = nil } })
    }

    private var styledForm: some View {
        
        Form {
            Section {
                NavigationLink {
                    RecipeImageImportView()
                } label: {
                    Label("Rezept aus Bildern importieren", systemImage: "doc.viewfinder")
                }
            } footer: {
                Text("Mehrere Seiten können gemeinsam analysiert und anschließend bearbeitet werden.")
            }
            
            Section("Speichern") {
                Picker("Ablage", selection: $storage) {
                    ForEach(RecipeStoragePreference.allCases) { preference in
                        Text(preference.shortTitle).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text(storage.explanation)
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)

                HStack {
                    IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Inhalte löschen", title: "Inhalte löschen", controlSize: .regular) {
                        clear()
                    }

                    Spacer()

                    IconActionButton(systemImage: storage.symbolName, style: .primary, accessibilityLabel: "Rezept speichern", title: "Rezept speichern", controlSize: .regular) {
                        requestSave()
                    }
                    // Prevent saving an unnamed (effectively empty) recipe, or
                    // starting a second upload while one is still in flight.
                    .disabled(!canSave || isUploading)
                    .alert("Rezept wurde gespeichert", isPresented: $showingAlert) {
                        Button("OK", role: .cancel) { }
                    }
                    .sheet(isPresented: $showEULA) {
                        EULAView {
                            addRecipe(to: .publicRecipe)
                        }
                    }
                }
            }

            Section {
                // Recipe image
                placeHolderImage
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 50, idealWidth: 100, maxWidth: 150, minHeight: 50, idealHeight: 100, maxHeight: 150, alignment: .center)
                    .accessibilityLabel(hasRecipeImage ? "Rezeptbild" : "Noch kein Rezeptbild")
                
                HStack {
                    IconActionButton(systemImage: "photo.on.rectangle", style: .primary, accessibilityLabel: "Fotomediathek öffnen", title: "Fotomediathek", controlSize: .regular) {
                        selectedImageSource  = .photoLibrary
                        isShowingImagePicker = true
                    }

                    // Offer direct camera capture too, but only on devices that
                    // actually have a camera (never on the Simulator).
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Spacer()

                        IconActionButton(systemImage: "camera", style: .primary, accessibilityLabel: "Kamera öffnen", title: "Kamera", controlSize: .regular) {
                            selectedImageSource  = .camera
                            isShowingImagePicker = true
                        }
                    }
                }
                .sheet(isPresented: $isShowingImagePicker, onDismiss: loadImage) {
                    ImagePicker(selectedSource: selectedImageSource, recipeImage: $recipeImage)
                }
            }
                    
//            RatingStarsUpdateView(rating: $recipeFB.rating)
//                .padding()
                        
            Section {
                // The recipe meta data
                AddMetaDataView(name:    $recipeFB.name,
                            summary: $recipeFB.summary,
                            urlLink: $recipeFB.urlLink)
                
                AddTagsDataView(tags: $recipeFB.tags, title: "Tags", placeholderText: "...")
            }
            
            Section {
                
                AddComponentDataView(components: $recipeFB.components)
            }
            
            Section {
                // Instruction Data
                AddInstructionDataView(instructions: $recipeFB.instructions)
            }
        }
        // Match RecipeDetailView: use the Avenir body font throughout instead of
        // the system default. Set on the Form so every label and input field inherits it.
        .font(Theme.bodyFont(15))
        .clearScrollBackground()
        .warmBackground()
        // Show progress while a public upload is running …
        .overlay {
            if isUploading {
                ProgressView("Rezept wird hochgeladen …")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    /// Where the recipe is stored, and the button that saves it. Its own
    /// property, so the type checker does not have to resolve it as part of the
    /// (very large) body expression.
    @ViewBuilder
    private var saveSection: some View {
        Section("Speichern") {
            Picker("Ablage", selection: $storage) {
                ForEach(RecipeStoragePreference.allCases) { preference in
                    Text(preference.shortTitle).tag(preference)
                }
            }
            .pickerStyle(.segmented)

            Text(storage.explanation)
                .font(Theme.bodyFont(13))
                .foregroundColor(Theme.subtitle)

            HStack {
                IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Inhalte löschen", title: "Inhalte löschen", controlSize: .regular) {
                    clear()
                }

                Spacer()

                IconActionButton(systemImage: storage.symbolName, style: .primary, accessibilityLabel: "Rezept speichern", title: "Rezept speichern", controlSize: .regular) {
                    requestSave()
                }
                // Prevent saving an unnamed (effectively empty) recipe, or
                // starting a second upload while one is still in flight.
                .disabled(!canSave || isUploading)
                .alert("Rezept wurde gespeichert", isPresented: $showingAlert) {
                    Button("OK", role: .cancel) { }
                }
                .sheet(isPresented: $showEULA) {
                    EULAView {
                        addRecipe(to: .publicRecipe)
                    }
                }
            }
        }
    }

    func loadImage() {
        
        // Check if an image was selected from the library
        if recipeImage != nil {
            // Set it as the placeholder image
            placeHolderImage = Image(uiImage: recipeImage!)
        }
    }
    
    func clear() {
        
        recipeFB = RecipeFB()
        recipeImage = nil
        storage = AppSettings.defaultStoragePreference
        
        placeHolderImage = Image(systemName: "photo")
    }

    private func requestSave() {
        guard hasRecipeImage else {
            showMissingImageAlert = true
            return
        }

        switch storage {
        case .privateRecipe:
            addRecipe(to: .privateRecipe)
        case .privateCloudRecipe:
            // The recipe is tied to the author's uid, so it needs an identity
            // that outlives this installation.
            if modelFB.isSignedInWithAccount {
                showPrivateCloudSaveWarning = true
            } else {
                showSignInRequest = true
            }
        case .publicRecipe:
            showPublicSaveWarning = true
        }
    }

    private func continuePublicSaveAfterWarning() {
        // Publishing to the shared database requires accepting the content agreement first.
        if !ModerationStore.shared.hasAcceptedEULA {
            showEULA = true
        } else {
            addRecipe(to: .publicRecipe)
        }
    }
    
    func addRecipe(to target: RecipeStoragePreference) {

        if let visibility = target.cloudVisibility {
            // The upload is asynchronous: show a spinner, then confirm on
            // success or surface the error on failure.
            isUploading = true
            modelFB.uploadRecipeToFirestore(r: recipeFB, i: recipeImage ?? UIImage(), visibility: visibility) { result in
                isUploading = false
                switch result {
                case .success:
                    clear()
                    showingAlert = true
                case .failure(let error):
                    uploadErrorMessage = error.localizedDescription
                }
            }
        }
        else {
            // Local Core Data save is synchronous, so confirm immediately.
            _ = model.uploadRecipeIntoCoreData(recipeId: nil, recipeFB: recipeFB, context: viewContext, recipeImage: recipeImage ?? UIImage())
            clear()
            showingAlert = true
        }
    }
}
