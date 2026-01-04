//
//  PermissionManager.swift
//  VhisperNative
//
//  System permission management (Microphone, Accessibility)
//

import AVFoundation
import ApplicationServices
import AppKit

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
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .denied, .restricted:
            microphoneStatus = .denied
        case .notDetermined:
            microphoneStatus = .notDetermined
        @unknown default:
            microphoneStatus = .unknown
        }
    }

    func checkAccessibilityPermission() {
        if AXIsProcessTrusted() {
            accessibilityStatus = .granted
        } else {
            accessibilityStatus = .denied
        }
    }

    // MARK: - Request Permissions

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.checkMicrophonePermission()
                completion(granted)
            }
        }
    }

    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Open System Settings

    func openMicrophoneSettings() {
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
