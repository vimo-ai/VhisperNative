//
//  VhisperManager.swift
//  VhisperNative
//
//  Core state manager for the application
//

import SwiftUI
import Combine

/// Application version
let appVersion = "1.0.2"

@MainActor
class VhisperManager: ObservableObject {
    static let shared = VhisperManager()

    // MARK: - Published State

    @Published var state: VhisperState = .idle
    @Published var lastResult: String = ""
    @Published var errorMessage: String?
    @Published var config: AppConfig = .default

    // MARK: - Private

    private var pipeline: VoicePipeline?
    private var streamingText: String = ""
    private var processingTimeoutTask: Task<Void, Never>?

    enum VhisperState {
        case idle
        case recording
        case processing

        var description: String {
            switch self {
            case .idle: return "Ready"
            case .recording: return "Recording..."
            case .processing: return "Processing..."
            }
        }

        var icon: String {
            switch self {
            case .idle: return "mic"
            case .recording: return "mic.fill"
            case .processing: return "ellipsis.circle"
            }
        }
    }

    private init() {}

    // MARK: - Configuration

    func loadConfiguration() {
        Task {
            // Try to migrate from UserDefaults first
            if let migrated = await ConfigStorage.shared.migrateFromUserDefaults() {
                self.config = migrated
            } else {
                self.config = await ConfigStorage.shared.load()
            }

            initializePipeline()
        }
    }

    func saveConfiguration() {
        Task {
            do {
                try await ConfigStorage.shared.save(config)
                initializePipeline()
            } catch {
                errorMessage = "Failed to save configuration: \(error.localizedDescription)"
            }
        }
    }

    private func initializePipeline() {
        pipeline = VoicePipeline(config: config)

        Task {
            await pipeline?.updateConfig(config)
            await setupPipelineCallbacks()
        }
    }

    private func setupPipelineCallbacks() async {
        await pipeline?.setEventHandler { [weak self] event in
            Task { @MainActor in
                self?.handlePipelineEvent(event)
            }
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        guard pipeline != nil else {
            errorMessage = NSLocalizedString("error.no_api_key", comment: "No API key configured")
            return
        }

        // Check microphone permission before starting
        guard PermissionManager.shared.microphoneStatus == .granted else {
            errorMessage = NSLocalizedString("error.microphone_denied", comment: "Microphone permission denied")
            return
        }

        // Force cleanup if in bad state
        if state != .idle {
            Task {
                await pipeline?.cancel()
            }
            forceCleanup()
        }

        guard state == .idle else { return }

        streamingText = ""

        // Start audio level monitoring and show waveform
        AudioLevelMonitor.shared.startMonitoring()
        WaveformOverlayController.shared.show(with: AudioLevelMonitor.shared)

        // Start usage tracking
        UsageTracker.shared.startSession(provider: config.asr.provider.rawValue)

        Task {
            do {
                try await pipeline?.startRecording()
                state = .recording
                errorMessage = nil
                updateAppDelegateIcon(recording: true)
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                WaveformOverlayController.shared.hide()
                AudioLevelMonitor.shared.stopMonitoring()
                UsageTracker.shared.cancelSession()
            }
        }
    }

    func stopRecording() {
        guard state == .recording else { return }

        state = .processing
        updateAppDelegateIcon(recording: false)

        Task {
            do {
                try await pipeline?.stopRecording()
            } catch {
                forceCleanup()
                errorMessage = error.localizedDescription
            }
        }

        // Cancel any existing timeout task
        processingTimeoutTask?.cancel()

        // Timeout protection: force cleanup after 3 seconds
        processingTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            if self.state == .processing {
                self.forceCleanup()
            }
        }
    }

    func cancel() {
        Task {
            await pipeline?.cancel()
        }
        forceCleanup()
    }

