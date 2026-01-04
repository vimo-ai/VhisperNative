//
//  VhisperManager.swift
//  VhisperNative
//
//  Core state manager for the application
//

import SwiftUI
import Combine

/// Application version
let appVersion = "1.0.0"

@MainActor
class VhisperManager: ObservableObject {
    nonisolated(unsafe) static let shared = VhisperManager()

    // MARK: - Published State

    @Published var state: VhisperState = .idle
    @Published var lastResult: String = ""
    @Published var errorMessage: String?
    @Published var config: AppConfig = .default

    // MARK: - Private

    private var pipeline: VoicePipeline?
    private var streamingText: String = ""

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
            errorMessage = "Please configure API Key first"
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

        // Timeout protection: force cleanup after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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
            lastResult = text
            errorMessage = nil

            // Output text
            if !text.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    TextOutputService.shared.outputText(
                        text,
                        restoreClipboard: self.config.output.restoreClipboard,
                        pasteDelay: self.config.output.pasteDelayMs
                    )
                }
            }

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

        case .cancelled:
            forceCleanup()
        }
    }

    // MARK: - Helpers

    private func updateAppDelegateIcon(recording: Bool) {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.updateStatusIcon(isRecording: recording)
        }
    }
}
