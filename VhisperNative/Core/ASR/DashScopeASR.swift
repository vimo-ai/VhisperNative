//
//  DashScopeASR.swift
//  VhisperNative
//
//  DashScope Paraformer ASR using WebSocket
//

import Foundation

/// DashScope Paraformer ASR service (WebSocket streaming)
final class DashScopeASR: StreamingASRService, @unchecked Sendable {
    private let apiKey: String
    private let model: String

    private let wsBaseURL = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"

    init(apiKey: String, model: String = "paraformer-realtime-v2") {
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - StreamingASRService

    func startStreaming(sampleRate: UInt32) async throws -> (
        control: @Sendable (StreamingControl) async -> Void,
        events: AsyncStream<StreamingASREvent>
    ) {
        var request = URLRequest(url: URL(string: wsBaseURL)!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let webSocket = NetworkConfig.webSocketTask(with: request)
        webSocket.resume()

        // Send start transcription command
        let startCommand = StartTranscriptionCommand(
            header: CommandHeader(
                taskId: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                action: "run-task",
                streaming: "duplex"
            ),
            payload: TranscriptionPayload(
                model: model,
                task: "asr",
                taskGroup: "audio",
                input: AudioInput(sampleRate: Int(sampleRate), format: "pcm"),
                parameters: TranscriptionParameters(
                    sampleRate: Int(sampleRate),
                    format: "pcm"
                )
            )
        )

        let startJSON = try JSONEncoder().encode(startCommand)
        guard let startJSONString = String(data: startJSON, encoding: .utf8) else {
            throw ASRError.api("Failed to encode start command")
        }
        try await webSocket.send(.string(startJSONString))

        let (eventStream, eventContinuation) = AsyncStream<StreamingASREvent>.makeStream()

        // Capture webSocket strongly to keep connection alive
        let controlHandler: @Sendable (StreamingControl) async -> Void = { control in
            switch control {
            case .audio(let data):
                do {
                    try await webSocket.send(.data(data))
                } catch {
                    print("[DashScopeASR] Failed to send audio: \(error)")
                    eventContinuation.yield(.error(error.localizedDescription))
                }

            case .commit:
                let finish = FinishCommand(
                    header: CommandHeader(
                        taskId: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                        action: "finish-task",
                        streaming: "duplex"
                    )
                )
                do {
                    let json = try JSONEncoder().encode(finish)
                    guard let jsonString = String(data: json, encoding: .utf8) else {
                        print("[DashScopeASR] Failed to encode finish command to string")
                        return
                    }
                    try await webSocket.send(.string(jsonString))
                } catch {
                    print("[DashScopeASR] Failed to send finish: \(error)")
                }

            case .cancel:
                webSocket.cancel(with: .normalClosure, reason: nil)
            }
        }

        // Receive messages
        Task {
            while true {
                do {
                    let message = try await webSocket.receive()

                    if case .string(let text) = message,
                       let response = try? JSONDecoder().decode(TranscriptionResponse.self, from: Data(text.utf8)) {
                        if let error = response.header.errorCode, error != 0 {
                            eventContinuation.yield(.error(response.header.errorMessage ?? "Unknown error"))
                            continue
                        }

                        if let output = response.payload?.output {
                            let text = output.sentence?.text ?? ""
                            if response.header.event == "result-generated" {
                                if output.sentence?.endTime != nil {
                                    eventContinuation.yield(.final(text: text))
                                } else {
                                    eventContinuation.yield(.partial(text: text, stash: ""))
                                }
                            }
                        }

                        if response.header.event == "task-finished" {
                            eventContinuation.finish()
                            return
                        }
                    }
                } catch {
                    eventContinuation.yield(.error(error.localizedDescription))
                    eventContinuation.finish()
                    return
                }
            }
        }

        return (control: controlHandler, events: eventStream)
    }

    func recognize(audioData: Data, sampleRate: UInt32) async throws -> String {
        let (control, events) = try await startStreaming(sampleRate: sampleRate)

        // Send audio in chunks
        let chunkSize = 3200  // 100ms at 16kHz
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + chunkSize, audioData.count)
            let chunk = audioData.subdata(in: offset..<end)
            await control(.audio(chunk))
            offset = end
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms between chunks
        }

        await control(.commit)

        var finalText = ""
        for await event in events {
            switch event {
            case .final(let text):
                finalText = text
            case .error(let msg):
                throw ASRError.api(msg)
            case .partial:
                continue
            }
        }

        return finalText
    }
}

// MARK: - Request/Response Types

private struct StartTranscriptionCommand: Encodable {
    let header: CommandHeader
    let payload: TranscriptionPayload
}

private struct FinishCommand: Encodable {
    let header: CommandHeader
}

private struct CommandHeader: Encodable {
    let taskId: String
    let action: String
    let streaming: String

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case action
        case streaming
    }
}

private struct TranscriptionPayload: Encodable {
    let model: String
    let task: String
    let taskGroup: String
    let input: AudioInput
    let parameters: TranscriptionParameters

    enum CodingKeys: String, CodingKey {
        case model
        case task
        case taskGroup = "task_group"
        case input
        case parameters
    }
}

private struct AudioInput: Encodable {
    let sampleRate: Int
    let format: String

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case format
    }
}

private struct TranscriptionParameters: Encodable {
    let sampleRate: Int
    let format: String

    enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case format
    }
}

private struct TranscriptionResponse: Decodable {
    let header: ResponseHeader
    let payload: ResponsePayload?
}

private struct ResponseHeader: Decodable {
    let taskId: String
    let event: String
    let errorCode: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case event
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

private struct ResponsePayload: Decodable {
    let output: TranscriptionOutput?
}

private struct TranscriptionOutput: Decodable {
    let sentence: Sentence?
}

private struct Sentence: Decodable {
    let text: String
    let endTime: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case endTime = "end_time"
    }
}
