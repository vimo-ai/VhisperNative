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
    var general: GeneralConfig
    var hotkey: HotkeyConfig
    var asr: ASRConfig
    var llm: LLMConfig
    var output: OutputConfig
    var vocabulary: VocabularyConfig

    static var `default`: AppConfig {
        AppConfig(
            general: .default,
            hotkey: .default,
            asr: .default,
            llm: .default,
            output: .default,
            vocabulary: .default
        )
    }

    // Custom decoder to handle missing general field in old configs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        general = try container.decodeIfPresent(GeneralConfig.self, forKey: .general) ?? .default
        hotkey = try container.decode(HotkeyConfig.self, forKey: .hotkey)
        asr = try container.decode(ASRConfig.self, forKey: .asr)
        llm = try container.decode(LLMConfig.self, forKey: .llm)
        output = try container.decode(OutputConfig.self, forKey: .output)
        vocabulary = try container.decodeIfPresent(VocabularyConfig.self, forKey: .vocabulary) ?? .default
    }

    init(general: GeneralConfig, hotkey: HotkeyConfig, asr: ASRConfig, llm: LLMConfig, output: OutputConfig, vocabulary: VocabularyConfig) {
        self.general = general
        self.hotkey = hotkey
        self.asr = asr
        self.llm = llm
        self.output = output
        self.vocabulary = vocabulary
    }
}

// MARK: - General Configuration

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return NSLocalizedString("settings.language.system", comment: "Follow System")
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    /// Get the actual locale identifier for this language
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .chinese: return "zh-Hans"
        }
    }
}

struct GeneralConfig: Codable {
    var language: AppLanguage

    static var `default`: GeneralConfig {
        GeneralConfig(language: .system)
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
    var vad: VADConfig
    var qwen: QwenASRConfig?
    var dashscope: DashScopeASRConfig?
    var openai: OpenAIASRConfig?
    var funasr: FunASRConfig?

    static var `default`: ASRConfig {
        ASRConfig(
            provider: .qwen,
            vad: .default,
            qwen: QwenASRConfig(),
            dashscope: nil,
            openai: nil,
            funasr: nil
        )
    }

    // Custom decoder to handle missing vad field in old configs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ASRProvider.self, forKey: .provider)
        vad = try container.decodeIfPresent(VADConfig.self, forKey: .vad) ?? .default
        qwen = try container.decodeIfPresent(QwenASRConfig.self, forKey: .qwen)
        dashscope = try container.decodeIfPresent(DashScopeASRConfig.self, forKey: .dashscope)
        openai = try container.decodeIfPresent(OpenAIASRConfig.self, forKey: .openai)
        funasr = try container.decodeIfPresent(FunASRConfig.self, forKey: .funasr)
    }

    init(provider: ASRProvider, vad: VADConfig, qwen: QwenASRConfig?, dashscope: DashScopeASRConfig?, openai: OpenAIASRConfig?, funasr: FunASRConfig?) {
        self.provider = provider
        self.vad = vad
        self.qwen = qwen
        self.dashscope = dashscope
        self.openai = openai
        self.funasr = funasr
    }
}

/// VAD (Voice Activity Detection) configuration
struct VADConfig: Codable {
    var silenceDurationMs: Int  // Silence duration to trigger end of speech (ms)
    var threshold: Float        // VAD sensitivity threshold (0.0 - 1.0)

    static var `default`: VADConfig {
        VADConfig(
            silenceDurationMs: 300,
            threshold: 0.5
        )
    }

    /// Predefined presets with localization keys
    static let presets: [(name: String, localizationKey: String, config: VADConfig)] = [
        ("Fast", "settings.vad.preset.fast", VADConfig(silenceDurationMs: 200, threshold: 0.5)),
        ("Default", "settings.vad.preset.default", VADConfig(silenceDurationMs: 300, threshold: 0.5)),
        ("Stable", "settings.vad.preset.stable", VADConfig(silenceDurationMs: 500, threshold: 0.5)),
        ("Long", "settings.vad.preset.long", VADConfig(silenceDurationMs: 800, threshold: 0.4))
    ]
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
    var customPrompt: String?  // nil = use default prompt
    var dashscope: DashScopeLLMConfig?
    var openai: OpenAILLMConfig?
    var ollama: OllamaLLMConfig?

    static var `default`: LLMConfig {
        LLMConfig(
            enabled: false,
            provider: .dashscope,
            customPrompt: nil,
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

// MARK: - Vocabulary Configuration

/// A vocabulary entry mapping multiple error spellings to one correct word
struct VocabularyEntry: Codable, Identifiable {
    var id: UUID
    var correctWord: String      // The correct word to output
    var errorVariants: [String]  // Possible misspellings/alternate transcriptions

    init(id: UUID = UUID(), correctWord: String, errorVariants: [String]) {
        self.id = id
        self.correctWord = correctWord
        self.errorVariants = errorVariants
    }
}

/// A category of vocabulary entries
struct VocabularyCategory: Codable, Identifiable {
    var id: UUID
    var name: String             // Category name (e.g., "Brand Names", "Person Names")
    var entries: [VocabularyEntry]
    var enabled: Bool

    init(id: UUID = UUID(), name: String, entries: [VocabularyEntry] = [], enabled: Bool = true) {
        self.id = id
        self.name = name
        self.entries = entries
        self.enabled = enabled
    }
}

/// Vocabulary configuration
struct VocabularyConfig: Codable {
    var enabled: Bool
    var enablePostASRReplacement: Bool  // Direct text replacement after ASR
    var enableLLMInjection: Bool        // Add vocabulary context to LLM prompt
    var categories: [VocabularyCategory]

    static var `default`: VocabularyConfig {
        VocabularyConfig(
            enabled: false,
            enablePostASRReplacement: true,
            enableLLMInjection: true,
            categories: []
        )
    }

    /// Get all enabled vocabulary entries as a flat dictionary for replacement
    var replacementDictionary: [String: String] {
        var dict: [String: String] = [:]
        for category in categories where category.enabled {
            for entry in category.entries {
                for variant in entry.errorVariants {
                    dict[variant.lowercased()] = entry.correctWord
                }
            }
        }
        return dict
    }

    /// Generate vocabulary context string for LLM prompt injection
    var llmContextString: String? {
        guard enabled && enableLLMInjection else { return nil }

        var lines: [String] = []
        for category in categories where category.enabled {
            for entry in category.entries {
                let variants = entry.errorVariants.joined(separator: ", ")
                lines.append("- \"\(variants)\" should be written as \"\(entry.correctWord)\"")
            }
        }

        guard !lines.isEmpty else { return nil }

        return "Important vocabulary corrections:\n" + lines.joined(separator: "\n")
    }
}
