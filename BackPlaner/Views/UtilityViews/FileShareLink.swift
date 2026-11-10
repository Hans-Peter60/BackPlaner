//
//  FileShareLink.swift
//  BackPlaner
//
//  A share link for a file the app writes on demand – the recipe backup,
//  the recipe PDF, the Backtag-Zettel. On iPhone and iPad this is SwiftUI's
//  ShareLink. On the Mac ("Designed for iPad") the share sheet's "Sichern"
//  (save to Files) cannot work with the item provider a ShareLink hands
//  over: ShareKit's save service never obtains a file URL from it and calls
//  NSSavePanel with a nil name, which is an assertion and a crash. There
//  the button writes the file first and hands the URL itself to a
//  UIActivityViewController, which the Mac shows as its share popover.
//

import BakePlannerCore
import SwiftUI
import UIKit

/// A share item that can also be written as a file, for the Mac's way.
protocol FileExport: Transferable {
    /// Writes the file and returns where it is.
    func writeFile() throws -> URL
}

struct FileShareLink<Item: FileExport, PreviewImage: Transferable, PreviewIcon: Transferable, Label: View>: View {
    let item: Item
    let preview: SharePreview<PreviewImage, PreviewIcon>
    /// True for a link inside a `Menu`: a menu item has no view of its own
    /// behind which the Mac's activity sheet could sit, so there the sheet
    /// is presented from the window instead.
    var inMenu = false
    @ViewBuilder let label: () -> Label

    @State private var writtenFile: URL?

    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            Button {
                do {
                    let file = try item.writeFile()
                    if inMenu {
                        WindowActivitySheet.present(file)
                    } else {
                        writtenFile = file
                    }
                } catch {
                    AppLog.persistence.error("The file to share could not be written: \(error)")
                }
            } label: {
                label()
            }
            // Behind the button, as big as the button: the activity sheet's
            // popover is anchored to it.
            .background(ActivitySheetPresenter(file: $writtenFile))
        } else {
            ShareLink(item: item, preview: preview, label: label)
        }
    }
}

/// Presents a UIActivityViewController for `file` from the front window,
/// anchored near the top right where the menu that asked for it sits.
private enum WindowActivitySheet {
    @MainActor static func present(_ file: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.keyWindow ?? scene.windows.first,
              var presenter = window.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = window
        activity.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.maxX - 60, y: window.safeAreaInsets.top + 24,
                                                                    width: 1, height: 1)
        presenter.present(activity, animated: true)
    }
}

/// Presents a UIActivityViewController for `file` as soon as it is set, and
/// clears it when the sheet is gone.
private struct ActivitySheetPresenter: UIViewControllerRepresentable {
    @Binding var file: URL?

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let file, controller.presentedViewController == nil, !context.coordinator.isPresenting else { return }
        context.coordinator.isPresenting = true
        let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = controller.view.bounds
        activity.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.isPresenting = false
            DispatchQueue.main.async { self.file = nil }
        }
        controller.present(activity, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var isPresenting = false
    }
}
