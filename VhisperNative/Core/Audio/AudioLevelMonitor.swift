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

    private let audioEngine = AVAudioEngine()
    private let numberOfBands = 20

    // FFT
    private let fftSize = 1024
    private var fftSetup: FFTSetup?
    private var log2n: vDSP_Length = 0

    // Smoothing
    private var smoothedLevels: [Float] = Array(repeating: 0.0, count: 20)
    private let smoothingFactor: Float = 0.3

    // Wave animation - independent target and current heights for each bar
    private var targetHeights: [Float] = Array(repeating: 0.0, count: 20)
    private var currentHeights: [Float] = Array(repeating: 0.0, count: 20)
    private var updateCounter: Int = 0

    private init() {
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
        guard isMonitoring else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
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
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: format) { [weak self] buffer, _ in
            self?.processFFT(buffer)
        }

        try audioEngine.start()
    }

    private func processFFT(_ buffer: AVAudioPCMBuffer) {
        guard let fftSetup = fftSetup,
              let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength >= fftSize else { return }

        let samples = channelData[0]

        // Apply Hanning window
        var windowedSamples = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        // Prepare split complex format
        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)

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

                // Calculate magnitudes
                var magnitudes = [Float](repeating: 0, count: fftSize / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

                // Convert to dB and normalize
                var normalizedMagnitudes = [Float](repeating: 0, count: fftSize / 2)
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
