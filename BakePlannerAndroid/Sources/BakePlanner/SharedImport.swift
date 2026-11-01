import BakePlannerCore
import Foundation

/// What another app shared with BakePlanner: the address of a recipe page
/// from the browser's share sheet (AndroidManifest.xml lets the app take
/// `text/plain`; MainActivity hands the text to the app delegate). The
/// recipe list registers a handler and gets the address, as the iPhone's
/// list does for its share extension. An address that arrives before the
/// list exists — the share started the app — waits for the handler.
///
/// A plain hand-off rather than an observed property: a change to an
/// `@Observable` singleton made from the delegate's call did not reach
/// the list's `onChange` in Skip Fuse.
@MainActor
final class SharedImport {
    static let shared = SharedImport()

    private var pendingURL: URL?
    private var handler: ((URL) -> Void)?

    private init() {
    }

    /// Takes a shared text; one without an address is ignored.
    func receive(text: String) {
        guard let url = SharedPageAddress.url(in: text) else {
            logger.debug("SharedImport: no address in the shared text")
            return
        }
        pendingURL = url
        deliver()
    }

    /// Who opens the web import; set by the recipe list when it appears.
    func setHandler(_ handler: @escaping (URL) -> Void) {
        self.handler = handler
        deliver()
    }

    private func deliver() {
        guard let handler, let url = pendingURL else { return }
        pendingURL = nil
        handler(url)
    }
}
