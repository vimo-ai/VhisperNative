//
//  MenuBarView.swift
//  VhisperNative
//
//  Menu bar popover view
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var manager: VhisperManager
    @EnvironmentObject var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(spacing: 12) {
            // Status display
            HStack {
                Image(systemName: manager.state.icon)
                    .font(.title2)
                    .foregroundColor(manager.state == .recording ? .red : .primary)
                    .symbolEffect(.pulse, isActive: manager.state == .recording)

                Text(manager.state.description)
                    .font(.headline)

                Spacer()

                Text(hotkeyManager.currentHotkey.displayString)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.top, 8)

            // Recording button
            Button(action: { manager.toggleRecording() }) {
                HStack {
                    Image(systemName: manager.state == .recording ? "stop.fill" : "mic.fill")
                    Text(manager.state == .recording ? "Stop" : "Start Recording")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.state == .recording ? .red : .accentColor)
            .disabled(manager.state == .processing)

            // Last result
            if !manager.lastResult.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Result:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(manager.lastResult)
                        .font(.callout)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }

            // Error message
            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }

            Divider()

            // Bottom buttons
            HStack {
                SettingsLink {
                    Text("Settings")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .frame(width: 280)
    }
}
