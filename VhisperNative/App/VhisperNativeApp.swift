//
//  VhisperNativeApp.swift
//  VhisperNative
//
//  Pure Swift/SwiftUI voice input app for macOS
//

import SwiftUI

@main
struct VhisperNativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(VhisperManager.shared)
                .environmentObject(HotkeyManager.shared)
        }
    }
}
