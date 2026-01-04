//
//  AudioRecorder.swift
//  VhisperNative
//
//  Audio recording using AVAudioEngine with resampling to 16kHz
//

import AVFoundation
import Accelerate

actor AudioRecorder {
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var isRecording = false

    // Target sample rate for ASR (Whisper standard)
    static let targetSampleRate: Double = 16000
    static let channels: AVAudioChannelCount = 1

    // Resampling state
    private var resampleAccumulator: Double = 0

    // MARK: - Public API

    func start() throws {
        guard !isRecording else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let sourceSampleRate = inputFormat.sampleRate
        let sourceChannels = inputFormat.channelCount

        // Calculate resample ratio
        let resampleRatio = sourceSampleRate / Self.targetSampleRate
        resampleAccumulator = 0
        audioBuffer.removeAll()

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            Task { [weak self] in
                await self?.processBuffer(
                    buffer,
                    resampleRatio: resampleRatio,
                    sourceChannels: Int(sourceChannels)
                )
            }
        }

        try audioEngine.start()
        isRecording = true
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false

        let result = audioBuffer
        audioBuffer.removeAll()
        resampleAccumulator = 0
        return result
    }

    /// Drain buffer without stopping (for streaming mode)
    func drainBuffer() -> [Float] {
        let result = audioBuffer
        audioBuffer.removeAll()
        return result
    }

    func cancel() {
        if isRecording {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            isRecording = false
        }
        audioBuffer.removeAll()
        resampleAccumulator = 0
    }

    var recordingState: Bool {
        isRecording
    }

    // MARK: - Private

    private func processBuffer(_ buffer: AVAudioPCMBuffer, resampleRatio: Double, sourceChannels: Int) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)

        for frame in 0..<frameLength {
            // Mix channels to mono
            var mono: Float = 0
            for channel in 0..<sourceChannels {
                mono += channelData[channel][frame]
            }
            mono /= Float(sourceChannels)

            // Resample using accumulator (precise linear interpolation)
            resampleAccumulator += 1.0 / resampleRatio
            while resampleAccumulator >= 1.0 {
                audioBuffer.append(mono)
                resampleAccumulator -= 1.0
            }
        }
    }
}

// MARK: - Audio Encoder

struct AudioEncoder {
    /// Encode float samples to 16-bit PCM
    static func encodeToPCM(_ samples: [Float]) -> Data {
        var pcmData = Data(capacity: samples.count * 2)

        for sample in samples {
            // Clamp to [-1.0, 1.0] and convert to Int16
            let clamped = max(-1.0, min(1.0, sample))
            let amplitude = Int16(clamped * Float(Int16.max))

            // Little-endian
            var le = amplitude.littleEndian
            withUnsafeBytes(of: &le) { pcmData.append(contentsOf: $0) }
        }

        return pcmData
    }

    /// Encode float samples to WAV format (for OpenAI Whisper)
    static func encodeToWAV(_ samples: [Float], sampleRate: UInt32 = 16000) -> Data {
        let pcmData = encodeToPCM(samples)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var wavData = Data()

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        var fileSize = UInt32(36 + pcmData.count).littleEndian
        withUnsafeBytes(of: &fileSize) { wavData.append(contentsOf: $0) }
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        var fmtSize = UInt32(16).littleEndian
        withUnsafeBytes(of: &fmtSize) { wavData.append(contentsOf: $0) }
        var audioFormat = UInt16(1).littleEndian  // PCM
        withUnsafeBytes(of: &audioFormat) { wavData.append(contentsOf: $0) }
        var numChannels = channels.littleEndian
        withUnsafeBytes(of: &numChannels) { wavData.append(contentsOf: $0) }
        var sampleRateLE = sampleRate.littleEndian
        withUnsafeBytes(of: &sampleRateLE) { wavData.append(contentsOf: $0) }
        var byteRateLE = byteRate.littleEndian
        withUnsafeBytes(of: &byteRateLE) { wavData.append(contentsOf: $0) }
        var blockAlignLE = blockAlign.littleEndian
        withUnsafeBytes(of: &blockAlignLE) { wavData.append(contentsOf: $0) }
        var bitsPerSampleLE = bitsPerSample.littleEndian
        withUnsafeBytes(of: &bitsPerSampleLE) { wavData.append(contentsOf: $0) }

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        var dataSize = UInt32(pcmData.count).littleEndian
        withUnsafeBytes(of: &dataSize) { wavData.append(contentsOf: $0) }
        wavData.append(pcmData)

        return wavData
    }

    /// Check audio quality
    static func checkAudioQuality(_ samples: [Float]) -> AudioQualityResult {
        guard !samples.isEmpty else {
            return .error("No audio data")
        }

        let maxAmplitude = samples.map { abs($0) }.max() ?? 0

        if maxAmplitude < 0.001 {
            return .error("Audio is silent. Please check microphone permissions.")
        } else if maxAmplitude < 0.05 {
            return .warning("Audio level is very low. Please speak louder or check microphone.")
        }

        return .ok
    }

    enum AudioQualityResult {
        case ok
        case warning(String)
        case error(String)
    }
}
