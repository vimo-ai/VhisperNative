//
//  HotkeyManager.swift
//  VhisperNative
//
//  Global hotkey management using NSEvent monitoring
//

import SwiftUI
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Hotkey Manager

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var currentHotkey: HotkeyBinding = .default
    @Published var isListeningForHotkey = false
    @Published var pendingHotkey: HotkeyBinding?

    private var eventMonitor: Any?
    private var flagsMonitor: Any?
    private(set) var isHotkeyPressed = false

    // Recording state
    private var hotkeyRecordingMonitor: Any?
    private var hotkeyRecordingFlagsMonitor: Any?
    private var recordedModifiers: UInt32 = 0
    private var lastModifierKeyCode: UInt16?

    private init() {
        loadHotkey()
    }

    // MARK: - Registration

    @discardableResult
    func register() -> Bool {
        unregister()

        // Check accessibility permission first
        guard AXIsProcessTrusted() else {
            print("[Hotkey] Accessibility permission not granted, hotkey registration skipped")
            return false
        }

        if currentHotkey.isModifierOnly {
            if currentHotkey.useSpecificModifierKey {
                flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    self?.handleSpecificModifierHotkey(event)
                }
            } else {
                flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                    self?.handleModifierOnlyHotkey(event)
                }
            }
        } else {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
            }
            flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp, .flagsChanged]) { [weak self] event in
                self?.handleKeyUp(event)
            }
        }

        // Verify registration succeeded
        let success = (currentHotkey.isModifierOnly && flagsMonitor != nil) ||
                      (!currentHotkey.isModifierOnly && eventMonitor != nil && flagsMonitor != nil)

        if !success {
            print("[Hotkey] Failed to register event monitors")
        } else {
            print("[Hotkey] Registered successfully: \(currentHotkey.displayString)")
        }

        return success
    }

    func unregister() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        isHotkeyPressed = false
    }

    // MARK: - Event Handlers

    private func handleModifierOnlyHotkey(_ event: NSEvent) {
        guard !isListeningForHotkey else { return }

        let modifiers = event.modifierFlags.carbonFlags
        let isPressed = (modifiers & currentHotkey.modifiers) == currentHotkey.modifiers

        if isPressed && !isHotkeyPressed {
            isHotkeyPressed = true
            DispatchQueue.main.async {
                VhisperManager.shared.startRecording()
            }
        } else if !isPressed && isHotkeyPressed {
            isHotkeyPressed = false
            DispatchQueue.main.async {
                VhisperManager.shared.stopRecording()
            }
        }
    }

    private func handleSpecificModifierHotkey(_ event: NSEvent) {
        guard !isListeningForHotkey else { return }

        let keyCode = event.keyCode
        let hasAnyModifier = event.modifierFlags.carbonFlags != 0

        if keyCode == currentHotkey.keyCode {
            if hasAnyModifier && !isHotkeyPressed {
                isHotkeyPressed = true
                DispatchQueue.main.async {
                    VhisperManager.shared.startRecording()
                }
            } else if !hasAnyModifier && isHotkeyPressed {
                isHotkeyPressed = false
                DispatchQueue.main.async {
                    VhisperManager.shared.stopRecording()
                }
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !isListeningForHotkey else { return }

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.carbonFlags

        if keyCode == currentHotkey.keyCode && modifiers == currentHotkey.modifiers && !isHotkeyPressed {
            isHotkeyPressed = true
            DispatchQueue.main.async {
                VhisperManager.shared.startRecording()
            }
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        guard !isListeningForHotkey else { return }

        if event.type == .keyUp && event.keyCode == currentHotkey.keyCode && isHotkeyPressed {
            isHotkeyPressed = false
            DispatchQueue.main.async {
                VhisperManager.shared.stopRecording()
            }
        }
    }

    // MARK: - Hotkey Recording

    func startListeningForNewHotkey() {
        unregister()
        isListeningForHotkey = true
        pendingHotkey = nil
        recordedModifiers = 0

        hotkeyRecordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if event.type == .keyDown {
                self?.handleHotkeyRecordingKeyDown(event: event)
            }
            return nil
        }

        hotkeyRecordingFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleHotkeyRecordingFlags(event: event)
            return event
        }
    }

    private func handleHotkeyRecordingKeyDown(event: NSEvent) {
        guard isListeningForHotkey else { return }

        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.carbonFlags

        if Self.isModifierKeyCode(keyCode) {
            let newHotkey = HotkeyBinding(
                keyCode: keyCode,
                modifiers: 0,
                isModifierOnly: true,
                useSpecificModifierKey: true
            )
            DispatchQueue.main.async {
                self.pendingHotkey = newHotkey
            }
            return
        }

        let newHotkey = HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            isModifierOnly: false,
            useSpecificModifierKey: false
        )
        DispatchQueue.main.async {
            self.pendingHotkey = newHotkey
        }
    }

    private func handleHotkeyRecordingFlags(event: NSEvent) {
        guard isListeningForHotkey else { return }

        let keyCode = event.keyCode
        let currentFlags = event.modifierFlags.carbonFlags

        if Self.isModifierKeyCode(keyCode) && currentFlags != 0 {
            lastModifierKeyCode = keyCode
            recordedModifiers = currentFlags
        } else if recordedModifiers != 0 && currentFlags == 0 {
            if let lastKeyCode = lastModifierKeyCode, Self.isModifierKeyCode(lastKeyCode) {
                let newHotkey = HotkeyBinding(
                    keyCode: lastKeyCode,
                    modifiers: 0,
                    isModifierOnly: true,
                    useSpecificModifierKey: true
                )
                DispatchQueue.main.async {
                    self.pendingHotkey = newHotkey
                }
            } else {
                let newHotkey = HotkeyBinding(
                    keyCode: 0xFFFF,
                    modifiers: recordedModifiers,
                    isModifierOnly: true,
                    useSpecificModifierKey: false
                )
                DispatchQueue.main.async {
                    self.pendingHotkey = newHotkey
                }
            }
            recordedModifiers = 0
            lastModifierKeyCode = nil
        }
    }

    func confirmPendingHotkey() {
        guard let pending = pendingHotkey else {
            cancelHotkeyRecording()
            return
        }

        currentHotkey = pending
        saveHotkey()
        stopListeningForNewHotkey()
        register()
    }

    func cancelHotkeyRecording() {
        stopListeningForNewHotkey()
        register()
    }

    func updateHotkey(_ binding: HotkeyBinding) {
        currentHotkey = binding
        saveHotkey()
        register()
    }

    func stopListeningForNewHotkey() {
        isListeningForHotkey = false
        pendingHotkey = nil
        recordedModifiers = 0
        lastModifierKeyCode = nil
        if let monitor = hotkeyRecordingMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyRecordingMonitor = nil
        }
        if let monitor = hotkeyRecordingFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyRecordingFlagsMonitor = nil
        }
    }

    // MARK: - Persistence

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(currentHotkey) {
            UserDefaults.standard.set(data, forKey: "vhisper.hotkey")
        }
    }

    private func loadHotkey() {
        if let data = UserDefaults.standard.data(forKey: "vhisper.hotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            currentHotkey = hotkey
        }
    }

    // MARK: - Static Helpers

    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let leftControl: UInt16 = 59
    static let rightControl: UInt16 = 62
    static let leftOption: UInt16 = 58
    static let rightOption: UInt16 = 61
    static let leftCommand: UInt16 = 55
    static let rightCommand: UInt16 = 54
    static let fnKey: UInt16 = 63

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        return [leftShift, rightShift, leftControl, rightControl,
                leftOption, rightOption, leftCommand, rightCommand, fnKey].contains(keyCode)
    }
}

