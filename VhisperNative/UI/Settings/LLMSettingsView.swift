//
//  LLMSettingsView.swift
//  VhisperNative
//
//  LLM service configuration for text refinement
//

import SwiftUI

struct LLMSettingsView: View {
    @EnvironmentObject var manager: VhisperManager

    var body: some View {
        Form {
            Section("Text Refinement (LLM)") {
                Toggle("Enable Text Refinement", isOn: $manager.config.llm.enabled)

                if manager.config.llm.enabled {
                    Picker("Provider", selection: $manager.config.llm.provider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    switch manager.config.llm.provider {
                    case .dashscope:
                        dashscopeSettings
                    case .openai:
                        openaiSettings
                    case .ollama:
                        ollamaSettings
                    }
                }
            }

            if manager.config.llm.enabled {
                Section {
                    Text("LLM will refine the transcribed text by fixing grammar, adding punctuation, and improving readability.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button("Save") {
                        manager.saveConfiguration()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Provider Settings

    @ViewBuilder
    private var dashscopeSettings: some View {
        SecureField("API Key (leave empty to use ASR key)", text: Binding(
            get: { manager.config.llm.dashscope?.apiKey ?? "" },
            set: {
                if manager.config.llm.dashscope == nil {
                    manager.config.llm.dashscope = DashScopeLLMConfig()
                }
                manager.config.llm.dashscope?.apiKey = $0
            }
        ))

        Picker("Model", selection: Binding(
            get: { manager.config.llm.dashscope?.model ?? "qwen-plus" },
            set: {
                if manager.config.llm.dashscope == nil {
                    manager.config.llm.dashscope = DashScopeLLMConfig()
                }
                manager.config.llm.dashscope?.model = $0
            }
        )) {
            ForEach(DashScopeLLMConfig.availableModels, id: \.self) { model in
                Text(model).tag(model)
            }
        }
    }

    @ViewBuilder
    private var openaiSettings: some View {
        SecureField("API Key", text: Binding(
            get: { manager.config.llm.openai?.apiKey ?? "" },
            set: {
                if manager.config.llm.openai == nil {
                    manager.config.llm.openai = OpenAILLMConfig()
                }
                manager.config.llm.openai?.apiKey = $0
            }
        ))

        TextField("Model", text: Binding(
            get: { manager.config.llm.openai?.model ?? "gpt-4o-mini" },
            set: {
                if manager.config.llm.openai == nil {
                    manager.config.llm.openai = OpenAILLMConfig()
                }
                manager.config.llm.openai?.model = $0
            }
        ))
    }

    @ViewBuilder
    private var ollamaSettings: some View {
        TextField("Endpoint", text: Binding(
            get: { manager.config.llm.ollama?.endpoint ?? "http://localhost:11434" },
            set: {
                if manager.config.llm.ollama == nil {
                    manager.config.llm.ollama = OllamaLLMConfig()
                }
                manager.config.llm.ollama?.endpoint = $0
            }
        ))

        TextField("Model", text: Binding(
            get: { manager.config.llm.ollama?.model ?? "qwen3:8b" },
            set: {
                if manager.config.llm.ollama == nil {
                    manager.config.llm.ollama = OllamaLLMConfig()
                }
                manager.config.llm.ollama?.model = $0
            }
        ))

        Text("Ollama runs locally. Make sure Ollama is running on your machine.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
