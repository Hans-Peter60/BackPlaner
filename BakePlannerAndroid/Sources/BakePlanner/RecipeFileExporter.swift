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

    enum Outcome {
        case saved, failed
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: recipeIDs) { _, ids in
                guard let ids else { return }
                recipeIDs = nil
                fileURL = model.exportFile(recipeIDs: ids, named: fileName, includingBakeHistory: includesBakeHistory)
                if fileURL == nil {
                    outcome = .failed
                    showsOutcome = true
                } else {
                    showsExporter = true
                }
            }
            .withDocumentExporter(isPresented: $showsExporter, contentType: .json, documentURL: fileURL) { result in
                switch result {
                case .success: outcome = .saved
                case .failure: outcome = .failed
                }
                showsOutcome = true
            }
            .alert(outcome == .saved ? LocalizedStringKey("Gesichert") : LocalizedStringKey("Sichern fehlgeschlagen"),
                   isPresented: $showsOutcome) {
                Button(role: .cancel) {
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