// MARK: - HotkeyBinding Extension

extension HotkeyBinding {
    var displayString: String {
        if useSpecificModifierKey && isModifierOnly {
            return Self.specificModifierKeyName(keyCode) ?? "Unknown"
        }

        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("^") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("~") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("/") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("@") }

        if !isModifierOnly {
            parts.append(Self.keyCodeToString(keyCode))
        }

        return parts.isEmpty ? "Not Set" : parts.joined()
    }

    static func specificModifierKeyName(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case HotkeyManager.leftShift: return "Left Shift"
        case HotkeyManager.rightShift: return "Right Shift"
        case HotkeyManager.leftControl: return "Left Ctrl"
        case HotkeyManager.rightControl: return "Right Ctrl"
        case HotkeyManager.leftOption: return "Left Option"
        case HotkeyManager.rightOption: return "Right Option"
        case HotkeyManager.leftCommand: return "Left Cmd"
        case HotkeyManager.rightCommand: return "Right Cmd"
        case HotkeyManager.fnKey: return "Fn"
        default: return nil
        }
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        if let special = specialKeyName(for: keyCode) {
            return special
        }

        if let char = characterForKeyCode(keyCode) {
            return char.uppercased()
        }

        return "Key(\(keyCode))"
    }

    private static func specialKeyName(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_CapsLock: return "CapsLock"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }

    private static func characterForKeyCode(_ keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var actualLength: Int = 0

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            chars.count,
            &actualLength,
            &chars
        )

        guard status == noErr, actualLength > 0 else {
            return nil
        }

        return String(utf16CodeUnits: chars, count: actualLength)
    }
}

// MARK: - NSEvent Extension

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.function) { flags |= UInt32(NSEvent.ModifierFlags.function.rawValue) }
        return flags
    }
}
