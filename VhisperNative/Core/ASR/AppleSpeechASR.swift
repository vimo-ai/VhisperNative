//
//  AppleSpeechASR.swift
//  VhisperNative
//
//  Apple Speech Framework ASR - 系统原生语音识别（支持离线）
//

import Foundation
import Speech
import AVFoundation

/// Apple Speech ASR service (streaming, on-device support)
final class AppleSpeechASR: StreamingASRService, @unchecked Sendable {
    private let locale: Locale
    private let useOnDevice: Bool
    private let silenceThreshold: Float = 0.01  // 音量阈值
    private let silenceTimeout: TimeInterval = 0.75  // 静默超时（秒）

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init(language: String = "zh-CN", useOnDevice: Bool = true) {
        self.locale = Locale(identifier: language)
        self.useOnDevice = useOnDevice
    }

    // MARK: - StreamingASRService

    func startStreaming(sampleRate: UInt32) async throws -> (
        control: @Sendable (StreamingControl) async -> Void,
        events: AsyncStream<StreamingASREvent>
    ) {
        // Check authorization
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            throw ASRError.api("Speech recognition not authorized: \(authStatus.rawValue)")
        }

        // Create recognizer
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw ASRError.api("Speech recognizer not available for locale: \(locale.identifier)")
        }

        guard recognizer.isAvailable else {
            throw ASRError.api("Speech recognizer not available")
        }

        self.recognizer = recognizer

        // Check on-device support
        if useOnDevice {
            if #available(macOS 10.15, *) {
                if recognizer.supportsOnDeviceRecognition {
                    print("[AppleSpeech] On-device recognition available")
                } else {
                    print("[AppleSpeech] On-device recognition not available for this locale, using online")
                }
            }
        }

        // Create event stream
        let (eventStream, eventContinuation) = AsyncStream<StreamingASREvent>.makeStream()

        // State for silence detection and auto-commit
        let state = StreamingState(
            sampleRate: sampleRate,
            silenceThreshold: silenceThreshold,
            silenceTimeout: silenceTimeout,
            eventContinuation: eventContinuation,
            recognizer: recognizer,
            useOnDevice: useOnDevice,
            locale: locale
        )

        // Start initial recognition session
        await state.startNewSession()

        // Create control handler
        let controlHandler: @Sendable (StreamingControl) async -> Void = { control in
            switch control {
            case .audio(let pcmData):
                await state.appendAudio(pcmData)

            case .commit:
                print("[AppleSpeech] Commit received, finalizing...")
                await state.commit()

            case .cancel:
                print("[AppleSpeech] Cancel received")
                await state.cancel()
            }
        }

        return (control: controlHandler, events: eventStream)
    }

    // MARK: - ASRService (batch)

    func recognize(audioData: Data, sampleRate: UInt32) async throws -> String {
        let (control, events) = try await startStreaming(sampleRate: sampleRate)

        await control(.audio(audioData))
        await control(.commit)

        for await event in events {
            switch event {
            case .final(let text):
                return text
            case .error(let msg):
                throw ASRError.api(msg)
            case .partial:
                continue
            }
        }

        throw ASRError.api("No result received")
    }
}

// MARK: - Streaming State Actor

