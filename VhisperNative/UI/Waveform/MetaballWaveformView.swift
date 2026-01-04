//
//  MetaballWaveformView.swift
//  VhisperNative
//
//  Metaball-style waveform visualization with glass effect
//

import SwiftUI
import Combine

// MARK: - MetaballWaveformView

/// Metaball-style waveform view
/// Top layer: recognized text (dynamic width)
/// Bottom layer: waveform display
/// Both layers merged with alphaThreshold + blur
struct MetaballWaveformView: View {
    let levels: [Float]
    let recognizedText: String
    let stashText: String

    // Configuration
    private let waveformWidth: CGFloat = 120
    private let waveformHeight: CGFloat = 36
    private let minTextWidth: CGFloat = 60
    private let maxTextWidth: CGFloat = 280

    var body: some View {
        let displayText = recognizedText + stashText
        let hasText = !displayText.isEmpty

        VStack(spacing: -4) {
            // Text bubble
            if hasText {
                Text(displayText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.85, anchor: .bottom).combined(with: .opacity)
                    ))
            }

            // Waveform bars
            WaveformBarsView(levels: levels)
                .frame(width: waveformWidth - 28, height: waveformHeight - 16)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hasText)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: displayText)
    }
}

// MARK: - WaveformBarsView

struct WaveformBarsView: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<paddedLevels.count, id: \.self) { index in
                WaveformBar(level: paddedLevels[index])
            }
        }
    }

    private var paddedLevels: [Float] {
        if levels.count >= 20 {
            return Array(levels.prefix(20))
        } else if levels.isEmpty {
            return Array(repeating: 0.1, count: 20)
        } else {
            var result: [Float] = []
            let step = Float(levels.count - 1) / 19.0
            for i in 0..<20 {
                let idx = Float(i) * step
                let lower = Int(idx)
                let upper = min(lower + 1, levels.count - 1)
                let frac = idx - Float(lower)
                result.append(levels[lower] * (1 - frac) + levels[upper] * frac)
            }
            return result
        }
    }
}

// MARK: - WaveformBar

struct WaveformBar: View {
    let level: Float

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(.white.opacity(barOpacity))
            .frame(width: 1.5, height: barHeight)
            .animation(.easeOut(duration: 0.06), value: level)
    }

    private var barHeight: CGFloat {
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 18
        return minHeight + CGFloat(level) * (maxHeight - minHeight)
    }

    private var barOpacity: Double {
        let minOpacity: Double = 0.25
        let maxOpacity: Double = 0.95
        return minOpacity + Double(level) * (maxOpacity - minOpacity)
    }
}
