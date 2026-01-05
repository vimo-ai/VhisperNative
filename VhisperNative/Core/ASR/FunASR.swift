//
//  FunASR.swift
//  VhisperNative
//
//  FunASR local deployment using WebSocket
//

import Foundation

/// FunASR service (local deployment, WebSocket)
final class FunASR: StreamingASRService, @unchecked Sendable {
    private let endpoint: String

    init(endpoint: String = "ws://localhost:10096") {
        self.endpoint = endpoint
    }

    func startStreaming(sampleRate: UInt32) async throws -> (
        control: @Sendable (StreamingControl) async -> Void,
        events: AsyncStream<StreamingASREvent>
    ) {
        guard let url = URL(string: endpoint) else {
            throw ASRError.network("Invalid endpoint URL")
        }

        // FunASR may use self-signed certificates for local deployment
        // Use proxy-free configuration to avoid network issues
        let session = URLSession(configuration: NetworkConfig.sessionConfiguration, delegate: SelfSignedCertDelegate(), delegateQueue: nil)
        let webSocket = session.webSocketTask(with: url)
        webSocket.resume()

        // Send start message
        let startMessage = FunASRStartMessage(
            mode: "2pass",
            chunkSize: [5, 10, 5],
            wavName: "audio",
            isSpeaking: true,
            chunkInterval: 10,
            hotWords: ""
        )

        let startJSON = try JSONEncoder().encode(startMessage)
        guard let startJSONString = String(data: startJSON, encoding: .utf8) else {
            throw ASRError.api("Failed to encode start message")
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
                    print("[FunASR] Failed to send audio: \(error)")
                    eventContinuation.yield(.error(error.localizedDescription))
                }

            case .commit:
                // Send end message
                let endMessage = FunASREndMessage(isSpeaking: false)
                do {
                    let json = try JSONEncoder().encode(endMessage)
                    guard let jsonString = String(data: json, encoding: .utf8) else {
                        print("[FunASR] Failed to encode end message to string")
                        return
                    }
                    try await webSocket.send(.string(jsonString))
                } catch {
                    print("[FunASR] Failed to send end message: \(error)")
                }

            case .cancel:
                webSocket.cancel(with: .normalClosure, reason: nil)
            }
        }

        // Receive messages
        Task {
            var accumulatedText = ""

            while true {
                do {
                    let message = try await webSocket.receive()

                    if case .string(let text) = message,
                       let response = try? JSONDecoder().decode(FunASRResponse.self, from: Data(text.utf8)) {
                        if response.isEnd {
                            eventContinuation.yield(.final(text: response.text ?? accumulatedText))
                            eventContinuation.finish()
                            return
                        } else {
                            let newText = response.text ?? ""
                            if response.mode == "2pass-online" {
                                // Streaming partial result
                                eventContinuation.yield(.partial(text: accumulatedText, stash: newText))
                            } else if response.mode == "2pass-offline" {
                                // Final corrected result
                                accumulatedText = newText
                                eventContinuation.yield(.partial(text: newText, stash: ""))
                            }
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
        let chunkSize = 9600  // 300ms at 16kHz (16000 * 0.3 * 2)
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + chunkSize, audioData.count)
            let chunk = audioData.subdata(in: offset..<end)
            await control(.audio(chunk))
            offset = end
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        await control(.commit)

        var finalText = ""
        for await event in events {
            switch event {
            case .final(let text):
                finalText = text
            case .error(let msg):
                throw ASRError.api(msg)
            case .partial(let text, _):
                finalText = text
            }
        }

        return finalText
    }
}

// MARK: - Request/Response Types

private struct FunASRStartMessage: Encodable {
    let mode: String
    let chunkSize: [Int]
    let wavName: String
    let isSpeaking: Bool
    let chunkInterval: Int
    let hotWords: String

    enum CodingKeys: String, CodingKey {
        case mode
        case chunkSize = "chunk_size"
        case wavName = "wav_name"
        case isSpeaking = "is_speaking"
        case chunkInterval = "chunk_interval"
        case hotWords = "hotwords"
    }
}

private struct FunASREndMessage: Encodable {
    let isSpeaking: Bool

    enum CodingKeys: String, CodingKey {
        case isSpeaking = "is_speaking"
    }
}

private struct FunASRResponse: Decodable {
    let text: String?
    let mode: String?
    let isEnd: Bool

    enum CodingKeys: String, CodingKey {
        case text
        case mode
        case isEnd = "is_end"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)

        // is_end can be bool or int
        if let boolValue = try? container.decode(Bool.self, forKey: .isEnd) {
            isEnd = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .isEnd) {
            isEnd = intValue != 0
        } else {
            isEnd = false
        }
    }
}

// MARK: - Self-Signed Certificate Delegate

private class SelfSignedCertDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept self-signed certificates for local FunASR deployment
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
