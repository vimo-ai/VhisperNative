//
//  WaveformWindow.swift
//  VhisperNative
//
//  Floating window for waveform overlay
//

import SwiftUI
import Combine

// MARK: - WaveformWindow

/// Floating window that stays on top
class WaveformWindow: NSWindow {
    private let maxWidth: CGFloat = 320
    private let maxHeight: CGFloat = 100

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 150, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = true
        self.hasShadow = false

        self.orderOut(nil)
    }

    /// Show window at mouse screen's bottom center
    func show() {
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first!

        let visibleRect = currentScreen.visibleFrame
        let size = self.frame.size
        let x = visibleRect.midX - size.width / 2
        let y = visibleRect.minY + 80

        self.setFrameOrigin(NSPoint(x: x, y: y))
        self.orderFront(nil)
    }

    func updateSize(width: CGFloat, height: CGFloat) {
        let newWidth = min(width, maxWidth)
        let newHeight = min(height, maxHeight)

        let currentFrame = self.frame
        let deltaWidth = newWidth - currentFrame.width
        let deltaHeight = newHeight - currentFrame.height

        let newX = currentFrame.origin.x - deltaWidth / 2
        let newY = currentFrame.origin.y - deltaHeight

        self.setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true, animate: true)
    }

    func hide() {
        self.orderOut(nil)
    }
}

// MARK: - WaveformOverlayController

/// Waveform overlay window manager (singleton)
class WaveformOverlayController {
    static let shared = WaveformOverlayController()

    private var window: WaveformWindow?
    private var hostingView: NSHostingView<MetaballWaveformView>?
    private var monitor: AudioLevelMonitor?
    private var cancellable: AnyCancellable?

    private var recognizedText: String = ""
    private var stashText: String = ""

    private init() {}

    func show(with monitor: AudioLevelMonitor) {
        recognizedText = ""
        stashText = ""

        if window == nil {
            window = WaveformWindow()
        }

        self.monitor = monitor

        let metaballView = MetaballWaveformView(
            levels: monitor.levels,
            recognizedText: recognizedText,
            stashText: stashText
        )
        hostingView = NSHostingView(rootView: metaballView)

        window?.contentView = hostingView

        cancellable = monitor.$levels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLevels in
                self?.updateView(levels: newLevels)
            }

        window?.show()
    }

    func hide() {
        window?.hide()
        cancellable?.cancel()
        cancellable = nil
        monitor = nil
        recognizedText = ""
        stashText = ""
    }

    func updateText(text: String, stash: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.recognizedText = text
            self.stashText = stash
            self.updateView(levels: self.monitor?.levels ?? [])
        }
    }

    func clearText() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.recognizedText = ""
            self.stashText = ""
            self.updateView(levels: self.monitor?.levels ?? [])
        }
    }

    private func updateView(levels: [Float]) {
        guard let hostingView = hostingView else { return }

        let updatedView = MetaballWaveformView(
            levels: levels,
            recognizedText: recognizedText,
            stashText: stashText
        )
        hostingView.rootView = updatedView
    }
}
