//
//  ASRProtocol.swift
//  VhisperNative
//
//  ASR service protocols and types
//

import Foundation

// MARK: - Errors

enum ASRError: Error, LocalizedError {
    case network(String)
    case api(String)
    case encoding(String)
    case timeout
    case cancelled
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .network(let msg): return "Network error: \(msg)"
        case .api(let msg): return "API error: \(msg)"
        case .encoding(let msg): return "Encoding error: \(msg)"
        case .timeout: return "Request timeout"
        case .cancelled: return "Request cancelled"
        case .notConfigured: return "ASR service not configured"
        }
    }
}

// MARK: - Streaming Events

enum StreamingASREvent: Sendable {
    case partial(text: String, stash: String)
    case final(text: String)
    case error(String)
}

enum StreamingControl: Sendable {
    case audio(Data)
    case commit
    case cancel
}

// MARK: - Protocols

/// Basic ASR service (batch recognition)
protocol ASRService: AnyObject, Sendable {
    func recognize(audioData: Data, sampleRate: UInt32) async throws -> String
}

/// Streaming ASR service (real-time recognition)
protocol StreamingASRService: ASRService {
    /// Start streaming session
    /// - Returns: Tuple of control channel and event stream
    func startStreaming(sampleRate: UInt32) async throws -> (
        control: @Sendable (StreamingControl) async -> Void,
        events: AsyncStream<StreamingASREvent>
    )
}

// MARK: - Factory

enum ASRFactory {
    static func create(config: ASRConfig) -> (any ASRService)? {
        switch config.provider {
        case .qwen:
            guard let qwenConfig = config.qwen, !qwenConfig.apiKey.isEmpty else {
                print("[ASRFactory] Qwen ASR not configured - missing API key")
                return nil
            }
            return QwenRealtimeASR(apiKey: qwenConfig.apiKey, model: qwenConfig.model)

        case .dashscope:
            guard let dsConfig = config.dashscope, !dsConfig.apiKey.isEmpty else {
                print("[ASRFactory] DashScope ASR not configured - missing API key")
                return nil
            }
            return DashScopeASR(apiKey: dsConfig.apiKey, model: dsConfig.model)

        case .openaiWhisper:
            guard let oaiConfig = config.openai, !oaiConfig.apiKey.isEmpty else {
                print("[ASRFactory] OpenAI Whisper not configured - missing API key")
                return nil
            }
            return OpenAIWhisperASR(
                apiKey: oaiConfig.apiKey,
                model: oaiConfig.model,
                language: oaiConfig.language
            )

        case .funasr:
            let funConfig = config.funasr ?? FunASRConfig()
            return FunASR(endpoint: funConfig.endpoint)
        }
    }

    static func createStreaming(config: ASRConfig) -> (any StreamingASRService)? {
        guard let service = create(config: config) else { return nil }
        return service as? StreamingASRService
    }
}
