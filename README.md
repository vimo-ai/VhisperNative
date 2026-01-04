# VhisperNative

Pure Swift/SwiftUI implementation of Vhisper voice input app for macOS.

## Features

- **Multiple ASR Engines**
  - Qwen Realtime (WebSocket streaming)
  - DashScope Paraformer
  - OpenAI Whisper
  - FunASR (local deployment)

- **LLM Text Refinement**
  - DashScope (Qwen)
  - OpenAI ChatGPT
  - Ollama (local)

- **System Integration**
  - Global hotkey support
  - Menu bar app
  - Waveform visualization
  - Direct text input (Espanso-style)

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

### 1. Create Xcode Project

1. Open Xcode
2. File > New > Project
3. Select "macOS" > "App"
4. Configure:
   - Product Name: `VhisperNative`
   - Team: Your team
   - Organization Identifier: `com.yourcompany`
   - Interface: SwiftUI
   - Language: Swift

### 2. Add Source Files

1. Delete the default `ContentView.swift` and `VhisperNativeApp.swift`
2. Drag the `VhisperNative` folder contents into your project
3. Make sure "Copy items if needed" is checked

### 3. Configure Project

1. Select the project in navigator
2. Select the target
3. Under "Signing & Capabilities":
   - Add "App Sandbox" capability (disable if needed for accessibility)
   - Enable "Audio Input"
   - Enable "Outgoing Connections (Client)"

4. Update Info.plist:
   - Add `NSMicrophoneUsageDescription`
   - Set `LSUIElement` to `YES` (menu bar only app)

### 4. Build & Run

1. Select "My Mac" as destination
2. Build and run (Cmd+R)

## Configuration

### API Keys

1. Click the menu bar icon
2. Open Settings
3. Configure your ASR provider and API key
4. Optionally enable LLM text refinement

### Hotkey

Default hotkey is Option key. You can change it in Settings > General.

## Permissions

The app requires:
- **Microphone**: For voice recording
- **Accessibility**: For global hotkeys and text input

Grant these permissions in System Settings > Privacy & Security.

## Architecture

```
VhisperNative/
├── App/                    # Application entry
├── Core/
│   ├── ASR/               # Speech recognition services
│   ├── LLM/               # Language model services
│   ├── Audio/             # Audio recording & FFT
│   ├── Pipeline/          # Voice processing pipeline
│   └── Config/            # Configuration management
├── System/
│   ├── Hotkey/            # Global hotkey management
│   ├── Output/            # Text output & clipboard
│   └── Permissions/       # Permission management
├── UI/
│   ├── Settings/          # Settings views
│   └── Waveform/          # Waveform visualization
└── Managers/              # State management
```

## License

Copyright 2024. All rights reserved.
