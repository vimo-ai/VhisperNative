//
//  AudioLevelMonitor.swift
//  VhisperNative
//
//  Real-time audio spectrum analyzer using AVAudioEngine + Accelerate FFT
//

import AVFoundation
import Accelerate
import Combine

/// Audio spectrum monitor with FFT analysis
class AudioLevelMonitor: ObservableObject {
    static let shared = AudioLevelMonitor()

    // MARK: - Published Properties

    /// Spectrum data (20 bands, range 0-1)
    @Published var levels: [Float] = Array(repeating: 0.0, count: 20)

    /// Current peak level
    @Published var peakLevel: Float = 0.0

    /// Is monitoring active
    @Published var isMonitoring: Bool = false

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private let numberOfBands = 20

    // FFT
    private let fftSize = 1024
    private var fftSetup: FFTSetup?
    private var log2n: vDSP_Length = 0

    // Pre-allocated FFT buffers (performance optimization)
    private var windowedSamples: [Float]
    private var window: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]
    private var normalizedMagnitudes: [Float]

    // UI update throttling
    private var lastUIUpdate: Date = .distantPast
    private let uiUpdateInterval: TimeInterval = 0.033 // ~30fps

    // Smoothing
    private var smoothedLevels: [Float] = Array(repeating: 0.0, count: 20)
    private let smoothingFactor: Float = 0.3

    // Wave animation - independent target and current heights for each bar
    private var targetHeights: [Float] = Array(repeating: 0.0, count: 20)
    private var currentHeights: [Float] = Array(repeating: 0.0, count: 20)
    private var updateCounter: Int = 0

    private init() {
        // Pre-allocate all FFT buffers
        windowedSamples = [Float](repeating: 0, count: fftSize)
        window = [Float](repeating: 0, count: fftSize)
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
        normalizedMagnitudes = [Float](repeating: 0, count: fftSize / 2)

        // Pre-compute Hanning window (only needs to be done once)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        setupFFT()
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - FFT Setup

    private func setupFFT() {
        log2n = vDSP_Length(log2(Float(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    // MARK: - Public Methods

    func startMonitoring() {
        guard !isMonitoring else { return }

        do {
            try setupAudioEngine()
            isMonitoring = true
        } catch {
            print("Failed to start audio monitoring: \(error)")
        }
    }

    func stopMonitoring() {
        guard isMonitoring, let engine = audioEngine else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioEngine = nil
        isMonitoring = false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.levels = Array(repeating: 0.0, count: self.numberOfBands)
            self.smoothedLevels = Array(repeating: 0.0, count: self.numberOfBands)
            self.peakLevel = 0.0
        }
    }

    // MARK: - Private Methods

    private func setupAudioEngine() throws {
        // Create fresh audio engine for each monitoring session
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Validate format
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioLevelMonitor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"])
        }

        inputNode.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: format) { [weak self] buffer, _ in
            self?.processFFT(buffer)
        }

        try engine.start()
    }

    private func processFFT(_ buffer: AVAudioPCMBuffer) {
        guard let fftSetup = fftSetup,
              let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength >= fftSize else { return }

        // Throttle UI updates
        let now = Date()
        guard now.timeIntervalSince(lastUIUpdate) >= uiUpdateInterval else { return }
        lastUIUpdate = now

        let samples = channelData[0]

        // Apply Hanning window using pre-allocated buffers
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        // Prepare split complex format using pre-allocated buffers
        realp.withUnsafeMutableBufferPointer { realBP in
            imagp.withUnsafeMutableBufferPointer { imagBP in
                var splitComplex = DSPSplitComplex(realp: realBP.baseAddress!, imagp: imagBP.baseAddress!)

                windowedSamples.withUnsafeBufferPointer { samplesPtr in
                    samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }

                // Execute FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Calculate magnitudes using pre-allocated buffer
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

                // Convert to dB and normalize using pre-allocated buffer
                var one: Float = 1.0
                vDSP_vdbcon(magnitudes, 1, &one, &normalizedMagnitudes, 1, vDSP_Length(fftSize / 2), 0)

                // Compute band levels
                let bandLevels = self.computeBandLevels(from: normalizedMagnitudes)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    for i in 0..<self.numberOfBands {
                        self.smoothedLevels[i] = self.smoothedLevels[i] * (1 - self.smoothingFactor) + bandLevels[i] * self.smoothingFactor
                    }

                    self.levels = self.smoothedLevels
                    self.peakLevel = self.smoothedLevels.max() ?? 0
                }
            }
        }
    }

    /// Compute waveform display data with dynamic animation
    private func computeBandLevels(from magnitudes: [Float]) -> [Float] {
        let binCount = magnitudes.count
        let voiceLowBin = 2
        let voiceHighBin = min(64, binCount - 1)

        var sum: Float = 0
        for bin in voiceLowBin...voiceHighBin {
            sum += magnitudes[bin]
        }
        let avgMagnitude = sum / Float(voiceHighBin - voiceLowBin + 1)

        // Normalize volume to 0-1
        let volume = max(0, min(1, (avgMagnitude + 70) / 45))

        let baseHeight: Float = 0.1

        // Update target heights periodically
        updateCounter += 1
        if updateCounter >= 3 {
            updateCounter = 0

            for i in 0..<numberOfBands {
                // Square distribution for more natural feel
                let raw = Float.random(in: 0.0...1.0)
                let randomValue = raw * raw
                targetHeights[i] = baseHeight + volume * randomValue * 0.9
            }
        }

        // Smooth transition to target heights
        let transitionSpeed: Float = 0.3
        for i in 0..<numberOfBands {
            currentHeights[i] += (targetHeights[i] - currentHeights[i]) * transitionSpeed
        }

        return currentHeights
    }
}
