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
    @ViewBuilder let label: () -> Label

    @State private var writtenFile: URL?

    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            Button {
                do {
                    writtenFile = try item.writeFile()
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
