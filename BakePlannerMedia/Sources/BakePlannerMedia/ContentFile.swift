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

    /// A place for a file the app hands to other apps: `shared/<name>` in
    /// the app's cache, the folder the FileProvider in AndroidManifest.xml
    /// may share. On Apple platforms the temporary directory.
    public static func sharedFilePath(named name: String) -> String {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        let folder = java.io.File(context.cacheDir, "shared")
        folder.mkdirs()
        return java.io.File(folder, name).absolutePath
        #else
        return FileManager.default.temporaryDirectory.appendingPathComponent(name).path
        #endif
    }

    /// Opens the system's share sheet for the file at `path` (made with
    /// `sharedFilePath`), as a `content://` address of the app's
    /// FileProvider with permission to read it. Whether the sheet opened.
    public static func share(filePath path: String, mimeType: String) -> Bool {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        let file = java.io.File(path)
        guard file.exists() else { return false }
        let uri = androidx.core.content.FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
        let intent = android.content.Intent(android.content.Intent.ACTION_SEND)
        intent.type = mimeType
        intent.putExtra(android.content.Intent.EXTRA_STREAM, uri)
        intent.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        let chooser = android.content.Intent.createChooser(intent, nil)
        // The application context starts activities only in a new task.
        chooser.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
        return true
        #else
        return false
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
