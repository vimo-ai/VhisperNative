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
@MainActor
final class WaveformOverlayController {
    static let shared = WaveformOverlayController()

    private var window: WaveformWindow?
    private var hostingView: NSHostingView<MetaballWaveformView>?
    private var monitor: AudioLevelMonitor?
    private var cancellable: AnyCancellable?

    // Use view model for efficient in-place updates instead of view reconstruction
    private let viewModel = WaveformViewModel()

    private init() {}

    func show(with monitor: AudioLevelMonitor) {
        viewModel.clear()
        viewModel.update(levels: monitor.levels)

        if window == nil {
            window = WaveformWindow()
        }

        self.monitor = monitor

        // Create view once with view model - subsequent updates modify view model properties
        let metaballView = MetaballWaveformView(viewModel: viewModel)
        hostingView = NSHostingView(rootView: metaballView)

        window?.contentView = hostingView

        cancellable = monitor.$levels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLevels in
                // Update view model in-place instead of recreating view
                self?.viewModel.update(levels: newLevels)
            }

        window?.show()
    }

    func hide() {
        window?.hide()
        cancellable?.cancel()
        cancellable = nil
        monitor = nil
        viewModel.clear()
    }

    func updateText(text: String, stash: String) {
        // Update view model directly - no view reconstruction needed
        viewModel.update(text: text, stash: stash)
    }

    func clearText() {
        // Update view model directly - no view reconstruction needed
        viewModel.clear()
    }
}
