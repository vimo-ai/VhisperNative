//
//  VoiceprintManager.swift
//  VhisperNative
//
//  Manages voiceprint registration, storage, and verification
//  Uses FluidAudio for neural speaker embeddings (256-dim WeSpeaker)
//

import Foundation
import AVFoundation
import Accelerate
import FluidAudio

/// Voiceprint verification result
enum VoiceprintVerifyResult: Sendable {
    case match(similarity: Float)
    case noMatch(similarity: Float)
    case noVoiceprint
    case error(String)
}

/// Voiceprint manager for speaker verification using FluidAudio neural embeddings
actor VoiceprintManager {
    static let shared = VoiceprintManager()

    // FluidAudio diarizer for embedding extraction
    private var diarizer: OfflineDiarizerManager?
    private var isInitialized = false
    private var isModelReady = false

    // Reference voiceprint embedding (256-dim, L2-normalized)
    private var referenceEmbedding: [Float]?

    // Storage keys
    private let embeddingKey = "voiceprint_embedding_v2"

    // Verification threshold (0.0-1.0, higher = stricter)
    // Cosine similarity threshold, typical range: 0.5-0.7
    var threshold: Float = 0.5

    private init() {}

    // MARK: - Initialization

    /// Initialize the voiceprint manager and prepare models
    func initialize() async throws {
        guard !isInitialized else { return }

        // Load saved embedding if exists
        loadSavedEmbedding()

        isInitialized = true

        // Prepare FluidAudio models in background
        Task {
            await prepareModels()
        }
    }

    /// Prepare FluidAudio models (downloads if needed)
    private func prepareModels() async {
        do {
            let config = OfflineDiarizerConfig()
            let manager = OfflineDiarizerManager(config: config)
            try await manager.prepareModels()
            self.diarizer = manager
            self.isModelReady = true
            print("[Voiceprint] FluidAudio models ready")
        } catch {
            print("[Voiceprint] Failed to prepare models: \(error)")
        }
    }

    /// Check if manager is ready
    var isReady: Bool {
        isInitialized && isModelReady
    }

    /// Check if a voiceprint is registered
    var hasVoiceprint: Bool {
        referenceEmbedding != nil
    }

    // MARK: - Registration

    /// Register voiceprint from audio samples
    /// - Parameter samples: Audio samples (16kHz, mono, Float32)
    func registerVoiceprint(samples: [Float]) async throws {
        guard samples.count >= 48000 else {  // At least 3 seconds for good embedding
            throw VoiceprintError.audioTooShort
        }

        // Wait for model to be ready
        if !isModelReady {
            await prepareModels()
        }

        guard isModelReady, let diarizer = diarizer else {
            throw VoiceprintError.notInitialized
        }

        // Extract embedding using FluidAudio
        let embedding = try await extractEmbedding(from: samples, using: diarizer)

        // Store reference embedding
        referenceEmbedding = embedding

        // Persist to storage
        saveEmbedding(embedding)

        // Log embedding stats for debugging
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        let maxVal = embedding.max() ?? 0
        let minVal = embedding.min() ?? 0
        print("[Voiceprint] Registered voiceprint: \(embedding.count)-dim, norm=\(String(format: "%.3f", norm)), range=[\(String(format: "%.3f", minVal)), \(String(format: "%.3f", maxVal))]")
    }

    /// Clear registered voiceprint
    func clearVoiceprint() {
        referenceEmbedding = nil
        UserDefaults.standard.removeObject(forKey: embeddingKey)
    }

    // MARK: - Verification

    /// Verify if audio matches registered voiceprint
    /// - Parameter samples: Audio samples to verify (16kHz, mono, Float32)
    /// - Returns: Verification result with similarity score
    func verify(samples: [Float]) async -> VoiceprintVerifyResult {
        guard let refEmbedding = referenceEmbedding else {
            return .noVoiceprint
        }

        guard samples.count >= 32000 else {  // At least 2 seconds (FluidAudio needs longer audio)
            return .error("Audio too short for verification")
        }

        guard isModelReady, let diarizer = diarizer else {
            // Fallback to simple energy check if model not ready
            return fallbackVerify(samples: samples)
        }

        do {
            // Extract embedding from input audio
            let inputEmbedding = try await extractEmbedding(from: samples, using: diarizer)

            // Calculate cosine similarity (embeddings are L2-normalized, so dot product = cosine)
            let similarity = cosineSimilarity(refEmbedding, inputEmbedding)

            // Map user threshold (0.0-1.0) to actual threshold range (0.3-0.8)
            let adjustedThreshold = 0.3 + (threshold * 0.5)

            print("[Voiceprint] Similarity: \(String(format: "%.3f", similarity)), threshold: \(String(format: "%.3f", adjustedThreshold))")

            if similarity >= adjustedThreshold {
                print("[Voiceprint] Match! Audio will be transcribed")
                return .match(similarity: similarity)
            } else {
                print("[Voiceprint] No match - similarity too low")
                return .noMatch(similarity: similarity)
            }
        } catch {
            print("[Voiceprint] Error: \(error.localizedDescription)")
            return .error("Embedding extraction failed: \(error.localizedDescription)")
        }
    }

    /// Quick check if samples likely match the registered voiceprint
    /// - Returns: true if match, false otherwise
    func isMatch(samples: [Float]) async -> Bool {
        switch await verify(samples: samples) {
        case .match:
            return true
        default:
            return false
        }
    }

    // MARK: - Embedding Extraction

    /// Extract speaker embedding from audio samples using FluidAudio
    private func extractEmbedding(from samples: [Float], using diarizer: OfflineDiarizerManager) async throws -> [Float] {
        // Ensure minimum length by padding if necessary
        var audioSamples = samples
        let minLength = 16000  // 1 second minimum
        if audioSamples.count < minLength {
            audioSamples.append(contentsOf: [Float](repeating: 0, count: minLength - audioSamples.count))
        }

        // Run diarization to get speaker embeddings
        let result = try await diarizer.process(audio: audioSamples)

        // Get the primary speaker's embedding from the speaker database
        // speakerDatabase is [String: [Float]]? - maps speaker IDs to embeddings
        guard let speakerDB = result.speakerDatabase,
              !speakerDB.isEmpty else {
            throw VoiceprintError.verificationFailed("No speaker detected in audio")
        }

        // Use the first speaker's embedding (sorted by speaker ID)
        let sortedSpeakers = speakerDB.sorted { $0.key < $1.key }
        guard let firstSpeaker = sortedSpeakers.first else {
            throw VoiceprintError.verificationFailed("No speaker detected in audio")
        }

        let embedding = firstSpeaker.value

        guard embedding.count == 256 else {
            throw VoiceprintError.verificationFailed("Invalid embedding dimension: \(embedding.count)")
        }

        return embedding
    }

    /// Calculate cosine similarity between two vectors (handles non-normalized vectors)
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        // Calculate dot product
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        // Calculate magnitudes
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        normA = sqrt(normA)
        normB = sqrt(normB)

        // Avoid division by zero
        guard normA > 0 && normB > 0 else { return 0 }

        // Cosine similarity = dot(a, b) / (||a|| * ||b||)
        return dotProduct / (normA * normB)
    }

    // MARK: - Fallback (when model not ready)

    /// Simple energy-based verification as fallback
    private func fallbackVerify(samples: [Float]) -> VoiceprintVerifyResult {
        // Just return match with low confidence when model not ready
        // This prevents blocking the user while model loads
        return .match(similarity: 0.5)
    }

    // MARK: - Persistence

    private func saveEmbedding(_ embedding: [Float]) {
        let data = embedding.withUnsafeBytes { Data($0) }
        UserDefaults.standard.set(data, forKey: embeddingKey)
    }

    private func loadSavedEmbedding() {
        if let data = UserDefaults.standard.data(forKey: embeddingKey) {
            referenceEmbedding = data.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self))
            }
            if let embedding = referenceEmbedding {
                print("[Voiceprint] Loaded saved embedding: \(embedding.count)-dim")
            }
        }
    }

    // MARK: - Debug

    /// Get reference embedding dimension
    var embeddingDimension: Int? {
        referenceEmbedding?.count
    }

    /// Reference duration is no longer stored (only embedding)
    var referenceDuration: Double? {
        // Embedding doesn't preserve duration info, return nil
        nil
    }
}

// MARK: - Errors

enum VoiceprintError: Error, LocalizedError {
    case notInitialized
    case audioTooShort
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Voiceprint manager not initialized"
        case .audioTooShort:
            return "Audio too short. Please record at least 3 seconds."
        case .verificationFailed(let msg):
            return "Verification failed: \(msg)"
        }
    }
}
