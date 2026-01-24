//
//  VoicePipeline.swift
//  VhisperNative
//
//  Voice processing pipeline: Recording -> ASR -> LLM -> Output
//

import Foundation

/// Pipeline state
enum PipelineState: Int, Sendable {
    case idle = 0
    case recording = 1
    case processing = 2
}

/// Voice processing pipeline
actor VoicePipeline {
    private let audioRecorder = AudioRecorder()
    private var asrService: (any StreamingASRService)?
    private var llmService: (any LLMService)?
    private var vocabularyProcessor: VocabularyProcessor?
    private var config: AppConfig

    private var currentState: PipelineState = .idle

    // Streaming session
    private var streamingControl: (@Sendable (StreamingControl) async -> Void)?
    private var streamingTask: Task<Void, Never>?
    private var eventProcessingTask: Task<Void, Never>?

    // Voiceprint filtering
    private var voiceprintBuffer: [Float] = []
    private var isVoiceprintVerified = false
    private let voiceprintChunkSize = 32000  // 2 seconds at 16kHz (FluidAudio needs longer audio)

    // Event callback
    private var onEvent: (@Sendable (PipelineEvent) -> Void)?

    init(config: AppConfig) {
        self.config = config
        Task { await setupServices() }
    }

    // MARK: - Configuration

    func setEventHandler(_ handler: @escaping @Sendable (PipelineEvent) -> Void) {
        self.onEvent = handler
    }

    func updateConfig(_ config: AppConfig) {
        self.config = config
        setupServices()
    }

    private func setupServices() {
        // Create ASR service
        if let streaming = ASRFactory.createStreaming(config: config.asr) {
            asrService = streaming
        }

        // Create vocabulary processor
        vocabularyProcessor = VocabularyProcessor(config: config.vocabulary)

        // Create LLM service with vocabulary context
        let asrApiKey: String?
        switch config.asr.provider {
        case .qwen:
            asrApiKey = config.asr.qwen?.apiKey
        case .dashscope:
            asrApiKey = config.asr.dashscope?.apiKey
        default:
            asrApiKey = nil
        }
        let vocabularyContext = config.vocabulary.llmContextString
        llmService = LLMFactory.create(config: config.llm, vocabularyContext: vocabularyContext, asrApiKey: asrApiKey)
    }

    // MARK: - Recording Control

    var state: PipelineState {
        currentState
    }

    func startRecording() async throws {
        guard currentState == .idle else {
            throw PipelineError.invalidState("Cannot start recording in state: \(currentState)")
        }

        guard let asr = asrService else {
            throw PipelineError.notConfigured("ASR service not configured")
        }

        currentState = .recording

        // Reset voiceprint state
        voiceprintBuffer = []
        isVoiceprintVerified = false

        // Start audio recorder
        try await audioRecorder.start()

        // Start streaming ASR
        let (control, events) = try await asr.startStreaming(sampleRate: UInt32(AudioRecorder.targetSampleRate))
        streamingControl = control

        // Capture config for use in task
        let voiceprintEnabled = config.voiceprint.enabled
        let chunkSize = voiceprintChunkSize

        // Start audio streaming task with voiceprint filtering
        streamingTask = Task {
            while await audioRecorder.recordingState {
                let samples = await audioRecorder.drainBuffer()
                if !samples.isEmpty {
                    // Apply voiceprint filtering if enabled
                    let filteredSamples = await filterWithVoiceprint(
                        samples: samples,
                        enabled: voiceprintEnabled,
                        chunkSize: chunkSize
                    )

                    if !filteredSamples.isEmpty {
                        let pcmData = AudioEncoder.encodeToPCM(filteredSamples)
                        await control(.audio(pcmData))
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            }
        }

        // Cancel any existing event processing task
        eventProcessingTask?.cancel()

        // Process ASR events with proper lifecycle management
        eventProcessingTask = Task {
            for await event in events {
                guard !Task.isCancelled else { break }
                await handleASREvent(event)
            }
        }

        onEvent?(.recordingStarted)
    }

    func stopRecording() async throws {
        guard currentState == .recording else { return }

        currentState = .processing
        onEvent?(.recordingStopped)

        // Stop audio recorder
        let samples = await audioRecorder.stop()

        // Check audio quality (only warn, don't block - audio was already streamed)
        switch AudioEncoder.checkAudioQuality(samples) {
        case .error(let msg), .warning(let msg):
            onEvent?(.warning(msg))
        case .ok:
            break
        }

        // Send remaining audio and commit
        if !samples.isEmpty {
            let pcmData = AudioEncoder.encodeToPCM(samples)
            await streamingControl?(.audio(pcmData))
        }
        await streamingControl?(.commit)

        // Cancel streaming task
        streamingTask?.cancel()
        streamingTask = nil
    }

    func cancel() async {
        await audioRecorder.cancel()
        await streamingControl?(.cancel)

        // Cancel all running tasks
        streamingTask?.cancel()
        eventProcessingTask?.cancel()

        // Clean up
        streamingTask = nil
        eventProcessingTask = nil
        streamingControl = nil
        currentState = .idle
        onEvent?(.cancelled)
    }

    // MARK: - Voiceprint Filtering

    /// Filter audio samples with voiceprint verification
    private func filterWithVoiceprint(samples: [Float], enabled: Bool, chunkSize: Int) async -> [Float] {
        // If voiceprint filtering is disabled, pass through all samples
        guard enabled else {
            return samples
        }

        // Check if voiceprint is registered
        let hasVoiceprint = await VoiceprintManager.shared.hasVoiceprint
        guard hasVoiceprint else {
            // No voiceprint registered, pass through
            return samples
        }

        // Add samples to buffer
        voiceprintBuffer.append(contentsOf: samples)

        // If already verified for this session, pass through
        if isVoiceprintVerified {
            return samples
        }

        // Need enough samples for verification
        guard voiceprintBuffer.count >= chunkSize else {
            // Not enough samples yet, buffer but don't send
            return []
        }

        // Verify the buffered audio
        let isMatch = await VoiceprintManager.shared.isMatch(samples: voiceprintBuffer)

        if isMatch {
            // Voiceprint matched! Send all buffered audio and mark as verified
            isVoiceprintVerified = true
            let bufferedSamples = voiceprintBuffer
            voiceprintBuffer = []
            onEvent?(.voiceprintVerified)
            return bufferedSamples
        } else {
            // Not a match, clear buffer and continue listening
            voiceprintBuffer = []
            onEvent?(.voiceprintRejected)
            return []
        }
    }

    // MARK: - ASR Event Handling

    private func handleASREvent(_ event: StreamingASREvent) async {
        switch event {
        case .partial(let text, let stash):
            onEvent?(.partialResult(text: text, stash: stash))

        case .final(let text):
            var finalText = text

            // Apply post-ASR vocabulary replacement
            if let processor = vocabularyProcessor, config.vocabulary.enabled && config.vocabulary.enablePostASRReplacement {
                finalText = processor.process(finalText)
            }

            // Apply LLM refinement if enabled
            if let llm = llmService, !finalText.isEmpty {
                do {
                    finalText = try await llm.refineText(finalText)
                } catch {
                    // LLM failed, use text after vocabulary processing
                    onEvent?(.warning("LLM refinement failed: \(error.localizedDescription)"))
                }
            }

            // Reset state if hotkey is not pressed
            if !HotkeyManager.shared.isHotkeyPressed {
                currentState = .idle
            }

            onEvent?(.finalResult(text: finalText))

        case .error(let msg):
            currentState = .idle
            if !msg.lowercased().contains("cancel") {
                onEvent?(.error(msg))
            }
        }
    }
}

// MARK: - Pipeline Events

enum PipelineEvent {
    case recordingStarted
    case recordingStopped
    case partialResult(text: String, stash: String)
    case finalResult(text: String)
    case warning(String)
    case error(String)
    case cancelled
    case voiceprintVerified    // Voiceprint matched, audio will be transcribed
    case voiceprintRejected    // Voiceprint not matched, audio discarded
}

// MARK: - Pipeline Errors

enum PipelineError: Error, LocalizedError {
    case invalidState(String)
    case notConfigured(String)
    case audioError(String)

    var errorDescription: String? {
        switch self {
        case .invalidState(let msg): return "Invalid state: \(msg)"
        case .notConfigured(let msg): return "Not configured: \(msg)"
        case .audioError(let msg): return "Audio error: \(msg)"
        }
    }
}
