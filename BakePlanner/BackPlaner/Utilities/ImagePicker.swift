//
//  ImagePicker.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import BakePlannerCore
import SwiftUI

/// The source as the item of a `.sheet(item:)`. Presented with
/// `isPresented` and a separate source state, the sheet was built with
/// the source of the previous tap — "Kamera" opened the photo library the
/// first time, the camera only the second — because both states changed
/// in the same turn and the sheet's content read the old one.
extension UIImagePickerController.SourceType: @retroactive Identifiable {
    public var id: Int { rawValue }
}

struct ImagePicker: UIViewControllerRepresentable {
    
    @Environment(\.presentationMode) var presentationMode
    
    var selectedSource: UIImagePickerController.SourceType
    
    @Binding var recipeImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        
        // Create the image picker controller
        let imagePickerController = UIImagePickerController()
        imagePickerController.delegate = context.coordinator
        
        // Check that this source is available first
        if UIImagePickerController.isSourceTypeAvailable(selectedSource) {
            imagePickerController.sourceType = selectedSource
        }
        
        return imagePickerController
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        // Create a coordinator
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        
        var parent: ImagePicker
        
        init(parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            
            // Check if we can get the image
            if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            
                // We were able to get the uiimage into the image constant, pass this back to the AddRecipeView
                parent.recipeImage = image
            }
            // Dismiss this view
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

struct ImageArrayPicker: UIViewControllerRepresentable {
    
    @Environment(\.presentationMode) var presentationMode
    
    var selectedSource: UIImagePickerController.SourceType
    
    @Binding var recipeImages: [UIImage?]
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        
        // Create the image picker controller
        let imagePickerController = UIImagePickerController()
        imagePickerController.delegate = context.coordinator
        
        // Check that this source is available first
        if UIImagePickerController.isSourceTypeAvailable(selectedSource) {
            imagePickerController.sourceType = selectedSource
        }
        
        return imagePickerController
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        // Create a coordinator
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        
        var parent: ImageArrayPicker
        
        init(parent: ImageArrayPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            
            // Check if we can get the image
            if let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            
                // We were able to get the uiimage into the image constant, pass this back to the AddRecipeView
                parent.recipeImages.append(image)
            }
            // Dismiss this view
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
