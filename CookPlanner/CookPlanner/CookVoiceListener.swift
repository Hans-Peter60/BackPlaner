//
//  CookVoiceListener.swift
//  CookPlanner
//
//  The ear of the cook mode: the microphone feeds the on-device speech
//  recognizer of iOS 26 (SpeechAnalyzer), and whenever what was said ends
//  with one of the cook mode's commands (CookVoiceCommands in the package),
//  the view is told. Nothing leaves the device; the microphone is dropped
//  while the app itself talks. The same machinery as BakePlanner's
//  listener, with the cook's words.
//

import AVFoundation
import BakePlannerCore
import Foundation
import os
import Speech

@MainActor
@Observable
final class CookVoiceListener {

    enum State: Equatable {
        case off
        /// Asking for the microphone, fetching the language model.
        case preparing
        case listening
        case microphoneDenied
        /// No recognizer for the app's language on this device.
        case unavailable
        case failed(String)
    }

    private static let log = Logger(subsystem: "de.hpm64625.CookPlanner", category: "voice")

    private(set) var state: State = .off
    /// The command heard last, for the line on screen.
    private(set) var lastHeard: CookVoiceCommand?
    var onCommand: ((CookVoiceCommand) -> Void)?

    var isActive: Bool { state != .off }

    /// While the app itself talks, the microphone's buffers are dropped so
    /// the synthesizer is not taken for the baker.
    var isMuted: Bool {
        get { feeder?.isMuted ?? false }
        set { feeder?.isMuted = newValue }
    }

    private let engine = AVAudioEngine()
    private var feeder: AudioFeeder?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var languageCode = "de"
    /// The last command and the start of the audio range it came from: a
    /// tentative result and its final form carry the same words once.
    private var lastFired: (command: CookVoiceCommand, rangeStart: Double)?

    // MARK: Start and stop

    func start(languageCode: String) async {
        guard !isActive || state != .listening else { return }
        stop()
        state = .preparing
        self.languageCode = languageCode

        guard await AVAudioApplication.requestRecordPermission() else {
            state = .microphoneDenied
            return
        }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: languageCode)) else {
            state = .unavailable
            return
        }

        do {
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            // The language model has to be reserved before it can be asked
            // for; the app speaks three languages, the device allows a few.
            do {
                try await AssetInventory.reserve(locale: locale)
            } catch {
                for old in await AssetInventory.reservedLocales {
                    await AssetInventory.release(reservedLocale: old)
                }
                try await AssetInventory.reserve(locale: locale)
            }
            // No model for the language on this device (the simulator, say):
            // a plain word instead of the download's error.
            if await AssetInventory.status(forModules: [transcriber]) == .unsupported {
                stop()
                state = .unavailable
                return
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .unavailable
                return
            }

            let (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        self.handle(transcript: String(result.text.characters),
                                    rangeStart: result.range.start.seconds)
                    }
                } catch {
                    self?.fail(error)
                }
            }

            try startMicrophone(into: builder, format: format)
            try await analyzer.start(inputSequence: stream)
            observeInterruptions()
            state = .listening
        } catch {
            Self.log.error("Voice commands could not start: \(error.localizedDescription)")
            stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        resultsTask?.cancel()
        resultsTask = nil
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        feeder?.finish()
        feeder = nil
        if let analyzer {
            self.analyzer = nil
            Task { await analyzer.cancelAndFinishNow() }
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if state != .off {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        lastHeard = nil
        lastFired = nil
        state = .off
    }

    // MARK: Microphone

    private func startMicrophone(into builder: AsyncStream<AnalyzerInput>.Continuation,
                                 format: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw ListenerError.noMicrophoneFormat
        }
        let feeder = AudioFeeder(converter: converter, format: format, builder: builder)
        self.feeder = feeder
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            feeder.feed(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// A phone call or another app's audio ends the session; the cook
    /// switches the microphone on again when it suits.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    // MARK: Results

    private func handle(transcript: String, rangeStart: Double) {
        guard state == .listening, !isMuted,
              let command = CookVoiceCommands.command(in: transcript, languageCode: languageCode) else { return }
        if let lastFired, lastFired.command == command, lastFired.rangeStart == rangeStart {
            return
        }
        lastFired = (command, rangeStart)
        lastHeard = command
        onCommand?(command)
    }

    private func fail(_ error: Error) {
        guard state == .listening || state == .preparing else { return }
        Self.log.error("Voice commands stopped: \(error.localizedDescription)")
        stop()
        state = .failed(error.localizedDescription)
    }

    enum ListenerError: LocalizedError {
        case noMicrophoneFormat
        var errorDescription: String? {
            String(localized: "Das Mikrofon liefert kein Audio.")
        }
    }
}

/// Converts the microphone's buffers to the recognizer's format on the
/// audio thread and hands them on. Shared between that thread and the
/// listener, so its state sits behind a lock.
private final class AudioFeeder: @unchecked Sendable {

    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let builder: AsyncStream<AnalyzerInput>.Continuation
    private let muted = OSAllocatedUnfairLock(initialState: false)

    init(converter: AVAudioConverter, format: AVAudioFormat, builder: AsyncStream<AnalyzerInput>.Continuation) {
        self.converter = converter
        self.format = format
        self.builder = builder
    }

    var isMuted: Bool {
        get { muted.withLock { $0 } }
        set { muted.withLock { $0 = newValue } }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard !isMuted else { return }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, converted.frameLength > 0 else { return }
        builder.yield(AnalyzerInput(buffer: converted))
    }

    func finish() {
        builder.finish()
    }
}
