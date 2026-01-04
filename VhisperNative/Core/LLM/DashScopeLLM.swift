//
//  DashScopeLLM.swift
//  VhisperNative
//
//  DashScope (Qwen) LLM service
//

import Foundation

/// DashScope LLM service for text refinement
final class DashScopeLLM: LLMService, @unchecked Sendable {
    private let apiKey: String
    private let model: String

    private let apiURL = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation")!

    init(apiKey: String, model: String = "qwen-plus") {
        self.apiKey = apiKey
        self.model = model
    }

    func refineText(_ text: String) async throws -> String {
        guard !text.isEmpty else { return text }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let requestBody = DashScopeRequest(
            model: model,
            input: DashScopeInput(
                messages: [
                    DashScopeMessage(role: "system", content: LLMPrompt.refinePrompt),
                    DashScopeMessage(role: "user", content: text)
                ]
            ),
            parameters: DashScopeParameters(
                resultFormat: "message",
                temperature: 0.3,
                maxTokens: 2000
            )
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.network("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(DashScopeErrorResponse.self, from: data) {
                throw LLMError.api(errorResponse.message)
            }
            throw LLMError.api("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(DashScopeResponse.self, from: data)

        guard let content = result.output.choices.first?.message.content else {
            throw LLMError.api("No content in response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Request/Response Types

private struct DashScopeRequest: Encodable {
    let model: String
    let input: DashScopeInput
    let parameters: DashScopeParameters
}

private struct DashScopeInput: Encodable {
    let messages: [DashScopeMessage]
}

private struct DashScopeMessage: Encodable {
    let role: String
    let content: String
}

private struct DashScopeParameters: Encodable {
    let resultFormat: String
    let temperature: Float
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case resultFormat = "result_format"
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct DashScopeResponse: Decodable {
    let output: DashScopeOutput
}

private struct DashScopeOutput: Decodable {
    let choices: [DashScopeChoice]
}

private struct DashScopeChoice: Decodable {
    let message: DashScopeResponseMessage
}

private struct DashScopeResponseMessage: Decodable {
    let content: String
}

private struct DashScopeErrorResponse: Decodable {
    let message: String
    let code: String?
}
