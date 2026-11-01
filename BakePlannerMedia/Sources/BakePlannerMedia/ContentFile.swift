// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation

/// The bytes behind an address the system handed out. On Android a photo
/// the camera took or a file another app shares arrives as a `content://`
/// address of a content provider, which native Swift cannot open as a
/// file; the ContentResolver can. On Apple platforms the address is a
/// file and is read as one.
public final class ContentFile {

    /// The whole content at `urlString`, or nil when it cannot be read.
    public static func data(atURLString urlString: String) -> Data? {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        let uri = android.net.Uri.parse(urlString)
        guard let stream = context.contentResolver.openInputStream(uri) else { return nil }
        defer { stream.close() }
        return Data(platformValue: stream.readBytes())
        #else
        guard let url = URL(string: urlString) else { return nil }
        return try? Data(contentsOf: url)
        #endif
    }

    /// Removes what is behind `urlString`, once it was read: the camera's
    /// temporary file would otherwise stay in the app's pictures folder.
    public static func remove(atURLString urlString: String) {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        let uri = android.net.Uri.parse(urlString)
        _ = try? context.contentResolver.delete(uri, nil, nil)
        #else
        if let url = URL(string: urlString) {
            try? FileManager.default.removeItem(at: url)
        }
        #endif
    }
}
#endif
