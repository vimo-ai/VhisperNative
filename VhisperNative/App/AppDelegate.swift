//
//  AppDelegate.swift
//  VhisperNative
//
//  Application delegate for menu bar app setup
//

import SwiftUI
import AVFoundation
import ApplicationServices

// MARK: - Settings Window Helper

@MainActor
class SettingsOpener: ObservableObject {
    static let shared = SettingsOpener()
    var openWindowAction: ((String) -> Void)?
}

struct SettingsOpenerView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                SettingsOpener.shared.openWindowAction = { windowId in
                    openWindow(id: windowId)
                }
            }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsOpenerWindow: NSWindow?
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide Dock icon - menu bar only app
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        setupStatusItem()

        // Setup settings opener helper
        setupSettingsOpener()

        // Check accessibility permission first
        let hasAccessibility = AXIsProcessTrusted()
        print("[AppDelegate] Initial accessibility check: \(hasAccessibility)")

        // Update permission status (this will also trigger hotkey registration if granted)
        PermissionManager.shared.checkAllPermissions()

        // If accessibility already granted, register hotkey immediately
        if hasAccessibility {
            print("[AppDelegate] Accessibility granted, registering hotkey")
            HotkeyManager.shared.register()
        } else {
            print("[AppDelegate] Accessibility not granted, showing alert")
            // Show permission alert
            showAccessibilityPermissionAlert()
        }

        // Load configuration
        VhisperManager.shared.loadConfiguration()

        // Sync language with config
        LocalizationManager.shared.setLanguage(VhisperManager.shared.config.general.language)

        // Setup periodic permission check (every 2 seconds for first 30 seconds)
        setupPermissionPolling()

        // Listen for language changes to update menu
        languageObserver = NotificationCenter.default.addObserver(
            forName: LocalizationManager.languageDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupMenu()
            self?.statusItem?.menu = self?.statusMenu
        }
    }

    private func setupPermissionPolling() {
        // Poll for permission changes after user grants access
        var pollCount = 0
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            pollCount += 1
            if pollCount > 15 { // Stop after 30 seconds
                timer.invalidate()
                return
            }

            let isTrusted = AXIsProcessTrusted()
            if isTrusted && PermissionManager.shared.accessibilityStatus != .granted {
                print("[AppDelegate] Permission polling: accessibility granted!")
                PermissionManager.shared.forceRefreshAccessibilityPermission()
                timer.invalidate()
            }
        }
    }

    private func showAccessibilityPermissionAlert() {
        // Trigger system prompt to add app to accessibility list
        // This will show the system dialog and add the app to the list
        PermissionManager.shared.requestAccessibilityPermission()
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

        let settingsTitle = LocalizationManager.shared.localizedString("menu.settings")
        let settingsItem = NSMenuItem(title: settingsTitle, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        statusMenu?.addItem(settingsItem)

        statusMenu?.addItem(NSMenuItem.separator())

        let quitTitle = LocalizationManager.shared.localizedString("menu.quit")
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu?.addItem(quitItem)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Use the SwiftUI openWindow action
        if let action = SettingsOpener.shared.openWindowAction {
            action("settings")
        }

        // Find and configure settings window to not hide on deactivate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                if window.title == "Vhisper Settings" {
                    window.hidesOnDeactivate = false
                    window.level = .normal
                    break
                }
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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

    // Prevent app from quitting when last window is closed (menu bar app)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
