//
//  ConfigStorage.swift
//  VhisperNative
//
//  Configuration persistence using JSON file
//

import Foundation

actor ConfigStorage {
    static let shared = ConfigStorage()

    private let fileManager = FileManager.default
    private let configFileName = "config.json"

    private var configDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VhisperNative", isDirectory: true)
    }

    private var configFileURL: URL {
        configDirectory.appendingPathComponent(configFileName)
    }

    private init() {
        // Ensure config directory exists
        try? fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func load() async -> AppConfig {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: configFileURL)
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            return config
        } catch {
            print("Failed to load config: \(error)")
            return .default
        }
    }

    func save(_ config: AppConfig) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(config)
        try data.write(to: configFileURL, options: .atomic)
    }

    // MARK: - Migration Support

    /// Migrate from UserDefaults (legacy) to file-based storage
    func migrateFromUserDefaults() async -> AppConfig? {
        let defaults = UserDefaults.standard

        guard let provider = defaults.string(forKey: "vhisper.asr.provider") else {
            return nil
        }

        let apiKey = defaults.string(forKey: "vhisper.asr.apiKey") ?? ""
        let llmEnabled = defaults.bool(forKey: "vhisper.llm.enabled")

        var config = AppConfig.default

        // Migrate ASR config
        switch provider.lowercased() {
        case "qwen":
            config.asr.provider = .qwen
            config.asr.qwen = QwenASRConfig(apiKey: apiKey)
        case "dashscope":
            config.asr.provider = .dashscope
            config.asr.dashscope = DashScopeASRConfig(apiKey: apiKey)
        case "openaiwhisper":
            config.asr.provider = .openaiWhisper
            config.asr.openai = OpenAIASRConfig(apiKey: apiKey)
        case "funasr":
            config.asr.provider = .funasr
            config.asr.funasr = FunASRConfig()
        default:
            break
        }

        // Migrate LLM config
        config.llm.enabled = llmEnabled

        // Migrate hotkey
        if let hotkeyData = defaults.data(forKey: "vhisper.hotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyBinding.self, from: hotkeyData) {
            config.hotkey.binding = hotkey
        }

        // Save migrated config
        try? await save(config)

        // Clean up old keys
        defaults.removeObject(forKey: "vhisper.asr.provider")
        defaults.removeObject(forKey: "vhisper.asr.apiKey")
        defaults.removeObject(forKey: "vhisper.llm.enabled")
        defaults.removeObject(forKey: "vhisper.hotkey")

        return config
    }
}
