//
//  PhotoTextReader.swift
//  CookPlanner
//
//  The text of photographed recipe pages, read on the device with Vision.
//  The photo import does not send pictures anywhere: the recognized text
//  lands in the import's text field, the cook can correct it, and only
//  that text goes to the cloud analysis like a pasted recipe.
//

import SwiftUI
import UIKit
import Vision
import VisionKit

enum PhotoTextReader {

    /// The pages' text in reading order, pages apart by a blank line.
    static func text(of images: [UIImage]) async -> String {
        var pages: [String] = []
        for image in images {
            guard let cgImage = image.cgImage else { continue }
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let page = await documentText(cgImage, orientation: orientation)
            let text = page.isEmpty ? await lineText(cgImage, orientation: orientation) : page
            if !text.isEmpty { pages.append(text) }
        }
        return pages.joined(separator: "\n\n")
    }

    private static let languages = [Locale.Language(identifier: "de-DE"), Locale.Language(identifier: "en-US"),
                                    Locale.Language(identifier: "fr-FR")]

    /// The document reader keeps columns and lists together, which a
    /// cookbook page with ingredients beside the method needs.
    private static func documentText(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = languages
        request.textRecognitionOptions.useLanguageCorrection = true
        guard let observations = try? await request.perform(on: image, orientation: orientation) else { return "" }
        return observations.map(\.document.text.transcript)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Line by line, top to bottom, when the document reader found nothing.
    private static func lineText(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image, orientation: orientation) else { return "" }
        return observations.map(\.transcript).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The system's document camera: finds the page, straightens it, and
/// takes several pages in a row.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScanned: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Twenty cookbook pages at camera size would not fit in memory;
            // the text is legible at 2000 px.
            let pages = (0..<scan.pageCount).compactMap { index -> UIImage? in
                let page = scan.imageOfPage(at: index)
                guard let data = page.jpegData(compressionQuality: 0.9) else { return page }
                return CookRunLog.downsampled(data, maxPixels: 2000) ?? page
            }
            parent.onScanned(pages)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
