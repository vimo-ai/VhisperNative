//
//  KeySimulator.swift
//  VhisperNative
//
//  Espanso-style Unicode text input using CGEvent
//

import Foundation
import Carbon.HIToolbox

/// Espanso-style keyboard simulator
/// Reference: https://github.com/espanso/espanso/blob/dev/espanso-inject/src/mac/native.mm
class KeySimulator {
    static let shared = KeySimulator()

    private init() {}

    /// Send Unicode text using CGEvent
    /// This bypasses input methods and works with modifier keys pressed
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }

        // Convert to UTF-16 and process in chunks (max 20 chars per event)
        let utf16Chars = Array(text.utf16)
        let chunks = utf16Chars.chunked(into: 20)

        let delayMicroseconds: useconds_t = 1000

        for chunk in chunks {
            var chars = chunk

            // Create key down event (source = nil to bypass restrictions)
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                continue
            }
            keyDown.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyDown.flags = []  // Clear modifier flags

            // Create key up event
            guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyUp.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyUp.flags = []

            // Post events to HID event tap
            keyDown.post(tap: .cghidEventTap)
            usleep(delayMicroseconds)
            keyUp.post(tap: .cghidEventTap)
            usleep(delayMicroseconds)
        }
    }

    /// Simulate Cmd+V paste
    func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyV: CGKeyCode = 9  // V key

        // Key down with Command
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true) else { return }
        keyDown.flags = .maskCommand

        // Key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else { return }
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(10000)  // 10ms
        keyUp.post(tap: .cghidEventTap)
    }
}

// MARK: - Clipboard Manager

import AppKit

class ClipboardManager {
    static let shared = ClipboardManager()

    private let pasteboard = NSPasteboard.general

    private init() {}

    /// Get current clipboard text
    func getText() -> String? {
        return pasteboard.string(forType: .string)
    }

    /// Set clipboard text
    func setText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Execute with clipboard restore
    func withClipboardRestore<T>(_ action: () throws -> T) rethrows -> T {
        let originalText = getText()

        let result = try action()

        // Restore after a short delay
        if let original = originalText {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.setText(original)
            }
        }

        return result
    }
}

// MARK: - Text Output Service

class TextOutputService {
    static let shared = TextOutputService()

    private let clipboard = ClipboardManager.shared
    private let keySimulator = KeySimulator.shared

    private init() {}

    /// Output text using Espanso-style direct input
    func outputText(_ text: String, restoreClipboard: Bool = true, pasteDelay: Int = 50) {
        guard !text.isEmpty else { return }

        // Use direct CGEvent input (works better with modifier keys)
        // Small delay to ensure modifier key is released
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(pasteDelay) / 1000.0) {
            self.keySimulator.sendText(text)
        }
    }

    /// Output text using clipboard + paste
    func outputTextViaPaste(_ text: String, restoreClipboard: Bool = true, pasteDelay: Int = 50) {
        guard !text.isEmpty else { return }

        let originalClipboard = restoreClipboard ? clipboard.getText() : nil

        clipboard.setText(text)

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(pasteDelay) / 1000.0) { [weak self] in
            self?.keySimulator.simulatePaste()

            // Restore clipboard
            if let original = originalClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.clipboard.setText(original)
                }
            }
        }
    }
}
