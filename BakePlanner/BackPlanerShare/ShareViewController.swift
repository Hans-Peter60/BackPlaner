//
//  ShareViewController.swift
//  BackPlanerShare
//
//  The app's entry in the share sheet. It takes the address of the page being
//  shared, parks it in the App Group and opens BakePlanner, where the web
//  import starts with it. The extension never loads the page itself: the
//  import needs the signed-in Firebase client and the on-device AI, and both
//  live in the app.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let model = ShareImportModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let importView = ShareImportView(model: model) { [weak self] in
            self?.handOffToApp()
        } onCancel: { [weak self] in
            self?.cancel()
        } onDone: { [weak self] in
            self?.finish()
        }

        let host = UIHostingController(rootView: importView)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)

        loadSharedURL()
    }

    // MARK: The shared address

    private func loadSharedURL() {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments)
            .flatMap { $0 } ?? []

        guard let provider = attachments.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            model.phase = .failed(String(localized: "Diese Freigabe enthält keine Internetadresse."))
            return
        }

        _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                    self.model.pageURL = url
                    self.model.phase = .ready
                } else {
                    self.model.phase = .failed(String(localized: "Diese Freigabe enthält keine Internetadresse."))
                }
            }
        }
    }

    // MARK: Handing over to the app

    private func handOffToApp() {
        guard let url = model.pageURL else { return }
        do {
            try PendingWebImport.store(url)
        } catch {
            model.phase = .failed(String(localized: "Die Adresse konnte nicht an BakePlanner übergeben werden."))
            return
        }

        guard let link = PendingWebImport.deepLink(for: url) else {
            model.phase = .handedOff
            return
        }
        openContainingApp(link) { [weak self] opened in
            guard let self else { return }
            if opened {
                // Let the app come forward before the sheet disappears under it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.finish()
                }
            } else {
                // The address is parked; the app collects it when it next
                // comes to the foreground.
                self.model.phase = .handedOff
            }
        }
    }

    /// Extensions may not call `UIApplication.open` directly, but the
    /// application object at the far end of the responder chain still
    /// implements it. The old `openURL:` shortcut is refused since iOS 27
    /// ("force returning NO"), so this calls the current method through its
    /// implementation pointer. When even that stops working, `completion`
    /// gets false and the parked address is the fallback.
    private func openContainingApp(_ url: URL, completion: @escaping (Bool) -> Void) {
        typealias OpenURLMethod = @convention(c) (
            AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
        ) -> Void

        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = next
        while let current = responder {
            // Only the application itself: a UIScene on the way answers the
            // same selector but wants an options object, not a dictionary,
            // and the call would crash the extension.
            if current.isKind(of: UIApplication.self),
               current.responds(to: selector),
               let implementation = current.method(for: selector) {
                let open = unsafeBitCast(implementation, to: OpenURLMethod.self)
                open(current, selector, url as NSURL, [:] as NSDictionary) { opened in
                    DispatchQueue.main.async { completion(opened) }
                }
                return
            }
            responder = current.next
        }
        completion(false)
    }

    // MARK: Leaving

    /// Completes rather than cancels: a cancelled request drops the user
    /// back into the share sheet, a completed one back onto the page, which
    /// is where "Abbrechen" should lead.
    private func cancel() {
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
