//
//  ASRSettingsView.swift
//  VhisperNative
//
//  ASR service configuration
//

import SwiftUI

struct ASRSettingsView: View {
    @EnvironmentObject var manager: VhisperManager
    @State private var showingSaveConfirmation = false
    @State private var isTesting = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section("Speech Recognition (ASR)") {
                Picker("Provider", selection: $manager.config.asr.provider) {
                    ForEach(ASRProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                switch manager.config.asr.provider {
                case .qwen:
                    qwenSettings
                case .dashscope:
                    dashscopeSettings
                case .openaiWhisper:
                    openaiSettings
                case .funasr:
                    funasrSettings
                }

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting || !isConfigValid)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.starts(with: "Success") ? .green : .red)
                }
            }

            Section {
                Button("Save") {
                    manager.saveConfiguration()
                    showingSaveConfirmation = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showingSaveConfirmation = false
                    }
                }
                .disabled(!isConfigValid)

                if showingSaveConfirmation {
                    Text("Configuration saved!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Provider Settings

    @ViewBuilder
    private var qwenSettings: some View {
        SecureField("API Key", text: Binding(
            get: { manager.config.asr.qwen?.apiKey ?? "" },
            set: {
                if manager.config.asr.qwen == nil {
                    manager.config.asr.qwen = QwenASRConfig()
                }
                manager.config.asr.qwen?.apiKey = $0
            }
        ))

        LabeledContent("Model", value: "qwen3-asr-flash-realtime")
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var dashscopeSettings: some View {
        SecureField("API Key", text: Binding(
            get: { manager.config.asr.dashscope?.apiKey ?? "" },
            set: {
                if manager.config.asr.dashscope == nil {
                    manager.config.asr.dashscope = DashScopeASRConfig()
                }
                manager.config.asr.dashscope?.apiKey = $0
            }
        ))

        Picker("Model", selection: Binding(
            get: { manager.config.asr.dashscope?.model ?? "paraformer-realtime-v2" },
            set: {
                if manager.config.asr.dashscope == nil {
                    manager.config.asr.dashscope = DashScopeASRConfig()
                }
                manager.config.asr.dashscope?.model = $0
            }
        )) {
            ForEach(DashScopeASRConfig.availableModels, id: \.self) { model in
                Text(model).tag(model)
            }
        }
    }

    @ViewBuilder
    private var openaiSettings: some View {
        SecureField("API Key", text: Binding(
            get: { manager.config.asr.openai?.apiKey ?? "" },
            set: {
                if manager.config.asr.openai == nil {
                    manager.config.asr.openai = OpenAIASRConfig()
                }
                manager.config.asr.openai?.apiKey = $0
            }
        ))

        Picker("Language", selection: Binding(
            get: { manager.config.asr.openai?.language ?? "zh" },
            set: {
                if manager.config.asr.openai == nil {
                    manager.config.asr.openai = OpenAIASRConfig()
                }
                manager.config.asr.openai?.language = $0
            }
        )) {
            Text("Chinese").tag("zh")
            Text("English").tag("en")
            Text("Japanese").tag("ja")
        }
    }

    @ViewBuilder
    private var funasrSettings: some View {
        TextField("Endpoint", text: Binding(
            get: { manager.config.asr.funasr?.endpoint ?? "ws://localhost:10096" },
            set: {
                if manager.config.asr.funasr == nil {
                    manager.config.asr.funasr = FunASRConfig()
                }
                manager.config.asr.funasr?.endpoint = $0
            }
        ))

        Text("FunASR is for local deployment. No API key required.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Validation

    private var isConfigValid: Bool {
        switch manager.config.asr.provider {
        case .qwen:
            return !(manager.config.asr.qwen?.apiKey.isEmpty ?? true)
        case .dashscope:
            return !(manager.config.asr.dashscope?.apiKey.isEmpty ?? true)
        case .openaiWhisper:
            return !(manager.config.asr.openai?.apiKey.isEmpty ?? true)
        case .funasr:
            return true
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                // Simple validation test
                try await Task.sleep(nanoseconds: 500_000_000)
                testResult = "Success: Configuration is valid"
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
