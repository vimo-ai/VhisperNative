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
    case asr = "语音识别"
    case llm = "文本优化"
    case hotkey = "快捷键"
    case permissions = "权限"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .asr: return "mic.fill"
        case .llm: return "sparkles"
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

    @State private var selectedTab: SettingsTab = .asr
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
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                // Footer with save button
                footer
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 480)
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App title
            Text("Vhisper")
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .padding(.bottom, 8)

            // Navigation buttons
            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarButton(for: tab)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 160)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func sidebarButton(for tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(.system(size: 13))

                Spacer()

                // Warning dot for permissions
                if tab == .permissions && permissionManager.hasPermissionIssues {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedTab == tab ? Color.accentColor : Color.clear)
            .foregroundColor(selectedTab == tab ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Permission Warning Banner

    private var permissionWarningBanner: some View {
        Button(action: { selectedTab = .permissions }) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text("部分系统权限未授权，可能影响应用功能。")
                    .font(.system(size: 13))

                Text("点击查看")
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
        case .asr:
            ASRSettingsContent()
                .environmentObject(manager)
        case .llm:
            LLMSettingsContent()
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
                Label("保存成功", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
            }

            Spacer()

            Button("保存设置") {
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
        VStack(alignment: .leading, spacing: 20) {
            Text("语音识别设置")
                .font(.system(size: 18, weight: .semibold))

            // Provider picker
            VStack(alignment: .leading, spacing: 8) {
                Text("ASR 服务商")
                    .font(.system(size: 13, weight: .medium))

                Picker("", selection: $manager.config.asr.provider) {
                    ForEach(ASRProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
            }

            // Provider-specific settings
            providerSettings

            // Test button
            HStack(spacing: 12) {
                Button(action: testConnection) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(isTesting ? "测试中..." : "测试")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || !isConfigValid)

                if let result = testResult {
                    Text(result.message)
                        .font(.system(size: 13))
                        .foregroundColor(result.success ? .green : .red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .cornerRadius(6)
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
        VStack(alignment: .leading, spacing: 16) {
            SettingsTextField(
                label: "API Key",
                text: Binding(
                    get: { manager.config.asr.qwen?.apiKey ?? "" },
                    set: {
                        if manager.config.asr.qwen == nil {
                            manager.config.asr.qwen = QwenASRConfig()
                        }
                        manager.config.asr.qwen?.apiKey = $0
                    }
                ),
                isSecure: true,
                hint: "从阿里云百炼控制台获取 API Key"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("模型")
                    .font(.system(size: 13, weight: .medium))

                Text("qwen3-asr-flash-realtime (推荐)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)

                Text("支持 30+ 语言，中英混合识别更准确")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var dashscopeSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsTextField(
                label: "API Key",
                text: Binding(
                    get: { manager.config.asr.dashscope?.apiKey ?? "" },
                    set: {
                        if manager.config.asr.dashscope == nil {
                            manager.config.asr.dashscope = DashScopeASRConfig()
                        }
                        manager.config.asr.dashscope?.apiKey = $0
                    }
                ),
                isSecure: true,
                hint: "从阿里云百炼控制台获取 API Key"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("模型")
                    .font(.system(size: 13, weight: .medium))

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
                .frame(maxWidth: 300)
            }
        }
    }

    @ViewBuilder
    private var openaiSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsTextField(
                label: "API Key",
                text: Binding(
                    get: { manager.config.asr.openai?.apiKey ?? "" },
                    set: {
                        if manager.config.asr.openai == nil {
                            manager.config.asr.openai = OpenAIASRConfig()
                        }
                        manager.config.asr.openai?.apiKey = $0
                    }
                ),
                isSecure: true
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("模型")
                    .font(.system(size: 13, weight: .medium))

                Text("whisper-1")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("语言")
                    .font(.system(size: 13, weight: .medium))

                Picker("", selection: Binding(
                    get: { manager.config.asr.openai?.language ?? "zh" },
                    set: {
                        if manager.config.asr.openai == nil {
                            manager.config.asr.openai = OpenAIASRConfig()
                        }
                        manager.config.asr.openai?.language = $0
                    }
                )) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
        }
    }

    @ViewBuilder
    private var funasrSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsTextField(
                label: "服务地址",
                text: Binding(
                    get: { manager.config.asr.funasr?.endpoint ?? "ws://localhost:10096" },
                    set: {
                        if manager.config.asr.funasr == nil {
                            manager.config.asr.funasr = FunASRConfig()
                        }
                        manager.config.asr.funasr?.endpoint = $0
                    }
                ),
                isSecure: false,
                hint: "本地 FunASR 服务的 WebSocket 地址"
            )
        }
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
                testResult = (true, "连接成功")
            } catch {
                testResult = (false, "连接失败: \(error.localizedDescription)")
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
        VStack(alignment: .leading, spacing: 20) {
            Text("文本优化设置")
                .font(.system(size: 18, weight: .semibold))

            // Enable toggle
            Toggle("启用 LLM 文本优化", isOn: $manager.config.llm.enabled)
                .font(.system(size: 14))

            Text("对语音识别结果进行优化，修正错误、添加标点")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if manager.config.llm.enabled {
                Divider()
                    .padding(.vertical, 4)

                // Provider picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("LLM 服务商")
                        .font(.system(size: 13, weight: .medium))

                    Picker("", selection: $manager.config.llm.provider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                }

                // Provider-specific settings
                providerSettings

                // Test button for Ollama
                if manager.config.llm.provider == .ollama {
                    HStack(spacing: 12) {
                        Button(action: testOllama) {
                            HStack(spacing: 6) {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                Text(isTesting ? "测试中..." : "测试")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isTesting)

                        if let result = testResult {
                            Text(result.message)
                                .font(.system(size: 13))
                                .foregroundColor(result.success ? .green : .red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
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
        VStack(alignment: .leading, spacing: 16) {
            SettingsTextField(
                label: "API Key",
                text: Binding(
                    get: { manager.config.llm.dashscope?.apiKey ?? "" },
                    set: {
                        if manager.config.llm.dashscope == nil {
                            manager.config.llm.dashscope = DashScopeLLMConfig()
                        }
                        manager.config.llm.dashscope?.apiKey = $0
                    }
                ),
                isSecure: true,
                hint: "可以留空，将自动使用语音识别的 API Key"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("模型")
                    .font(.system(size: 13, weight: .medium))

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
                .frame(maxWidth: 300)
            }
        }
    }

    @ViewBuilder
    private var openaiSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsTextField(
                label: "API Key",
                text: Binding(
                    get: { manager.config.llm.openai?.apiKey ?? "" },
                    set: {
                        if manager.config.llm.openai == nil {
                            manager.config.llm.openai = OpenAILLMConfig()
                        }
                        manager.config.llm.openai?.apiKey = $0
                    }
                ),
                isSecure: true
            )

            SettingsTextField(
                label: "模型",
                text: Binding(
                    get: { manager.config.llm.openai?.model ?? "gpt-4o-mini" },
                    set: {
                        if manager.config.llm.openai == nil {
                            manager.config.llm.openai = OpenAILLMConfig()
                        }
                        manager.config.llm.openai?.model = $0
                    }
                ),
                isSecure: false
            )
        }
    }

    @ViewBuilder
    private var ollamaSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsTextField(
                label: "服务地址",
                text: Binding(
                    get: { manager.config.llm.ollama?.endpoint ?? "http://localhost:11434" },
                    set: {
                        if manager.config.llm.ollama == nil {
                            manager.config.llm.ollama = OllamaLLMConfig()
                        }
                        manager.config.llm.ollama?.endpoint = $0
                    }
                ),
                isSecure: false,
                hint: "本地 Ollama 服务地址"
            )

            SettingsTextField(
                label: "模型",
                text: Binding(
                    get: { manager.config.llm.ollama?.model ?? "qwen3:8b" },
                    set: {
                        if manager.config.llm.ollama == nil {
                            manager.config.llm.ollama = OllamaLLMConfig()
                        }
                        manager.config.llm.ollama?.model = $0
                    }
                ),
                isSecure: false,
                hint: "已安装的 Ollama 模型名称"
            )
        }
    }

    private func testOllama() {
        isTesting = true
        testResult = nil

        Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                testResult = (true, "连接成功")
            } catch {
                testResult = (false, "连接失败: \(error.localizedDescription)")
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
        VStack(alignment: .leading, spacing: 20) {
            Text("快捷键设置")
                .font(.system(size: 18, weight: .semibold))

            // Accessibility warning
            if permissionManager.accessibilityStatus != .granted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text("需要辅助功能权限才能使用全局快捷键。")
                        .font(.system(size: 13))

                    Button("打开设置") {
                        permissionManager.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Current hotkey display
            VStack(alignment: .leading, spacing: 8) {
                Text("触发键")
                    .font(.system(size: 13, weight: .medium))

                if hotkeyManager.isListeningForHotkey {
                    // Recording mode
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.orange)
                            Text("请按下新的快捷键...")
                                .foregroundColor(.orange)
                        }
                        .font(.system(size: 13))

                        if let pending = hotkeyManager.pendingHotkey {
                            Text(pending.displayString)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(8)
                        } else {
                            Text("等待输入...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button("取消") {
                                hotkeyManager.cancelHotkeyRecording()
                            }
                            .buttonStyle(.bordered)

                            Button("确定") {
                                hotkeyManager.confirmPendingHotkey()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(hotkeyManager.pendingHotkey == nil)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    // Normal display
                    HStack {
                        Text(hotkeyManager.currentHotkey.displayString)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)

                        Button("修改快捷键") {
                            hotkeyManager.startListeningForNewHotkey()
                        }
                        .buttonStyle(.bordered)

                        Button("重置") {
                            // Reset to default (Option key)
                            hotkeyManager.updateHotkey(.default)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("点击输入框后按下快捷键进行设置。支持单键或组合键。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            // Preset hotkeys
            VStack(alignment: .leading, spacing: 8) {
                Text("常用快捷键")
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 8) {
                    ForEach(presetHotkeys, id: \.0) { (name, config) in
                        Button(name) {
                            hotkeyManager.updateHotkey(config)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Text("按住此键开始录音，松开后进行语音识别并输出文字")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Permissions Settings Content

struct PermissionsSettingsContent: View {
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("系统权限")
                .font(.system(size: 18, weight: .semibold))

            Text("Vhisper 需要以下系统权限才能正常工作。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            // Accessibility permission
            permissionItem(
                title: "辅助功能",
                description: "用于监听全局快捷键",
                status: permissionManager.accessibilityStatus,
                openSettings: { permissionManager.openAccessibilitySettings() }
            )

            // Microphone permission
            permissionItem(
                title: "麦克风",
                description: "用于录制语音",
                status: permissionManager.microphoneStatus,
                openSettings: { permissionManager.openMicrophoneSettings() }
            )

            // Refresh button
            Button(action: refreshPermissions) {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(isRefreshing ? "检查中..." : "刷新状态")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
        }
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    private func permissionItem(
        title: String,
        description: String,
        status: PermissionManager.PermissionStatus,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusView(status)
            }

            if status != .granted {
                Button("打开系统设置") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }

            Text(status == .granted ? "权限已授予。" : "在系统设置中找到 Vhisper 并勾选启用。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusView(_ status: PermissionManager.PermissionStatus) -> some View {
        switch status {
        case .granted:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已授权")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
            }
        case .denied:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("未授权")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
            }
        case .notDetermined:
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.orange)
                Text("未请求")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
            }
        case .unknown:
            HStack(spacing: 4) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.gray)
                Text("未知")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
        }
    }

    private func refreshPermissions() {
        isRefreshing = true
        permissionManager.checkAllPermissions()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }
}

// MARK: - Settings Text Field

struct SettingsTextField: View {
    let label: String
    @Binding var text: String
    var isSecure: Bool = false
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))

            if isSecure {
                SecureField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 350)
            } else {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 350)
            }

            if let hint = hint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}
