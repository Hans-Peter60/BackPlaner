import SkipKit
import SwiftUI

/// Saves recipes as a backup file wherever the user picks — Downloads,
/// Google Drive — through the system's "save as". Setting `recipeIDs`
/// starts it; the iPhone app reads the file under Settings.
struct RecipeFileExporter: ViewModifier {
    let model: AppModel
    @Binding var recipeIDs: [String]?
    let fileName: String
    /// True for the full backup, which carries the bake history along.
    let includesBakeHistory: Bool
    @State var fileURL: URL?
    @State var showsExporter = false
    /// Kept apart from the alert's visibility: Android closes the alert
    /// before it is read.
    @State var outcome: Outcome = .saved
    @State var showsOutcome = false
    /// While the file is written: a note on screen, and no second start.
    @State var isExporting = false

    enum Outcome {
        case saved, failed
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: recipeIDs) { _, ids in
                guard let ids, !isExporting else { return }
                recipeIDs = nil
                isExporting = true
                Task {
                    fileURL = await model.exportFile(recipeIDs: ids, named: fileName, includingBakeHistory: includesBakeHistory)
                    isExporting = false
                    if fileURL == nil {
                        outcome = .failed
                        showsOutcome = true
                    } else {
                        showsExporter = true
                    }
                }
            }
            .overlay {
                if isExporting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Wird gesichert …")
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.97)))
                }
            }
            // No completion: handing SkipKit's Result back from Kotlin to
            // Swift crashed the app right after saving (SIGTRAP in
            // SkipBridge, skip-kit 1.1.6, found 26.11.2026 on the Pixel 7).
            // The system's "save as" confirms the file itself; the alert
            // stays for a file that could not be written at all.
            .withDocumentExporter(isPresented: $showsExporter, contentType: .json, documentURL: fileURL)
            .alert(outcome == .saved ? LocalizedStringKey("Gesichert") : LocalizedStringKey("Sichern fehlgeschlagen"),
                   isPresented: $showsOutcome) {
                Button {
                } label: {
                    Text(verbatim: "OK")
                }
            }
    }
}

extension View {
    func recipeFileExporter(model: AppModel, recipeIDs: Binding<[String]?>, fileName: String,
                            includesBakeHistory: Bool) -> some View {
        modifier(RecipeFileExporter(model: model, recipeIDs: recipeIDs, fileName: fileName,
                                    includesBakeHistory: includesBakeHistory))
    }
}
