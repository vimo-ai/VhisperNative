//
//  VoiceprintSettingsView.swift
//  VhisperNative
//
//  Voiceprint registration and settings UI
//

import SwiftUI
import AVFoundation

struct VoiceprintSettingsContent: View {
    @EnvironmentObject var manager: VhisperManager

    @State private var isRecording = false
    @State private var recordingProgress: Double = 0
    @State private var hasVoiceprint = false
    @State private var embeddingDimension: Int?
    @State private var statusMessage = ""
    @State private var isInitializing = false
    @State private var recordedSamples: [Float] = []
    @State private var recorder: VoiceprintRecorder?

    // Recording settings
    private let requiredDuration: Double = 3.0  // 3 seconds minimum
    private let maxDuration: Double = 10.0      // 10 seconds max

    var body: some View {
        Form {
            // Enable/Disable Section
            Section {
                Toggle(isOn: Binding(
                    get: { manager.config.voiceprint.enabled },
                    set: { newValue in
                        manager.config.voiceprint.enabled = newValue
                        if newValue {
                            initializeIfNeeded()
                        }
                        manager.saveConfiguration()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.voiceprint.enable")
                        Text("settings.voiceprint.enable.description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("settings.voiceprint.title", systemImage: "waveform.circle")
            }

            // Registration Section
            if manager.config.voiceprint.enabled {
                Section {
                    // Status
                    HStack {
                        if hasVoiceprint {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("settings.voiceprint.registered")
                                if let dim = embeddingDimension {
                                    Text("\(dim)-dim embedding")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .foregroundColor(.orange)
                            Text("settings.voiceprint.not_registered")
                        }
                        Spacer()
                    }

                    // Recording UI
                    if isRecording {
                        VStack(spacing: 8) {
                            ProgressView(value: recordingProgress, total: requiredDuration)
                                .progressViewStyle(.linear)

                            HStack {
                                Image(systemName: "mic.fill")
                                    .foregroundColor(.red)
                                    .symbolEffect(.pulse)
                                Text("settings.voiceprint.recording")
                                Spacer()
                                Text(String(format: "%.1fs", recordingProgress))
                                    .monospacedDigit()
                            }
                            .font(.caption)

                            Button(action: stopRecording) {
                                Label("settings.voiceprint.stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    } else {
                        HStack {
                            Button(action: startRecording) {
                                Label(
                                    hasVoiceprint ? "settings.voiceprint.re_register" : "settings.voiceprint.register",
                                    systemImage: "mic.badge.plus"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInitializing)

                            if hasVoiceprint {
                                Button(role: .destructive, action: clearVoiceprint) {
                                    Label("settings.voiceprint.clear", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    // Status message
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("settings.voiceprint.registration")
                } footer: {
                    Text("settings.voiceprint.registration.footer")
                }

                // Threshold Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("settings.voiceprint.threshold")
                            Spacer()
                            Text(String(format: "%.0f%%", manager.config.voiceprint.threshold * 100))
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { manager.config.voiceprint.threshold },
                                set: { newValue in
                                    manager.config.voiceprint.threshold = newValue
                                    Task {
                                        await VoiceprintManager.shared.threshold = newValue
                                    }
                                    manager.saveConfiguration()
                                }
                            ),
                            in: 0.2...0.9,
                            step: 0.05
                        ) {
                            Text("Threshold")
                        }

                        HStack {
                            Text("settings.voiceprint.threshold.loose")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("settings.voiceprint.threshold.strict")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("settings.voiceprint.sensitivity")
                } footer: {
                    Text("settings.voiceprint.sensitivity.footer")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshStatus()
            if manager.config.voiceprint.enabled {
                initializeIfNeeded()
            }
        }
    }

    // MARK: - Actions

    private func initializeIfNeeded() {
        guard !isInitializing else { return }
        isInitializing = true
        statusMessage = NSLocalizedString("settings.voiceprint.initializing", comment: "")

        Task {
            do {
                try await VoiceprintManager.shared.initialize()
                await MainActor.run {
                    isInitializing = false
                    statusMessage = ""
                    refreshStatus()
                }
            } catch {
                await MainActor.run {
                    isInitializing = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func refreshStatus() {
        Task {
            let manager = VoiceprintManager.shared
            let hasVP = await manager.hasVoiceprint
            let dimension = await manager.embeddingDimension

            await MainActor.run {
                hasVoiceprint = hasVP
                embeddingDimension = dimension
            }
        }
    }

    private func startRecording() {
        guard !isRecording else { return }

        isRecording = true
        recordingProgress = 0
        recordedSamples = []
        statusMessage = NSLocalizedString("settings.voiceprint.speak_now", comment: "")

        // Start recording
        Task {
            let newRecorder = VoiceprintRecorder()
            recorder = newRecorder
            do {
                try await newRecorder.start()

                // Update progress
                while isRecording && recordingProgress < maxDuration {
                    try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                    let samples = await newRecorder.drainBuffer()
                    recordedSamples.append(contentsOf: samples)

                    await MainActor.run {
                        recordingProgress = Double(recordedSamples.count) / 16000.0
                    }

                    // Auto-stop at max duration
                    if recordingProgress >= maxDuration {
                        await MainActor.run {
                            stopRecording()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isRecording = false
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        // Stop recorder
        Task {
            _ = await recorder?.stop()
        }

        // Check minimum duration
        let duration = Double(recordedSamples.count) / 16000.0
        if duration < requiredDuration {
            statusMessage = String(format: NSLocalizedString("settings.voiceprint.too_short", comment: ""), requiredDuration)
            return
        }

        // Register voiceprint
        Task {
            do {
                try await VoiceprintManager.shared.registerVoiceprint(samples: recordedSamples)
                await MainActor.run {
                    statusMessage = NSLocalizedString("settings.voiceprint.registered_success", comment: "")
                    refreshStatus()
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func clearVoiceprint() {
        Task {
            await VoiceprintManager.shared.clearVoiceprint()
            await MainActor.run {
                hasVoiceprint = false
                embeddingDimension = nil
                statusMessage = NSLocalizedString("settings.voiceprint.cleared", comment: "")
            }
        }
    }
}

// MARK: - Simple Recorder for Registration

actor VoiceprintRecorder {
    private var audioEngine: AVAudioEngine?
    private var buffer: [Float] = []
    private var isRecording = false
    private var resampleAccumulator: Double = 0

    func start() throws {
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let sourceSampleRate = format.sampleRate
        let resampleRatio = sourceSampleRate / 16000.0

        resampleAccumulator = 0

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] pcmBuffer, _ in
            guard let self = self, let channelData = pcmBuffer.floatChannelData else { return }
            let frameLength = Int(pcmBuffer.frameLength)

            Task {
                await self.processBuffer(channelData: channelData, frameLength: frameLength, resampleRatio: resampleRatio)
            }
        }

        try engine.start()
        isRecording = true
    }

    func stop() -> [Float] {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        isRecording = false
        return buffer
    }

    func drainBuffer() -> [Float] {
        let result = buffer
        buffer = []
        return result
    }

    private func processBuffer(channelData: UnsafePointer<UnsafeMutablePointer<Float>>, frameLength: Int, resampleRatio: Double) {
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            resampleAccumulator += 1.0 / resampleRatio
            while resampleAccumulator >= 1.0 {
                buffer.append(sample)
                resampleAccumulator -= 1.0
            }
        }
    }
}

