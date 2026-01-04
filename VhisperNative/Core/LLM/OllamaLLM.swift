//
//  OllamaLLM.swift
//  VhisperNative
//
//  Ollama local LLM service
//

import Foundation

/// Ollama LLM service for text refinement (local deployment)
final class OllamaLLM: LLMService, @unchecked Sendable {
    private let endpoint: String
    private let model: String

    init(endpoint: String = "http://localhost:11434", model: String = "qwen3:8b") {
        self.endpoint = endpoint
        self.model = model
    }

    func refineText(_ text: String) async throws -> String {
        guard !text.isEmpty else { return text }

        guard let url = URL(string: "\(endpoint)/api/chat") else {
            throw LLMError.network("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // Local models may be slower

        let requestBody = OllamaRequest(
            model: model,
            messages: [
                OllamaMessage(role: "system", content: LLMPrompt.refinePrompt),
                OllamaMessage(role: "user", content: text)
            ],
            stream: false
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.network("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OllamaErrorResponse.self, from: data) {
                throw LLMError.api(errorResponse.error)
            }
            throw LLMError.api("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)

        return result.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Test connection to Ollama server
    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            throw LLMError.network("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }
}

// MARK: - Request/Response Types

private struct OllamaRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
}

private struct OllamaMessage: Encodable {
    let role: String
    let content: String
}

private struct OllamaResponse: Decodable {
    let message: OllamaResponseMessage
}

private struct OllamaResponseMessage: Decodable {
    let content: String
}

private struct OllamaErrorResponse: Decodable {
    let error: String
}
