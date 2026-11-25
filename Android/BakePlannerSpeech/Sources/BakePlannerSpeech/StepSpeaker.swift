// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation
#if !SKIP
import AVFoundation
#else
import android.speech.tts.TextToSpeech
#endif

/// Reads a text aloud in a given language, one at a time: a new text stops
/// the one before. On Android the system's TextToSpeech, which starts up
/// asynchronously — a text asked for before it is ready is read as soon as
/// it is; on Apple platforms AVSpeechSynthesizer.
public final class StepSpeaker {

    public init() {
    }

    /// Whether a text is being read right now.
    public var isSpeaking: Bool {
        #if SKIP
        return engine?.isSpeaking() == true
        #else
        return synthesizer.isSpeaking
        #endif
    }

    /// Reads `text` aloud in `languageCode` ("de", "en_GB", "fr-FR"),
    /// stopping whatever was being read.
    public func speak(_ text: String, languageCode: String) {
        let tag = languageCode.replacingOccurrences(of: "_", with: "-")
        #if SKIP
        if let engine, ready {
            engine.stop()
            say(text, tag: tag, on: engine)
        } else {
            pendingText = text
            pendingTag = tag
            if engine == nil {
                startEngine()
            }
        }
        #else
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: tag)
        synthesizer.speak(utterance)
        #endif
    }

    /// Stops reading, at once.
    public func stop() {
        #if SKIP
        pendingText = nil
        engine?.stop()
        #else
        synthesizer.stopSpeaking(at: .immediate)
        #endif
    }

    /// Stops reading and lets go of the speech engine; a later `speak`
    /// starts it again.
    public func shutdown() {
        #if SKIP
        pendingText = nil
        engine?.stop()
        engine?.shutdown()
        engine = nil
        ready = false
        #else
        synthesizer.stopSpeaking(at: .immediate)
        #endif
    }

    #if SKIP
    private var engine: TextToSpeech? = nil
    private var ready = false
    private var pendingText: String? = nil
    private var pendingTag: String? = nil

    private func startEngine() {
        let context = ProcessInfo.processInfo.androidContext
        engine = TextToSpeech(context) { status in
            self.ready = status == TextToSpeech.SUCCESS
            guard self.ready, let engine = self.engine, let text = self.pendingText, let tag = self.pendingTag else {
                return
            }
            self.pendingText = nil
            self.say(text, tag: tag, on: engine)
        }
    }

    private func say(_ text: String, tag: String, on engine: TextToSpeech) {
        engine.setLanguage(java.util.Locale.forLanguageTag(tag))
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, nil, "bakeplanner-step")
    }
    #else
    private let synthesizer = AVSpeechSynthesizer()
    #endif
}
#endif
