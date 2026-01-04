//
//  AppConfig.swift
//  VhisperNative
//
//  Configuration data models (Codable)
//

import Foundation
import Carbon.HIToolbox

// MARK: - Main Configuration

struct AppConfig: Codable {
    var hotkey: HotkeyConfig
    var asr: ASRConfig
    var llm: LLMConfig
    var output: OutputConfig

    static var `default`: AppConfig {
        AppConfig(
            hotkey: .default,
            asr: .default,
            llm: .default,
            output: .default
        )
    }
}

// MARK: - Hotkey Configuration

struct HotkeyConfig: Codable {
    var binding: HotkeyBinding
    var enabled: Bool

    static var `default`: HotkeyConfig {
        HotkeyConfig(binding: .default, enabled: true)
    }
}

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32
    var isModifierOnly: Bool
    var useSpecificModifierKey: Bool

    static var `default`: HotkeyBinding {
        HotkeyBinding(
            keyCode: 0xFFFF,
            modifiers: UInt32(optionKey),
            isModifierOnly: true,
            useSpecificModifierKey: false
        )
    }
}

// MARK: - ASR Configuration

enum ASRProvider: String, Codable, CaseIterable, Identifiable {
    case qwen = "Qwen"
    case dashscope = "DashScope"
    case openaiWhisper = "OpenAIWhisper"
    case funasr = "FunAsr"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen: return "Qwen (Realtime)"
        case .dashscope: return "DashScope Paraformer"
        case .openaiWhisper: return "OpenAI Whisper"
        case .funasr: return "FunASR (Local)"
        }
    }
}

struct ASRConfig: Codable {
    var provider: ASRProvider
    var qwen: QwenASRConfig?
    var dashscope: DashScopeASRConfig?
    var openai: OpenAIASRConfig?
    var funasr: FunASRConfig?

    static var `default`: ASRConfig {
        ASRConfig(
            provider: .qwen,
            qwen: QwenASRConfig(),
            dashscope: nil,
            openai: nil,
            funasr: nil
        )
    }
}

struct QwenASRConfig: Codable {
    var apiKey: String = ""
    var model: String = "qwen3-asr-flash-realtime"
}

struct DashScopeASRConfig: Codable {
    var apiKey: String = ""
    var model: String = "paraformer-realtime-v2"

    static let availableModels = [
        "paraformer-realtime-v2",
        "paraformer-realtime-v1",
        "paraformer-realtime-8k-v2"
    ]
}

struct OpenAIASRConfig: Codable {
    var apiKey: String = ""
    var model: String = "whisper-1"
    var language: String = "zh"

    static let availableLanguages = ["zh", "en", "ja"]
}

struct FunASRConfig: Codable {
    var endpoint: String = "ws://localhost:10096"
}

// MARK: - LLM Configuration

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case dashscope = "DashScope"
    case openai = "OpenAI"
    case ollama = "Ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dashscope: return "DashScope (Qwen)"
        case .openai: return "OpenAI"
        case .ollama: return "Ollama (Local)"
        }
    }
}

struct LLMConfig: Codable {
    var enabled: Bool
    var provider: LLMProvider
    var dashscope: DashScopeLLMConfig?
    var openai: OpenAILLMConfig?
    var ollama: OllamaLLMConfig?

    static var `default`: LLMConfig {
        LLMConfig(
            enabled: false,
            provider: .dashscope,
            dashscope: DashScopeLLMConfig(),
            openai: nil,
            ollama: nil
        )
    }
}

struct DashScopeLLMConfig: Codable {
    var apiKey: String = ""  // Empty = reuse ASR API key
    var model: String = "qwen-plus"

    static let availableModels = ["qwen-plus", "qwen-max", "qwen-long"]
}

struct OpenAILLMConfig: Codable {
    var apiKey: String = ""
    var model: String = "gpt-4o-mini"
    var temperature: Float = 0.3
    var maxTokens: Int = 2000
}

struct OllamaLLMConfig: Codable {
    var endpoint: String = "http://localhost:11434"
    var model: String = "qwen3:8b"
}

// MARK: - Output Configuration

struct OutputConfig: Codable {
    var restoreClipboard: Bool
    var pasteDelayMs: Int

    static var `default`: OutputConfig {
        OutputConfig(
            restoreClipboard: true,
            pasteDelayMs: 50
        )
    }
}
