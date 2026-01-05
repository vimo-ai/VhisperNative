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
            Section(LocalizedStringKey("permissions.title")) {
                Text(LocalizedStringKey("permissions.description"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Accessibility
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(LocalizedStringKey("permissions.accessibility"))
                            .font(.headline)
                        Spacer()
                        statusBadge(permissionManager.accessibilityStatus)
                    }

                    Text(LocalizedStringKey("permissions.accessibility.description"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if permissionManager.accessibilityStatus == .granted {
                        Text(LocalizedStringKey("permissions.accessibility.granted"))
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Button(LocalizedStringKey("permissions.button.open_settings")) {
                            permissionManager.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)

                        Text(LocalizedStringKey("permissions.accessibility.instruction"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Microphone
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(LocalizedStringKey("permissions.microphone"))
                            .font(.headline)
                        Spacer()
                        statusBadge(permissionManager.microphoneStatus)
                    }

                    Text(LocalizedStringKey("permissions.microphone.description"))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if permissionManager.microphoneStatus == .granted {
                        Text(LocalizedStringKey("permissions.microphone.granted"))
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Button(LocalizedStringKey("permissions.button.request")) {
                            permissionManager.forceRequestMicrophonePermission()
                        }
                        .buttonStyle(.borderedProminent)

                        if permissionManager.microphoneStatus == .denied {
                            Button(LocalizedStringKey("permissions.button.open_settings")) {
                                permissionManager.openMicrophoneSettings()
                            }
                            .buttonStyle(.bordered)

                            Text(LocalizedStringKey("permissions.microphone.manual_instruction"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section {
                Button(LocalizedStringKey("permissions.button.refresh")) {
                    permissionManager.forceRefreshMicrophonePermission()
                    permissionManager.forceRefreshAccessibilityPermission()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            permissionManager.checkAllPermissions()
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionManager.PermissionStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(LocalizedStringKey("permissions.status.granted"))
                    .foregroundColor(.green)
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(LocalizedStringKey("permissions.status.denied"))
                    .foregroundColor(.red)
            case .notDetermined:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.orange)
                Text(LocalizedStringKey("permissions.status.not_requested"))
                    .foregroundColor(.orange)
            case .unknown:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.gray)
                Text(LocalizedStringKey("permissions.status.unknown"))
                    .foregroundColor(.gray)
            }
        }
        .font(.subheadline)
    }
}
