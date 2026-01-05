//
//  OpenAIWhisperASR.swift
//  VhisperNative
//
//  OpenAI Whisper ASR using HTTP API
//

import Foundation

/// OpenAI Whisper ASR service (HTTP batch)
final class OpenAIWhisperASR: ASRService, @unchecked Sendable {
    private let apiKey: String
    private let model: String
    private let language: String

    private let apiURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(apiKey: String, model: String = "whisper-1", language: String = "zh") {
        self.apiKey = apiKey
        self.model = model
        self.language = language
    }

    func recognize(audioData: Data, sampleRate: UInt32) async throws -> String {
        // Convert to WAV format
        let samples = pcmDataToFloats(audioData)
        let wavData = AudioEncoder.encodeToWAV(samples, sampleRate: sampleRate)

        // Build multipart request
        let boundary = UUID().uuidString
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Add language field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)

        // Add response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Send request using proxy-free configuration
        let (data, response) = try await NetworkConfig.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ASRError.network("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw ASRError.api(errorResponse.error.message)
            }
            throw ASRError.api("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
    }

    private func pcmDataToFloats(_ data: Data) -> [Float] {
        var floats: [Float] = []
        floats.reserveCapacity(data.count / 2)

        data.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for sample in int16Buffer {
                floats.append(Float(sample) / Float(Int16.max))
            }
        }

        return floats
    }
}

// MARK: - Response Types

private struct WhisperResponse: Decodable {
    let text: String
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError
}

private struct OpenAIError: Decodable {
    let message: String
    let type: String?
    let code: String?
}
