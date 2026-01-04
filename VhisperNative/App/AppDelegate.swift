//
//  AppDelegate.swift
//  VhisperNative
//
//  Application delegate for menu bar app setup
//

import SwiftUI
import AVFoundation

// MARK: - Settings Opener Helper

@MainActor
class SettingsOpener: ObservableObject {
    static let shared = SettingsOpener()
    var openSettingsAction: (() -> Void)?
}

struct SettingsOpenerView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                SettingsOpener.shared.openSettingsAction = {
                    openSettings()
                }
            }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsOpenerWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide Dock icon - menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        setupStatusItem()

        // Setup settings opener helper
        setupSettingsOpener()

        // Request microphone permission
        requestMicrophonePermission()

        // Initialize hotkey manager
        HotkeyManager.shared.register()

        // Load configuration
        VhisperManager.shared.loadConfiguration()
    }

    private func setupSettingsOpener() {
        // Create an invisible window to host the SettingsOpenerView
        let hostingView = NSHostingView(rootView: SettingsOpenerView())
        settingsOpenerWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        settingsOpenerWindow?.contentView = hostingView
        settingsOpenerWindow?.isReleasedWhenClosed = false
        settingsOpenerWindow?.orderOut(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // Use custom icon from asset catalog
            if let image = NSImage(named: "MenuBarIcon") {
                print("[Vhisper] MenuBarIcon loaded successfully")
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                print("[Vhisper] MenuBarIcon not found, using system symbol")
                // Fallback to system symbol
                if let sysImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Vhisper") {
                    sysImage.isTemplate = true
                    button.image = sysImage
                } else {
                    print("[Vhisper] System symbol also failed!")
                    button.title = "V"
                }
            }
        } else {
            print("[Vhisper] Status button is nil!")
        }

        // Create menu
        setupMenu()
        statusItem?.menu = statusMenu
    }

    private func setupMenu() {
        statusMenu = NSMenu()

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu?.addItem(settingsItem)

        statusMenu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu?.addItem(quitItem)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Use the SwiftUI openSettings action
        if let action = SettingsOpener.shared.openSettingsAction {
            action()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .denied, .restricted, .authorized:
            break
        @unknown default:
            break
        }
    }

    func updateStatusIcon(isRecording: Bool) {
        if let button = statusItem?.button {
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = !isRecording  // Disable template mode when recording to show red
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
            button.contentTintColor = isRecording ? .systemRed : nil
        }
    }
}
