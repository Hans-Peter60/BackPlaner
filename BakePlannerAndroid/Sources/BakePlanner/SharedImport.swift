import BakePlannerCore
import Foundation

/// What another app shared with BakePlanner: the address of a recipe page
/// from the browser's share sheet, or recipe text selected on a page
/// (AndroidManifest.xml lets the app take `text/plain`; MainActivity hands
/// the text to the app delegate). The recipe list registers a handler and
/// gets it, as the iPhone's list does for its share extension. What
/// arrives before the list exists — the share started the app — waits for
/// the handler.
///
/// A plain hand-off rather than an observed property: a change to an
/// `@Observable` singleton made from the delegate's call did not reach
/// the list's `onChange` in Skip Fuse.
@MainActor
final class SharedImport {
    static let shared = SharedImport()

    private var pending: SharedRecipeText.Kind?
    private var handler: ((SharedRecipeText.Kind) -> Void)?

    private init() {
    }

    /// Takes a shared text; one that is neither an address nor recipe text
    /// is ignored.
    func receive(text: String) {
        guard let kind = SharedRecipeText.kind(of: text) else {
            logger.debug("SharedImport: neither an address nor recipe text in the shared text")
            return
        }
        pending = kind
        deliver()
    }

    /// Who opens the import; set by the recipe list when it appears.
    func setHandler(_ handler: @escaping (SharedRecipeText.Kind) -> Void) {
        self.handler = handler
        deliver()
    }

    private func deliver() {
        guard let handler, let kind = pending else { return }
        pending = nil
        handler(kind)
    }
}
