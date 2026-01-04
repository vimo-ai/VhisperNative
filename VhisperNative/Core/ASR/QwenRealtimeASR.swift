//
//  QwenRealtimeASR.swift
//  VhisperNative
//
//  Qwen Realtime ASR using WebSocket streaming
//

import Foundation

/// Qwen Realtime ASR service (WebSocket streaming)
final class QwenRealtimeASR: StreamingASRService, @unchecked Sendable {
    private let apiKey: String
    private let model: String

    private let wsBaseURL = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
    private let connectTimeout: TimeInterval = 10
    private let sessionConfirmTimeout: TimeInterval = 5

    init(apiKey: String, model: String = "qwen3-asr-flash-realtime") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - StreamingASRService

    func startStreaming(sampleRate: UInt32) async throws -> (
        control: @Sendable (StreamingControl) async -> Void,
        events: AsyncStream<StreamingASREvent>
    ) {
        // Build WebSocket URL
        var components = URLComponents(string: wsBaseURL)!
        components.queryItems = [URLQueryItem(name: "model", value: model)]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        request.timeoutInterval = connectTimeout

        // Create WebSocket task
        let session = URLSession(configuration: .default)
        let webSocket = session.webSocketTask(with: request)
        webSocket.resume()

        // Send session.update
        let sessionUpdate = SessionUpdateEvent(
            eventId: Self.generateEventId(),
            type: "session.update",
            session: SessionConfig(
                modalities: ["text"],
                inputAudioFormat: "pcm",
                sampleRate: sampleRate,
                inputAudioTranscription: TranscriptionConfig(language: "zh"),
                turnDetection: TurnDetection(
                    type: "server_vad",
                    threshold: 0.5,
                    silenceDurationMs: 500
                )
            )
        )

        let sessionJSON = try JSONEncoder().encode(sessionUpdate)
        try await webSocket.send(.string(String(data: sessionJSON, encoding: .utf8)!))

        // Wait for session confirmation
        try await waitForSessionConfirm(webSocket: webSocket)

        // Create event stream
        let (eventStream, eventContinuation) = AsyncStream<StreamingASREvent>.makeStream()

        // Create control handler
        let controlHandler: @Sendable (StreamingControl) async -> Void = { [weak webSocket] control in
            guard let ws = webSocket else { return }

            do {
                switch control {
                case .audio(let data):
                    let audioAppend = AudioAppendEvent(
                        eventId: Self.generateEventId(),
                        type: "input_audio_buffer.append",
                        audio: data.base64EncodedString()
                    )
                    let json = try JSONEncoder().encode(audioAppend)
                    try await ws.send(.string(String(data: json, encoding: .utf8)!))

                case .commit:
                    let commit = AudioCommitEvent(
                        eventId: Self.generateEventId(),
                        type: "input_audio_buffer.commit"
                    )
                    let json = try JSONEncoder().encode(commit)
                    try await ws.send(.string(String(data: json, encoding: .utf8)!))

                case .cancel:
                    ws.cancel(with: .normalClosure, reason: nil)
                }
            } catch {
                eventContinuation.yield(.error(error.localizedDescription))
            }
        }

        // Start receiving messages
        Task {
            var accumulatedText = ""

            while true {
                do {
                    let message = try await webSocket.receive()

                    switch message {
                    case .string(let text):
                        if let response = try? JSONDecoder().decode(ResponseEvent.self, from: Data(text.utf8)) {
                            if let error = response.error {
                                eventContinuation.yield(.error(error.message))
                                eventContinuation.finish()
                                return
                            }

                            switch response.type {
                            case "conversation.item.input_audio_transcription.text":
                                let text = response.text ?? ""
                                let stash = response.stash ?? ""
                                if !text.isEmpty {
                                    accumulatedText = text
                                }
                                eventContinuation.yield(.partial(text: text, stash: stash))

                            case "conversation.item.input_audio_transcription.completed":
                                let finalText = response.transcript ?? response.text ?? accumulatedText
                                eventContinuation.yield(.final(text: finalText))
                                accumulatedText = ""

                            case "error":
                                if let error = response.error {
                                    eventContinuation.yield(.error(error.message))
                                }

                            default:
                                break
                            }
                        }

                    case .data:
                        break  // Ignore binary messages

                    @unknown default:
                        break
                    }
                } catch {
                    if (error as NSError).code != 57 {  // Socket closed normally
                        eventContinuation.yield(.error(error.localizedDescription))
                    }
                    eventContinuation.finish()
                    return
                }
            }
        }

        return (control: controlHandler, events: eventStream)
    }

    // MARK: - ASRService (batch)

    func recognize(audioData: Data, sampleRate: UInt32) async throws -> String {
        // For batch recognition, use streaming with immediate commit
        let (control, events) = try await startStreaming(sampleRate: sampleRate)

        // Send all audio
        await control(.audio(audioData))
        await control(.commit)

        // Wait for final result
        for await event in events {
            switch event {
            case .final(let text):
                await control(.cancel)
                return text
            case .error(let msg):
                throw ASRError.api(msg)
            case .partial:
                continue
            }
        }

        throw ASRError.api("No result received")
    }

    // MARK: - Private

    private func waitForSessionConfirm(webSocket: URLSessionWebSocketTask) async throws {
        let deadline = Date().addingTimeInterval(sessionConfirmTimeout)

        while Date() < deadline {
            let message = try await webSocket.receive()

            if case .string(let text) = message,
               let response = try? JSONDecoder().decode(ResponseEvent.self, from: Data(text.utf8)) {
                if let error = response.error {
                    throw ASRError.api(error.message)
                }
                if response.type == "session.created" || response.type == "session.updated" {
                    return
                }
            }
        }

        throw ASRError.timeout
    }

    private static func generateEventId() -> String {
        "event_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20))"
    }
}

// MARK: - Request/Response Types

private struct SessionUpdateEvent: Encodable {
    let eventId: String
    let type: String
    let session: SessionConfig

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case type
        case session
    }
}

private struct SessionConfig: Encodable {
    let modalities: [String]
    let inputAudioFormat: String
    let sampleRate: UInt32
    let inputAudioTranscription: TranscriptionConfig
    let turnDetection: TurnDetection

    enum CodingKeys: String, CodingKey {
        case modalities
        case inputAudioFormat = "input_audio_format"
        case sampleRate = "sample_rate"
        case inputAudioTranscription = "input_audio_transcription"
        case turnDetection = "turn_detection"
    }
}

private struct TranscriptionConfig: Encodable {
    let language: String
}

private struct TurnDetection: Encodable {
    let type: String
    let threshold: Float
    let silenceDurationMs: UInt32

    enum CodingKeys: String, CodingKey {
        case type
        case threshold
        case silenceDurationMs = "silence_duration_ms"
    }
}

private struct AudioAppendEvent: Encodable {
    let eventId: String
    let type: String
    let audio: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case type
        case audio
    }
}

private struct AudioCommitEvent: Encodable {
    let eventId: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case type
    }
}

private struct ResponseEvent: Decodable {
    let type: String
    let transcript: String?
    let text: String?
    let stash: String?
    let error: ErrorInfo?
}

private struct ErrorInfo: Decodable {
    let message: String
}
