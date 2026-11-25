//
//  DishTextImportView.swift
//  CookPlanner
//
//  A recipe pasted as text — or photographed, its text read on the device
//  (PhotoTextReader) — read into work steps by the cloud AI, and handed to
//  the editor for the cook to check before it is kept.
//

import BakePlannerCore
import PhotosUI
import SwiftUI
import UIKit

struct DishTextImportView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isAnalyzing = false
    /// The analysis under way, so "Abbrechen" can stop it: the call may
    /// take minutes when the connection is poor.
    @State private var analysisTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var result: DishImportResult?
    @FocusState private var editing: Bool
    /// Opened from "Aus Fotos importieren": the photo section comes first.
    var startsWithPhotos = false
    /// Called with the dish the cook accepted for the editor.
    let onImported: (KitchenDish) -> Void
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var scanning = false
    @State private var isReadingPhotos = false
    /// The text came from photos; the dish is marked so.
    @State private var fromPhotos = false

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    DishImportResultSections(result: result, onAccept: {
                        onImported(result.dish)
                        dismiss()
                    }, onRetry: {
                        self.result = nil
                    }, retryTitle: "Anderen Text analysieren")
                } else {
                    inputSections
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(startsWithPhotos ? "Aus Fotos importieren" : "Aus Text importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        analysisTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { editing = false }
                }
            }
            .alert("Import fehlgeschlagen",
                   isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isAnalyzing || isReadingPhotos)
        .fullScreenCover(isPresented: $scanning) {
            DocumentScannerView { pages in read(pages) }
                .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for item in items {
                    // Read small (ImageIO): the text is legible at 2000 px,
                    // and four full camera photos would fill the memory.
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = CookRunLog.downsampled(data, maxPixels: 2000) {
                        images.append(image)
                    }
                }
                photoItems = []
                read(images)
            }
        }
        #if DEBUG
        // Development builds take the text from a file named by the launch
        // argument -ImportTextFile, for import runs on the simulator where
        // the paste button cannot be driven.
        .onAppear {
            guard text.isEmpty, let path = UserDefaults.standard.string(forKey: "ImportTextFile"),
                  let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            text = contents
        }
        #endif
    }

    @ViewBuilder
    private var inputSections: some View {
        if startsWithPhotos {
            photoSection
            textSection
        } else {
            textSection
            photoSection
        }
        analyzeSection
    }

    private var photoSection: some View {
        Section {
            if DocumentScannerView.isAvailable {
                Button {
                    scanning = true
                } label: {
                    Label("Seiten scannen", systemImage: "doc.viewfinder")
                }
                .disabled(isReadingPhotos || isAnalyzing)
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                Label("Fotos auswählen", systemImage: "photo.on.rectangle")
            }
            .disabled(isReadingPhotos || isAnalyzing)
            if isReadingPhotos {
                HStack {
                    ProgressView()
                    Text("Text wird erkannt …")
                }
            }
        } header: {
            Text("Fotos")
        } footer: {
            Text("Ein Kochbuch oder ein Zettel: Der Text wird auf dem iPhone erkannt und erscheint im Feld, wo Du ihn prüfen kannst. Die Fotos verlassen das Gerät nicht.")
        }
    }

    @ViewBuilder
    private var textSection: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .focused($editing)
            // The system's paste button: no permission prompt, the text
            // arrives only when the person taps it.
            PasteButton(payloadType: String.self) { strings in
                if let pasted = strings.first { text = pasted }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
        } header: {
            Text("Rezepttext")
        } footer: {
            Text("Zutaten und Zubereitung, wie sie im Rezept stehen. Die Analyse schätzt die Arbeitszeiten und schlägt Reihenfolge und Abhängigkeiten vor; Du prüfst alles, bevor es gespeichert wird.")
        }
    }

    private var analyzeSection: some View {
        Section {
            Button {
                analyze()
            } label: {
                if isAnalyzing {
                    HStack {
                        ProgressView()
                        Text("Wird analysiert …")
                    }
                } else {
                    Label("Analysieren", systemImage: "sparkles")
                }
            }
            .disabled(isAnalyzing || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40)
        } footer: {
            Text("Der Text wird zur Analyse an einen Dienst von Google gesendet.")
        }
    }

    private func analyze() {
        editing = false
        isAnalyzing = true
        let input = text
        analysisTask?.cancel()
        analysisTask = Task {
            defer { isAnalyzing = false }
            do {
                let analysis = try await DishImportClient.shared.analyzeText(input)
                guard !Task.isCancelled else { return }
                let dish = CloudDishImport.dish(from: analysis.dish, source: fromPhotos ? .photo : .text,
                                                fallbackName: String(localized: "Gericht"))
                result = DishImportResult(dish: dish, warnings: analysis.dish.warnings ?? [],
                                          notice: analysis.freeImports?.notice())
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reads the pages' text into the field, after what is already there.
    private func read(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        isReadingPhotos = true
        Task {
            let recognized = await PhotoTextReader.text(of: images)
            isReadingPhotos = false
            if recognized.isEmpty {
                errorMessage = String(localized: "Auf den Fotos wurde kein Text erkannt.")
                return
            }
            fromPhotos = true
            text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? recognized : text + "\n\n" + recognized
        }
    }
}
