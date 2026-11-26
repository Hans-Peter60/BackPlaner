import BakePlannerMedia
import SkipKit
import SwiftUI

extension View {
    /// Takes a photo with the camera when `isPresented` turns true and
    /// hands it over as JPEG, shrunk the way the app keeps pictures. The
    /// camera's permission is asked for first; without it nothing opens.
    func cameraPicker(isPresented: Binding<Bool>, onPhoto: @escaping (Data) -> Void) -> some View {
        modifier(CameraPicker(isPresented: isPresented, onPhoto: onPhoto))
    }
}

/// SkipKit's camera picker writes the photo to a temporary file in the
/// app's pictures folder and reports a `content://` address of the app's
/// FileProvider (AndroidManifest.xml). Native Swift cannot open that as a
/// file; `ContentFile` in the transpiled BakePlannerMedia module reads it
/// through the ContentResolver and removes the file afterwards.
struct CameraPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPhoto: (Data) -> Void
    @State var photoURL: URL?
    /// The picker itself; set once the permission is there.
    @State var opensCamera = false

    func body(content: Content) -> some View {
        content
            .withMediaPicker(type: .camera, isPresented: $opensCamera, selectedImageURL: $photoURL)
            .onChange(of: isPresented) { _, presented in
                guard presented else { return }
                isPresented = false
                Task {
                    let authorization = await PermissionManager.requestPermission(.CAMERA)
                    if authorization == .authorized {
                        opensCamera = true
                    }
                }
            }
            .onChange(of: photoURL) { _, url in
                guard let url else { return }
                photoURL = nil
                if let data = CameraPhoto.data(at: url) {
                    onPhoto(data)
                }
            }
    }
}

enum CameraPhoto {
    /// The photo behind the picker's address as the app keeps pictures;
    /// nil when it cannot be read. A `content://` address is read through
    /// the ContentResolver and its file removed; anything else as a file.
    static func data(at url: URL) -> Data? {
        let raw: Data?
        if url.scheme == "content" {
            raw = ContentFile.data(atURLString: url.absoluteString)
            ContentFile.remove(atURLString: url.absoluteString)
        } else {
            raw = try? Data(contentsOf: url)
        }
        guard let raw else { return nil }
        return PhotoShrinker.pickedPhoto(raw)
    }
}