private actor StreamingState {
    let sampleRate: UInt32
    let silenceThreshold: Float
    let silenceTimeout: TimeInterval
    let eventContinuation: AsyncStream<StreamingASREvent>.Continuation
    let recognizer: SFSpeechRecognizer
    let useOnDevice: Bool
    let locale: Locale

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastText: String = ""
    private var lastPartialText: String = ""
    private var lastCommittedText: String = ""  // Track what we already committed
    private var lastSpeechTime: Date = Date()
    private var silenceTimer: Task<Void, Never>?
    private var hasSpeech: Bool = false
    private var isFinished: Bool = false
    private var isRestartingSession: Bool = false  // Prevent duplicate restarts

    init(sampleRate: UInt32, silenceThreshold: Float, silenceTimeout: TimeInterval,
         eventContinuation: AsyncStream<StreamingASREvent>.Continuation,
         recognizer: SFSpeechRecognizer, useOnDevice: Bool, locale: Locale) {
        self.sampleRate = sampleRate
        self.silenceThreshold = silenceThreshold
        self.silenceTimeout = silenceTimeout
        self.eventContinuation = eventContinuation
        self.recognizer = recognizer
        self.useOnDevice = useOnDevice
        self.locale = locale
    }

    func startNewSession() async {
        guard !isFinished else { return }

        // Cancel existing session and wait for cleanup
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        silenceTimer?.cancel()

        // Reset state for new session
        lastPartialText = ""
        lastCommittedText = ""  // Clear since this is a fresh session
        lastText = ""
        hasSpeech = false
        isRestartingSession = false

        // Create new recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        if #available(macOS 10.15, *) {
            request.requiresOnDeviceRecognition = useOnDevice && recognizer.supportsOnDeviceRecognition
        }

        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }

        self.recognitionRequest = request

        // Start recognition task
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task {
                await self?.handleRecognitionResult(result: result, error: error)
            }
        }

        self.recognitionTask = task
        print("[AppleSpeech] New session started")
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            let nsError = error as NSError
            print("[AppleSpeech] Error: domain=\(nsError.domain) code=\(nsError.code)")

            // Ignore certain errors
            if nsError.domain == "kAFAssistantErrorDomain" {
                if nsError.code == 216 || nsError.code == 1110 {
                    // Cancelled or no speech - not a real error
                    return
                }
            }
            return
        }

        guard let result = result else { return }

        let text = result.bestTranscription.formattedString

        if result.isFinal {
            // Only emit if we have text that wasn't already emitted by silence timeout
            let finalText = text.isEmpty ? lastText : text
            let alreadyCommitted = !lastCommittedText.isEmpty && finalText == lastCommittedText
            if !finalText.isEmpty && hasSpeech && !alreadyCommitted {
                print("[AppleSpeech] Final result (Apple VAD): \(finalText)")
                eventContinuation.yield(.final(text: finalText))
            }
            // Reset state
            lastText = ""
            lastPartialText = ""
            lastCommittedText = ""
            hasSpeech = false
            // Start new session for continuous recognition (if not already restarting)
            guard !isRestartingSession else { return }
            isRestartingSession = true
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
                guard !isFinished else { return }
                await startNewSession()
                isRestartingSession = false
            }
        } else if !text.isEmpty && text != lastPartialText {
            // Check if this is truly new text (not something we already committed)
            let isAlreadyCommitted = !lastCommittedText.isEmpty &&
                (text == lastCommittedText || text.hasPrefix(lastCommittedText) || lastCommittedText.hasPrefix(text))

            if isAlreadyCommitted {
                // Skip - this is just Apple re-sending old text
                lastPartialText = text
                return
            }

            // New partial result - update state and restart timer
            lastText = text
            lastPartialText = text
            hasSpeech = true
            lastSpeechTime = Date()

            // Clear lastCommittedText since we have genuinely new content
            lastCommittedText = ""

            // Restart silence timer only when we get NEW text
            restartSilenceTimer()

            print("[AppleSpeech] Partial: \(text)")
            eventContinuation.yield(.partial(text: text, stash: ""))
        }
    }

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(silenceTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.onSilenceTimeout()
        }
    }

    private func onSilenceTimeout() {
        guard hasSpeech, !lastText.isEmpty else { return }

        print("[AppleSpeech] Auto-commit: \(lastText)")

        // Emit final result
        eventContinuation.yield(.final(text: lastText))

        // Remember what we committed to avoid duplicate commits
        lastCommittedText = lastText

        // Reset state
        lastText = ""
        lastPartialText = ""
        hasSpeech = false

        // End current session and start fresh
        guard !isRestartingSession else { return }
        isRestartingSession = true

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay for cleanup
            guard !isFinished else { return }
            await startNewSession()
            isRestartingSession = false
        }
    }

    func appendAudio(_ pcmData: Data) {
        guard let request = recognitionRequest else { return }

        // Convert PCM Int16 to Float32 for Apple Speech
        let int16Samples = pcmData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Int16.self))
        }

        let floatSamples = int16Samples.map { Float($0) / 32768.0 }

        // Note: Silence detection is now based on Apple's partial results, not audio level
        // Timer is restarted in handleRecognitionResult when new partial arrives

        // Create audio buffer
        let frameCount = AVAudioFrameCount(floatSamples.count)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            for (index, sample) in floatSamples.enumerated() {
                channelData[index] = sample
            }
        }

        request.append(buffer)
    }

    func commit() {
        silenceTimer?.cancel()

        // Always emit final to ensure state machine proceeds
        // If we have new text, emit it; otherwise emit empty string for cleanup
        let textToEmit = (hasSpeech && !lastText.isEmpty) ? lastText : ""
        if !textToEmit.isEmpty {
            print("[AppleSpeech] Commit with text: \(textToEmit)")
        }
        eventContinuation.yield(.final(text: textToEmit))

        // Clean up
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isFinished = true
        eventContinuation.finish()
    }

    func cancel() {
        silenceTimer?.cancel()
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isRestartingSession = false
        isFinished = true
        eventContinuation.finish()
    }
}

// MARK: - Permission Helper

enum AppleSpeechPermission {
    static func checkAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func isAvailable(for locale: Locale = Locale(identifier: "zh-CN")) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return false
        }
        return recognizer.isAvailable
    }

    static func supportsOnDevice(for locale: Locale = Locale(identifier: "zh-CN")) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return false
        }
        if #available(macOS 10.15, *) {
            return recognizer.supportsOnDeviceRecognition
        }
        return false
    }
}
