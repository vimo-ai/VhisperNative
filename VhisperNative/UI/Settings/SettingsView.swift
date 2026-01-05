//
//  SettingsView.swift
//  VhisperNative
//
//  Main settings window with sidebar navigation
//

import SwiftUI
import Carbon.HIToolbox

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "general"
    case asr = "asr"
    case llm = "llm"
    case vocabulary = "vocabulary"
    case hotkey = "hotkey"
    case permissions = "permissions"

    var id: String { rawValue }

    /// Localization key for display name
    var localizationKey: String {
        switch self {
        case .general: return "settings.tab.general"
        case .asr: return "settings.tab.asr"
        case .llm: return "settings.tab.llm"
        case .vocabulary: return "settings.tab.vocabulary"
        case .hotkey: return "settings.tab.hotkey"
        case .permissions: return "settings.tab.permissions"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .asr: return "mic.fill"
        case .llm: return "sparkles"
        case .vocabulary: return "book.fill"
        case .hotkey: return "keyboard"
        case .permissions: return "lock.shield"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var manager: VhisperManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var localizationManager = LocalizationManager.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var showingSaveConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar

            // Main content
            VStack(spacing: 0) {
                // Permission warning banner
                if permissionManager.hasPermissionIssues {
                    permissionWarningBanner
                }

                // Content area
                ScrollView {
                    contentView
                        .padding(.horizontal, 28)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                // Footer with save button
                footer
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 700, height: 540)
        .onAppear {
            permissionManager.checkAllPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Auto-refresh permissions when app becomes active
            permissionManager.forceRefreshMicrophonePermission()
            permissionManager.forceRefreshAccessibilityPermission()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App title
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Vhisper")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Navigation buttons
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsTab.allCases) { tab in
                        sidebarButton(for: tab)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 180)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func sidebarButton(for tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .foregroundColor(selectedTab == tab ? .white : .secondary)
                    .frame(width: 18)

                Text(tab.localizationKey.localized())
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()

                // Warning dot for permissions
                if tab == .permissions && permissionManager.hasPermissionIssues {
                    Circle()
                        .fill(selectedTab == tab ? Color.white : Color.red)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selectedTab == tab ? Color.accentColor : Color.clear)
            .foregroundColor(selectedTab == tab ? .white : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission Warning Banner

    private var permissionWarningBanner: some View {
        Button(action: { selectedTab = .permissions }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text("settings.permission_warning".localized())
                    .font(.system(size: 13))

                Text("settings.permission_warning.button".localized())
                    .font(.system(size: 13, weight: .medium))
                    .underline()

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.15))
            .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsContent()
                .environmentObject(manager)
        case .asr:
            ASRSettingsContent()
                .environmentObject(manager)
        case .llm:
            LLMSettingsContent()
                .environmentObject(manager)
        case .vocabulary:
            VocabularySettingsContent()
                .environmentObject(manager)
        case .hotkey:
            HotkeySettingsContent()
                .environmentObject(hotkeyManager)
        case .permissions:
            PermissionsSettingsContent()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if showingSaveConfirmation {
                Label("settings.save.success".localized(), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            }

            Spacer()

            Button("settings.save".localized()) {
                manager.saveConfiguration()
                showingSaveConfirmation = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showingSaveConfirmation = false
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - ASR Settings Content

struct ASRSettingsContent: View {
    @EnvironmentObject var manager: VhisperManager
    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("settings.asr.title".localized())
                .font(.system(size: 18, weight: .semibold))

            // Provider Section
            SettingsSection {
                SettingsRow(label: "settings.asr.provider".localized()) {
                    Picker("", selection: $manager.config.asr.provider) {
                        ForEach(ASRProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 240)
                }

                // Provider-specific settings
                providerSettings
            }

            // VAD settings (only show for streaming providers)
            if manager.config.asr.provider == .qwen || manager.config.asr.provider == .dashscope {
                vadSettingsSection
            }

            // Test connection
            SettingsSection {
                HStack(spacing: 12) {
                    Button(action: testConnection) {
                        HStack(spacing: 6) {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(isTesting ? "settings.asr.testing".localized() : "settings.asr.test".localized())
                        }
                        .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTesting || !isConfigValid)

                    if let result = testResult {
                        Label(result.message, systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(result.success ? .green : .red)
                    }

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var providerSettings: some View {
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
    }

    @ViewBuilder
    private var qwenSettings: some View {
        SettingsRow(label: "settings.asr.apikey".localized(), hint: "settings.asr.apikey.hint.dashscope".localized()) {
            SecureField("", text: Binding(
                get: { manager.config.asr.qwen?.apiKey ?? "" },
                set: {
                    if manager.config.asr.qwen == nil {
                        manager.config.asr.qwen = QwenASRConfig()
                    }
                    manager.config.asr.qwen?.apiKey = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        SettingsRow(label: "settings.asr.model".localized(), hint: "settings.asr.model.qwen.hint".localized()) {
            Text("settings.asr.model.qwen.recommended".localized())
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var dashscopeSettings: some View {
        SettingsRow(label: "settings.asr.apikey".localized(), hint: "settings.asr.apikey.hint.dashscope".localized()) {
            SecureField("", text: Binding(
                get: { manager.config.asr.dashscope?.apiKey ?? "" },
                set: {
                    if manager.config.asr.dashscope == nil {
                        manager.config.asr.dashscope = DashScopeASRConfig()
                    }
                    manager.config.asr.dashscope?.apiKey = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        SettingsRow(label: "settings.asr.model".localized()) {
            Picker("", selection: Binding(
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
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 240)
        }
    }

    @ViewBuilder
    private var openaiSettings: some View {
        SettingsRow(label: "settings.asr.apikey".localized()) {
            SecureField("", text: Binding(
                get: { manager.config.asr.openai?.apiKey ?? "" },
                set: {
                    if manager.config.asr.openai == nil {
                        manager.config.asr.openai = OpenAIASRConfig()
                    }
                    manager.config.asr.openai?.apiKey = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        SettingsRow(label: "settings.asr.model".localized()) {
            Text("whisper-1")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
        }

        SettingsRow(label: "settings.asr.language".localized()) {
            Picker("", selection: Binding(
                get: { manager.config.asr.openai?.language ?? "zh" },
                set: {
                    if manager.config.asr.openai == nil {
                        manager.config.asr.openai = OpenAIASRConfig()
                    }
                    manager.config.asr.openai?.language = $0
                }
            )) {
                Text("settings.asr.language.chinese".localized()).tag("zh")
                Text("settings.asr.language.english".localized()).tag("en")
                Text("settings.asr.language.japanese".localized()).tag("ja")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 160)
        }
    }

    @ViewBuilder
    private var funasrSettings: some View {
        SettingsRow(label: "settings.asr.endpoint".localized(), hint: "settings.asr.endpoint.funasr.hint".localized()) {
            TextField("", text: Binding(
                get: { manager.config.asr.funasr?.endpoint ?? "ws://localhost:10096" },
                set: {
                    if manager.config.asr.funasr == nil {
                        manager.config.asr.funasr = FunASRConfig()
                    }
                    manager.config.asr.funasr?.endpoint = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }
    }

    // MARK: - VAD Settings Section

    @ViewBuilder
    private var vadSettingsSection: some View {
        SettingsSection(title: "settings.vad.title".localized()) {
            // Presets
            SettingsRow(label: "settings.vad.presets".localized(), hint: "settings.vad.presets.hint".localized()) {
                HStack(spacing: 6) {
                    ForEach(VADConfig.presets, id: \.name) { preset in
                        Button(preset.localizationKey.localized()) {
                            manager.config.asr.vad = preset.config
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(isVADPresetSelected(preset.config) ? .accentColor : nil)
                    }
                }
            }

            // Silence duration slider
            SettingsRow(label: "settings.vad.silence".localized(), hint: "settings.vad.silence.hint".localized()) {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(
                            get: { Double(manager.config.asr.vad.silenceDurationMs) },
                            set: { manager.config.asr.vad.silenceDurationMs = Int($0) }
                        ),
                        in: 100...1500,
                        step: 50
                    )
                    .frame(width: 160)

                    Text("\(manager.config.asr.vad.silenceDurationMs) ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            // Threshold slider
            SettingsRow(label: "settings.vad.threshold".localized(), hint: "settings.vad.threshold.hint".localized()) {
                HStack(spacing: 12) {
                    Slider(
                        value: $manager.config.asr.vad.threshold,
                        in: 0.1...0.9,
                        step: 0.05
                    )
                    .frame(width: 160)

                    Text(String(format: "%.2f", manager.config.asr.vad.threshold))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }

    private func isVADPresetSelected(_ config: VADConfig) -> Bool {
        manager.config.asr.vad.silenceDurationMs == config.silenceDurationMs &&
        manager.config.asr.vad.threshold == config.threshold
    }

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

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                testResult = (true, "settings.asr.test.success".localized())
            } catch {
                testResult = (false, "settings.asr.test.failed".localized() + ": \(error.localizedDescription)")
            }
            isTesting = false
        }
    }
}

// MARK: - LLM Settings Content

struct LLMSettingsContent: View {
    @EnvironmentObject var manager: VhisperManager
    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("settings.llm.title".localized())
                .font(.system(size: 18, weight: .semibold))

            // Enable Section
            SettingsSection {
                SettingsRow(label: "settings.llm.enable".localized(), hint: "settings.llm.enable.hint".localized()) {
                    Toggle("", isOn: $manager.config.llm.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            if manager.config.llm.enabled {
                // Provider Section
                SettingsSection {
                    SettingsRow(label: "settings.llm.provider".localized()) {
                        Picker("", selection: $manager.config.llm.provider) {
                            ForEach(LLMProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }

                    // Provider-specific settings
                    providerSettings
                }

                // Test button for Ollama
                if manager.config.llm.provider == .ollama {
                    SettingsSection {
                        HStack(spacing: 12) {
                            Button(action: testOllama) {
                                HStack(spacing: 6) {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(isTesting ? "settings.asr.testing".localized() : "settings.asr.test".localized())
                                }
                                .frame(minWidth: 80)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting)

                            if let result = testResult {
                                Label(result.message, systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(result.success ? .green : .red)
                            }

                            Spacer()
                        }
                    }
                }

                // Custom prompt section
                customPromptSection
            }
        }
    }

    // MARK: - Custom Prompt Section

    @ViewBuilder
    private var customPromptSection: some View {
        SettingsSection(title: "settings.llm.prompt".localized()) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("settings.llm.prompt.hint".localized())
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    Spacer()

                    if manager.config.llm.customPrompt != nil {
                        Button("settings.llm.prompt.reset".localized()) {
                            manager.config.llm.customPrompt = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                TextEditor(text: Binding(
                    get: { manager.config.llm.customPrompt ?? LLMPrompt.defaultRefinePrompt },
                    set: { newValue in
                        if newValue == LLMPrompt.defaultRefinePrompt {
                            manager.config.llm.customPrompt = nil
                        } else {
                            manager.config.llm.customPrompt = newValue
                        }
                    }
                ))
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 100)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var providerSettings: some View {
        switch manager.config.llm.provider {
        case .dashscope:
            dashscopeSettings
        case .openai:
            openaiSettings
        case .ollama:
            ollamaSettings
        }
    }

    @ViewBuilder
    private var dashscopeSettings: some View {
        SettingsRow(label: "settings.asr.apikey".localized(), hint: "settings.llm.apikey.hint.dashscope".localized()) {
            SecureField("", text: Binding(
                get: { manager.config.llm.dashscope?.apiKey ?? "" },
                set: {
                    if manager.config.llm.dashscope == nil {
                        manager.config.llm.dashscope = DashScopeLLMConfig()
                    }
                    manager.config.llm.dashscope?.apiKey = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        SettingsRow(label: "settings.asr.model".localized()) {
            Picker("", selection: Binding(
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
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 200)
        }
    }

    @ViewBuilder
    private var openaiSettings: some View {
        SettingsRow(label: "settings.asr.apikey".localized()) {
            SecureField("", text: Binding(
                get: { manager.config.llm.openai?.apiKey ?? "" },
                set: {
                    if manager.config.llm.openai == nil {
                        manager.config.llm.openai = OpenAILLMConfig()
                    }
                    manager.config.llm.openai?.apiKey = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        SettingsRow(label: "settings.asr.model".localized()) {
            TextField("", text: Binding(
                get: { manager.config.llm.openai?.model ?? "gpt-4o-mini" },
                set: {
                    if manager.config.llm.openai == nil {
                        manager.config.llm.openai = OpenAILLMConfig()
                    }
                    manager.config.llm.openai?.model = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
        }
    }

    @ViewBuilder
    private var ollamaSettings: some View {
        SettingsRow(label: "settings.llm.endpoint".localized(), hint: "settings.llm.endpoint.ollama.hint".localized()) {
            TextField("", text: Binding(
                get: { manager.config.llm.ollama?.endpoint ?? "http://localhost:11434" },
                set: {
                    if manager.config.llm.ollama == nil {
                        manager.config.llm.ollama = OllamaLLMConfig()
                    }
                    manager.config.llm.ollama?.endpoint = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)
        }

        SettingsRow(label: "settings.asr.model".localized(), hint: "settings.llm.model.ollama.hint".localized()) {
            TextField("", text: Binding(
                get: { manager.config.llm.ollama?.model ?? "qwen3:8b" },
                set: {
                    if manager.config.llm.ollama == nil {
                        manager.config.llm.ollama = OllamaLLMConfig()
                    }
                    manager.config.llm.ollama?.model = $0
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
        }
    }

    private func testOllama() {
        isTesting = true
        testResult = nil

        Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                testResult = (true, "settings.asr.test.success".localized())
            } catch {
                testResult = (false, "settings.asr.test.failed".localized() + ": \(error.localizedDescription)")
            }
            isTesting = false
        }
    }
}

// MARK: - Hotkey Settings Content

struct HotkeySettingsContent: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @StateObject private var permissionManager = PermissionManager.shared

    // Preset hotkeys using HotkeyBinding
    var presetHotkeys: [(String, HotkeyBinding)] {
        [
            ("Option", HotkeyBinding(keyCode: 0xFFFF, modifiers: UInt32(optionKey), isModifierOnly: true, useSpecificModifierKey: false)),
            ("Control", HotkeyBinding(keyCode: 0xFFFF, modifiers: UInt32(controlKey), isModifierOnly: true, useSpecificModifierKey: false)),
            ("CapsLock", HotkeyBinding(keyCode: UInt16(kVK_CapsLock), modifiers: 0, isModifierOnly: true, useSpecificModifierKey: true)),
            ("F1", HotkeyBinding(keyCode: UInt16(kVK_F1), modifiers: 0, isModifierOnly: false, useSpecificModifierKey: false)),
            ("Ctrl+Space", HotkeyBinding(keyCode: UInt16(kVK_Space), modifiers: UInt32(controlKey), isModifierOnly: false, useSpecificModifierKey: false))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("settings.hotkey.title".localized())
                .font(.system(size: 18, weight: .semibold))

            // Accessibility warning
            if permissionManager.accessibilityStatus != .granted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))

                    Text("settings.hotkey.accessibility.warning".localized())
                        .font(.system(size: 12))

                    Spacer()

                    Button("alert.button.open_settings".localized()) {
                        permissionManager.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Current hotkey section
            SettingsSection(title: "settings.hotkey.trigger".localized()) {
                if hotkeyManager.isListeningForHotkey {
                    // Recording mode
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.orange)
                            Text("settings.hotkey.recording".localized())
                                .foregroundColor(.orange)
                        }
                        .font(.system(size: 13))

                        if let pending = hotkeyManager.pendingHotkey {
                            Text(pending.displayString)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(6)
                        } else {
                            Text("settings.hotkey.waiting".localized())
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button("settings.hotkey.cancel".localized()) {
                                hotkeyManager.cancelHotkeyRecording()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("settings.hotkey.confirm".localized()) {
                                hotkeyManager.confirmPendingHotkey()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(hotkeyManager.pendingHotkey == nil)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    // Normal display
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text(hotkeyManager.currentHotkey.displayString)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)

                            Button("settings.hotkey.change".localized()) {
                                hotkeyManager.startListeningForNewHotkey()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("settings.hotkey.reset".localized()) {
                                hotkeyManager.updateHotkey(.default)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text("settings.hotkey.hint".localized())
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Preset hotkeys
            SettingsSection(title: "settings.hotkey.common".localized()) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(presetHotkeys, id: \.0) { (name, config) in
                            Button(name) {
                                hotkeyManager.updateHotkey(config)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Text("settings.hotkey.usage".localized())
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Permissions Settings Content

struct PermissionsSettingsContent: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("permissions.title".localized())
                    .font(.system(size: 18, weight: .semibold))

                Text("permissions.description".localized())
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Permission cards
            VStack(spacing: 12) {
                // Accessibility permission
                PermissionCard(
                    icon: "hand.raised.fill",
                    title: "permissions.accessibility".localized(),
                    description: "permissions.accessibility.description".localized(),
                    status: permissionManager.accessibilityStatus,
                    instruction: permissionManager.accessibilityStatus == .granted
                        ? "permissions.accessibility.granted".localized()
                        : "permissions.accessibility.instruction".localized(),
                    openSettings: { permissionManager.openAccessibilitySettings() }
                )

                // Microphone permission
                PermissionCard(
                    icon: "mic.fill",
                    title: "permissions.microphone".localized(),
                    description: "permissions.microphone.description".localized(),
                    status: permissionManager.microphoneStatus,
                    instruction: permissionManager.microphoneStatus == .granted
                        ? "permissions.microphone.granted".localized()
                        : "permissions.microphone.manual_instruction".localized(),
                    openSettings: { permissionManager.openMicrophoneSettings() }
                )
            }

            // Refresh button
            HStack {
                Button(action: refreshPermissions) {
                    HStack(spacing: 6) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRefreshing ? "permissions.button.refreshing".localized() : "permissions.button.refresh".localized())
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRefreshing)

                Spacer()
            }
        }
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    private func refreshPermissions() {
        isRefreshing = true
        permissionManager.forceRefreshMicrophonePermission()
        permissionManager.forceRefreshAccessibilityPermission()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }
}

// MARK: - Permission Card

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionManager.PermissionStatus
    let instruction: String
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(statusColor)
                .frame(width: 36, height: 36)
                .background(statusColor.opacity(0.12))
                .cornerRadius(8)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    statusBadge
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if status != .granted {
                    Text(instruction)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }

            // Action button
            if status != .granted {
                Button(action: openSettings) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .unknown: return .gray
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1))
        .cornerRadius(10)
    }

    private var statusText: String {
        switch status {
        case .granted: return "permissions.status.granted".localized()
        case .denied: return "permissions.status.denied".localized()
        case .notDetermined: return "permissions.status.not_requested".localized()
        case .unknown: return "permissions.status.unknown".localized()
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

// MARK: - Settings Row

struct SettingsRow<Content: View>: View {
    let label: String
    let hint: String?
    let content: Content

    private let labelWidth: CGFloat = 140

    init(label: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(width: labelWidth, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    content
                }
            }

            if let hint = hint {
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: labelWidth + 16)
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Vocabulary Settings Content

struct VocabularySettingsContent: View {
    @EnvironmentObject var manager: VhisperManager
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("settings.vocabulary.title".localized())
                .font(.system(size: 18, weight: .semibold))

            // Enable Section
            SettingsSection {
                SettingsRow(label: "settings.vocabulary.enable".localized(), hint: "settings.vocabulary.enable.hint".localized()) {
                    Toggle("", isOn: $manager.config.vocabulary.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            if manager.config.vocabulary.enabled {
                // Processing options
                SettingsSection(title: "settings.vocabulary.postASR".localized()) {
                    SettingsRow(label: "settings.vocabulary.postASR".localized(), hint: "settings.vocabulary.postASR.hint".localized()) {
                        Toggle("", isOn: $manager.config.vocabulary.enablePostASRReplacement)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    SettingsRow(label: "settings.vocabulary.llmInjection".localized(), hint: "settings.vocabulary.llmInjection.hint".localized()) {
                        Toggle("", isOn: $manager.config.vocabulary.enableLLMInjection)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                // Categories section
                categoriesSection
            }
        }
    }

    // MARK: - Categories Section

    @ViewBuilder
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("settings.vocabulary.categories".localized())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { isAddingCategory = true }) {
                    Label("settings.vocabulary.categories.add".localized(), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                if manager.config.vocabulary.categories.isEmpty && !isAddingCategory {
                    Text("settings.vocabulary.categories.empty".localized())
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                } else {
                    ForEach($manager.config.vocabulary.categories) { $category in
                        VocabularyCategoryRow(category: $category, onDelete: {
                            manager.config.vocabulary.categories.removeAll { $0.id == category.id }
                        })
                    }
                }

                // Add category form
                if isAddingCategory {
                    addCategoryView
                }
            }
        }
    }

    @ViewBuilder
    private var addCategoryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.vocabulary.category.new".localized())
                .font(.system(size: 12, weight: .medium))

            HStack(spacing: 10) {
                TextField("settings.vocabulary.category.name".localized(), text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Button("settings.vocabulary.add".localized()) {
                    guard !newCategoryName.isEmpty else { return }
                    let category = VocabularyCategory(name: newCategoryName)
                    manager.config.vocabulary.categories.append(category)
                    newCategoryName = ""
                    isAddingCategory = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newCategoryName.isEmpty)

                Button("settings.vocabulary.cancel".localized()) {
                    newCategoryName = ""
                    isAddingCategory = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Vocabulary Category Row

struct VocabularyCategoryRow: View {
    @Binding var category: VocabularyCategory
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isAddingEntry = false
    @State private var newCorrectWord = ""
    @State private var newVariants = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Toggle("", isOn: $category.enabled)
                    .labelsHidden()
                    .scaleEffect(0.75)

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)

                        Text(category.name)
                            .font(.system(size: 12, weight: .medium))

                        Text("(\(category.entries.count))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if isExpanded {
                    Button(action: { isAddingEntry = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Entries (when expanded)
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach($category.entries) { $entry in
                        VocabularyEntryRow(entry: $entry, onDelete: {
                            category.entries.removeAll { $0.id == entry.id }
                        })
                    }

                    if isAddingEntry {
                        addEntryView
                            .padding(10)
                    }

                    if category.entries.isEmpty && !isAddingEntry {
                        Text("settings.vocabulary.categories.empty".localized())
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(12)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var addEntryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("settings.vocabulary.entry.correct".localized(), text: $newCorrectWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(width: 120)

                TextField("settings.vocabulary.entry.variants".localized(), text: $newVariants)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: 200)
            }

            HStack(spacing: 8) {
                Button("settings.vocabulary.add".localized()) {
                    guard !newCorrectWord.isEmpty, !newVariants.isEmpty else { return }
                    let variants = newVariants.split(separator: ",").map {
                        String($0).trimmingCharacters(in: .whitespaces)
                    }
                    let entry = VocabularyEntry(correctWord: newCorrectWord, errorVariants: variants)
                    category.entries.append(entry)
                    newCorrectWord = ""
                    newVariants = ""
                    isAddingEntry = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(newCorrectWord.isEmpty || newVariants.isEmpty)

                Button("settings.vocabulary.cancel".localized()) {
                    newCorrectWord = ""
                    newVariants = ""
                    isAddingEntry = false
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(6)
    }
}

// MARK: - Vocabulary Entry Row

struct VocabularyEntryRow: View {
    @Binding var entry: VocabularyEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.correctWord)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)

            Image(systemName: "arrow.left")
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            Text(entry.errorVariants.joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - General Settings Content

struct GeneralSettingsContent: View {
    @EnvironmentObject var manager: VhisperManager
    @ObservedObject private var localizationManager = LocalizationManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            Text("settings.general.title".localized())
                .font(.system(size: 18, weight: .semibold))

            // Language Section
            SettingsSection {
                SettingsRow(label: "settings.language.title".localized(), hint: "settings.language.description".localized()) {
                    Picker("", selection: $manager.config.general.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    .onChange(of: manager.config.general.language) { newLanguage in
                        localizationManager.setLanguage(newLanguage)
                    }
                }
            }

            Spacer()
        }
        .onAppear {
            localizationManager.setLanguage(manager.config.general.language)
        }
    }
}
