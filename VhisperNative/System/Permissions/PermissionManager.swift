//
//  PermissionManager.swift
//  VhisperNative
//
//  System permission management (Microphone, Accessibility)
//

import AVFoundation
import ApplicationServices
import AppKit

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var microphoneStatus: PermissionStatus = .unknown
    @Published var accessibilityStatus: PermissionStatus = .unknown

    enum PermissionStatus: String {
        case unknown = "Unknown"
        case granted = "Granted"
        case denied = "Denied"
        case notDetermined = "Not Requested"
    }

    private init() {
        checkAllPermissions()
    }

    // MARK: - Check Permissions

    func checkAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
    }

    func checkMicrophonePermission() {
        // AVCaptureDevice.authorizationStatus can return cached/stale values
        // Use requestAccess which always returns the current status
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("[PermissionManager] checkMicrophonePermission requestAccess: \(granted)")
            Task { @MainActor [weak self] in
                self?.microphoneStatus = granted ? .granted : .denied
            }
        }
    }

    /// Force refresh microphone permission by requesting access
    /// This works because requestAccess returns immediately if already determined
    func forceRefreshMicrophonePermission() {
        print("[PermissionManager] Force refreshing microphone permission...")

        // Use requestAccess which always returns current status via callback
        // This is more reliable than authorizationStatus which may be cached
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("[PermissionManager] Microphone requestAccess callback: granted=\(granted)")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let newStatus: PermissionStatus = granted ? .granted : .denied
                print("[PermissionManager] Updating microphoneStatus to: \(newStatus)")
                self.microphoneStatus = newStatus
                // Force objectWillChange to trigger UI update
                self.objectWillChange.send()
            }
        }
    }

    func checkAccessibilityPermission() {
        let oldStatus = accessibilityStatus
        let isTrusted = AXIsProcessTrusted()
        let newStatus: PermissionStatus = isTrusted ? .granted : .denied

        // Update status
        accessibilityStatus = newStatus

        // Handle status change
        if oldStatus != newStatus {
            print("[PermissionManager] Accessibility status changed: \(oldStatus) -> \(newStatus)")
            if newStatus == .granted {
                print("[PermissionManager] Accessibility granted, registering hotkey")
                HotkeyManager.shared.register()
            }
        }
    }

    /// Force refresh accessibility permission with retry
    func forceRefreshAccessibilityPermission() {
        // Try multiple times with small delay as system may cache the result
        Task {
            for i in 0..<3 {
                let isTrusted = AXIsProcessTrusted()
                print("[PermissionManager] Accessibility check attempt \(i + 1): \(isTrusted)")

                await MainActor.run {
                    let oldStatus = self.accessibilityStatus
                    let newStatus: PermissionStatus = isTrusted ? .granted : .denied

                    if oldStatus != newStatus {
                        self.accessibilityStatus = newStatus
                        print("[PermissionManager] Accessibility status changed: \(oldStatus) -> \(newStatus)")
                        if newStatus == .granted {
                            print("[PermissionManager] Accessibility granted, registering hotkey")
                            HotkeyManager.shared.register()
                        }
                    }
                }

                if isTrusted {
                    return
                }

                // Wait a bit before next attempt
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }

    // MARK: - Request Permissions

    /// Request microphone permission. Call this on app launch.
    func requestMicrophonePermissionIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[Vhisper] Microphone authorization status: \(status.rawValue)")

        switch status {
        case .notDetermined:
            // First time - request permission
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                print("[Vhisper] Microphone permission result: \(granted)")
                DispatchQueue.main.async {
                    self?.microphoneStatus = granted ? .granted : .denied
                }
            }
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    /// Force request microphone permission (for manual trigger from UI)
    func forceRequestMicrophonePermission() {
        print("[Vhisper] Force requesting microphone permission...")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            print("[Vhisper] Force request result: \(granted)")
            DispatchQueue.main.async {
                self?.microphoneStatus = granted ? .granted : .denied
            }
        }
    }

    /// Request accessibility permission - triggers system prompt to add app to list
    func requestAccessibilityPermission() {
        // This triggers the system dialog that adds the app to the accessibility list
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Open System Settings

    func openMicrophoneSettings() {
        // macOS 13+ uses different URL scheme
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Convenience

    var allPermissionsGranted: Bool {
        microphoneStatus == .granted && accessibilityStatus == .granted
    }

    var hasPermissionIssues: Bool {
        microphoneStatus == .denied || accessibilityStatus == .denied
    }
}
