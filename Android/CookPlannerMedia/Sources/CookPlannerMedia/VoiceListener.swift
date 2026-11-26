// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
#endif

/// Listens for the cook's commands with Android's SpeechRecognizer, one
/// short phrase after another, starting again after each result or
/// silence until `stop`. The native app reads what was heard — no
/// callback crosses the bridge: `heardCount` counts up with every phrase,
/// `lastHeard` holds it, and the cook mode's clock looks once a second
/// (the iPhone's CookVoiceListener does the same job with SpeechAnalyzer).
/// Recognition on the device where Android offers it.
public final class VoiceListener {

    public init() {
    }

    /// The last phrase heard, and how many phrases so far.
    public var lastHeard: String = ""
    public var heardCount: Int = 0
    /// "listening", "off", or "unavailable" (no recognition on the device).
    public var state: String = "off"
    /// While true the recognizer is paused (the app is talking), so its
    /// own voice is not taken for a command.
    public var isMuted: Bool = false

    /// Starts listening in `languageTag` ("de-DE"); harmless while on.
    public func start(languageTag: String) {
        #if SKIP
        tag = languageTag
        wanted = true
        Handler(Looper.getMainLooper()).post {
            self.begin()
        }
        #endif
    }

    public func stop() {
        #if SKIP
        wanted = false
        state = "off"
        Handler(Looper.getMainLooper()).post {
            self.recognizer?.destroy()
            self.recognizer = nil
        }
        #endif
    }

    #if SKIP
    private var recognizer: SpeechRecognizer? = nil
    private var wanted = false
    private var tag = "de-DE"

    private func begin() {
        guard wanted else { return }
        let context = ProcessInfo.processInfo.androidContext
        guard SpeechRecognizer.isRecognitionAvailable(context) else {
            state = "unavailable"
            return
        }
        if recognizer == nil {
            let created = SpeechRecognizer.createSpeechRecognizer(context)
            created.setRecognitionListener(Listener(owner: self))
            recognizer = created
        }
        let intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, tag)
        intent.putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        state = "listening"
        recognizer?.startListening(intent)
    }

    /// The next phrase, a moment after the last one (or after silence);
    /// while muted it waits.
    fileprivate func again() {
        guard wanted else { return }
        Handler(Looper.getMainLooper()).postDelayed({
            if self.isMuted {
                self.again()
            } else {
                self.begin()
            }
        }, Int64(isMuted ? 400 : 150))
    }

    fileprivate func heard(_ text: String) {
        lastHeard = text
        heardCount += 1
    }

    private final class Listener: RecognitionListener {
        let owner: VoiceListener

        init(owner: VoiceListener) {
            self.owner = owner
        }

        override func onResults(results: Bundle?) {
            let matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if let text = matches?.firstOrNull(), !text.isEmpty {
                owner.heard(text)
            }
            owner.again()
        }

        override func onError(error: Int) {
            // Silence and "nothing understood" end a turn; listen again.
            owner.again()
        }

        override func onReadyForSpeech(params: Bundle?) {}
        override func onBeginningOfSpeech() {}
        override func onRmsChanged(rmsdB: Float) {}
        override func onBufferReceived(buffer: ByteArray?) {}
        override func onEndOfSpeech() {}
        override func onPartialResults(partialResults: Bundle?) {}
        override func onEvent(eventType: Int, params: Bundle?) {}
    }
    #endif
}
#endif
