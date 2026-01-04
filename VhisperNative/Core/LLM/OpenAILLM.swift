//
//  OpenAILLM.swift
//  VhisperNative
//
//  OpenAI ChatGPT LLM service
//

import Foundation

/// OpenAI LLM service for text refinement
final class OpenAILLM: LLMService, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let temperature: Float
    private let maxTokens: Int

    private let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String, model: String = "gpt-4o-mini", temperature: Float = 0.3, maxTokens: Int = 2000) {
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    func refineText(_ text: String) async throws -> String {
        guard !text.isEmpty else { return text }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let requestBody = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(role: "system", content: LLMPrompt.refinePrompt),
                OpenAIMessage(role: "user", content: text)
            ],
            temperature: temperature,
            maxTokens: maxTokens
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.network("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw LLMError.api(errorResponse.error.message)
            }
            throw LLMError.api("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(OpenAIResponse.self, from: data)

        guard let content = result.choices.first?.message.content else {
            throw LLMError.api("No content in response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Request/Response Types

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Float
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Decodable {
    let choices: [OpenAIChoice]
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIResponseMessage
}

private struct OpenAIResponseMessage: Decodable {
    let content: String
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
}
