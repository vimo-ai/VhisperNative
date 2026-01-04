//
//  LLMProtocol.swift
//  VhisperNative
//
//  LLM service protocols and types
//

import Foundation

// MARK: - Errors

enum LLMError: Error, LocalizedError {
    case network(String)
    case api(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .network(let msg): return "Network error: \(msg)"
        case .api(let msg): return "API error: \(msg)"
        case .notConfigured: return "LLM service not configured"
        }
    }
}

// MARK: - Protocol

protocol LLMService: AnyObject, Sendable {
    func refineText(_ text: String) async throws -> String
}

// MARK: - Factory

enum LLMFactory {
    static func create(config: LLMConfig, asrApiKey: String? = nil) -> (any LLMService)? {
        guard config.enabled else { return nil }

        switch config.provider {
        case .dashscope:
            let dsConfig = config.dashscope ?? DashScopeLLMConfig()
            let apiKey = dsConfig.apiKey.isEmpty ? (asrApiKey ?? "") : dsConfig.apiKey
            guard !apiKey.isEmpty else { return nil }
            return DashScopeLLM(apiKey: apiKey, model: dsConfig.model)

        case .openai:
            guard let oaiConfig = config.openai, !oaiConfig.apiKey.isEmpty else {
                return nil
            }
            return OpenAILLM(
                apiKey: oaiConfig.apiKey,
                model: oaiConfig.model,
                temperature: oaiConfig.temperature,
                maxTokens: oaiConfig.maxTokens
            )

        case .ollama:
            let ollamaConfig = config.ollama ?? OllamaLLMConfig()
            return OllamaLLM(endpoint: ollamaConfig.endpoint, model: ollamaConfig.model)
        }
    }
}

// MARK: - Common Prompt

enum LLMPrompt {
    static let refinePrompt = """
    You are a text refinement assistant. Your task is to:
    1. Fix any obvious spelling or grammar errors
    2. Add appropriate punctuation
    3. Keep the original meaning and style intact
    4. Do NOT add any explanations or comments
    5. Only output the refined text

    Text to refine:
    """
}
