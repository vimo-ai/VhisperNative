//
//  PermissionsView.swift
//  VhisperNative
//
//  System permissions management
//

import SwiftUI

struct PermissionsView: View {
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        Form {
            Section("Required Permissions") {
                // Microphone
                HStack {
                    VStack(alignment: .leading) {
                        Text("Microphone")
                            .font(.headline)
                        Text("Required for voice recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    permissionStatusView(permissionManager.microphoneStatus)

                    if permissionManager.microphoneStatus != .granted {
                        Button("Open Settings") {
                            permissionManager.openMicrophoneSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Accessibility
                HStack {
                    VStack(alignment: .leading) {
                        Text("Accessibility")
                            .font(.headline)
                        Text("Required for global hotkeys and text input")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    permissionStatusView(permissionManager.accessibilityStatus)

                    if permissionManager.accessibilityStatus != .granted {
                        Button("Open Settings") {
                            permissionManager.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section {
                Button("Refresh Status") {
                    permissionManager.checkAllPermissions()
                }
            }

            if permissionManager.hasPermissionIssues {
                Section {
                    Text("Some permissions are not granted. Vhisper may not work properly without all required permissions.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    @ViewBuilder
    private func permissionStatusView(_ status: PermissionManager.PermissionStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .notDetermined:
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.orange)
        case .unknown:
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.gray)
        }
    }
}