    func toggleRecording() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            cancel()
        }
    }

    private func forceCleanup() {
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil
        state = .idle
        updateAppDelegateIcon(recording: false)
        WaveformOverlayController.shared.hide()
        AudioLevelMonitor.shared.stopMonitoring()
    }

    // MARK: - Pipeline Event Handling

    private func handlePipelineEvent(_ event: PipelineEvent) {
        switch event {
        case .recordingStarted:
            state = .recording

        case .recordingStopped:
            state = .processing

        case .partialResult(let text, let stash):
            WaveformOverlayController.shared.updateText(text: text, stash: stash)
            streamingText = text + stash

        case .finalResult(let text):
            // Cancel the processing timeout since we got a result
            processingTimeoutTask?.cancel()
            processingTimeoutTask = nil

            // End usage tracking session
            UsageTracker.shared.endSession()

            var finalText = text

            // Remove trailing punctuation if enabled
            if config.output.removeTrailingPunctuation {
                let punctuationSet = Set(config.output.punctuationToRemove)
                while let lastChar = finalText.last, punctuationSet.contains(lastChar) {
                    finalText.removeLast()
                }
            }

            // Remove filler words if enabled
            if config.output.removeFillerWords && !config.output.fillerWordsToRemove.isEmpty {
                // Build regex pattern for all filler words at once (more efficient than multiple replacingOccurrences)
                let escapedWords = config.output.fillerWordsToRemove.map { NSRegularExpression.escapedPattern(for: $0) }
                let pattern = escapedWords.joined(separator: "|")
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    finalText = regex.stringByReplacingMatches(
                        in: finalText,
                        range: NSRange(finalText.startIndex..., in: finalText),
                        withTemplate: ""
                    )
                }
                // Clean up multiple spaces with single regex pass
                if let spaceRegex = try? NSRegularExpression(pattern: "  +", options: []) {
                    finalText = spaceRegex.stringByReplacingMatches(
                        in: finalText,
                        range: NSRange(finalText.startIndex..., in: finalText),
                        withTemplate: " "
                    )
                }
                finalText = finalText.trimmingCharacters(in: .whitespaces)
            }

            // Output text or show warning for empty result
            if !finalText.isEmpty {
                lastResult = finalText
                errorMessage = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    TextOutputService.shared.outputText(
                        finalText,
                        restoreClipboard: self.config.output.restoreClipboard,
                        pasteDelay: self.config.output.pasteDelayMs
                    )
                }
            } else if lastResult.isEmpty {
                // Only show error if we never got any result in this session
                errorMessage = NSLocalizedString("error.empty_transcription", comment: "Recording too short or no speech detected")
            }
            // If finalText is empty but lastResult has content, it's just a cleanup final after silence timeout

            // Clear waveform text
            WaveformOverlayController.shared.clearText()

            // Check if hotkey is still pressed
            if HotkeyManager.shared.isHotkeyPressed {
                // VAD final, keep recording state
            } else {
                // Hotkey released, end session
                state = .idle
                updateAppDelegateIcon(recording: false)
                WaveformOverlayController.shared.hide()
                AudioLevelMonitor.shared.stopMonitoring()
            }

        case .warning(let msg):
            print("Warning: \(msg)")

        case .error(let msg):
            state = .idle
            errorMessage = msg
            updateAppDelegateIcon(recording: false)
            WaveformOverlayController.shared.hide()
            AudioLevelMonitor.shared.stopMonitoring()
            UsageTracker.shared.cancelSession()

        case .cancelled:
            UsageTracker.shared.cancelSession()
            forceCleanup()

        case .voiceprintVerified:
            // Voiceprint matched, audio will be transcribed
            print("[Voiceprint] Verified - audio accepted")

        case .voiceprintRejected:
            // Voiceprint not matched, audio discarded
            print("[Voiceprint] Rejected - audio discarded")
        }
    }

    // MARK: - Helpers

    private func updateAppDelegateIcon(recording: Bool) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateStatusIcon(isRecording: recording)
        }
    }
}
