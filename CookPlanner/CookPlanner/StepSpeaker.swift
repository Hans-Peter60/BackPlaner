//
//  StepSpeaker.swift
//  CookPlanner
//
//  The voice of the cook mode: reads a step, an ingredient list or a short
//  answer aloud with the system voice of the app's language. The same
//  class as BakePlanner's; it lives here because the apps share no
//  AVFoundation code through the package.
//
//  Main-actor isolated: the view drives it, and AVSpeechSynthesizerDelegate
//  is Sendable, which a plain class with mutable state cannot be. The
//  delegate callbacks arrive on the synthesizer's own queue and hop over.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class StepSpeaker: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false
    /// False while the voice listener holds the audio session for the
    /// microphone: then the speaker neither reconfigures nor releases it.
    var managesAudioSession = true

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()

        if managesAudioSession {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceLanguage)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    /// The BCP 47 tag of the app's language; German, the source language,
    /// for anything else.
    private static var voiceLanguage: String {
        switch Locale.current.language.languageCode?.identifier {
        case "en": return "en-US"
        case "fr": return "fr-FR"
        default:   return "de-DE"
        }
    }

    private func finished() {
        isSpeaking = false
        if managesAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
