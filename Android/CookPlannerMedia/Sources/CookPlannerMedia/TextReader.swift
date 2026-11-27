// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
#endif

/// Reads the text on a photo with ML Kit's text recognition, on the
/// device (the model comes with the app, nothing goes to a server), for
/// the import from a cookbook page or a handwritten card — the iPhone
/// does the same with Vision. The native app polls: `read` starts,
/// `state` turns "done" (with `text`) or "failed"; no callback crosses
/// the bridge.
public final class TextReader {

    public init() {
    }

    /// The text found, lines as ML Kit orders them, blocks apart by a line.
    public var text: String = ""
    /// "idle", "reading", "done" or "failed".
    public var state: String = "idle"

    /// Starts reading the picture at `path` (a JPEG the app wrote);
    /// the camera's orientation in the file is honoured.
    public func read(path: String) {
        #if SKIP
        state = "reading"
        text = ""
        do {
            let context = ProcessInfo.processInfo.androidContext
            let image = try InputImage.fromFilePath(context, Uri.fromFile(java.io.File(path)))
            let recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { result in
                    self.text = result.text
                    self.state = "done"
                    recognizer.close()
                }
                .addOnFailureListener { error in
                    self.state = "failed"
                    recognizer.close()
                }
        } catch {
            state = "failed"
        }
        #endif
    }
}
#endif
