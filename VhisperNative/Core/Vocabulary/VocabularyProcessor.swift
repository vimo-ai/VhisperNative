//
//  VocabularyProcessor.swift
//  VhisperNative
//
//  Post-ASR vocabulary replacement processor
//

import Foundation

/// Cached regex pattern with its replacement string
private struct CachedReplacement {
    let regex: NSRegularExpression
    let replacement: String
}

/// Processor for applying vocabulary replacements to transcribed text
final class VocabularyProcessor: @unchecked Sendable {
    // Pre-compiled regex patterns sorted by key length (longest first)
    private var cachedReplacements: [CachedReplacement] = []

    init(config: VocabularyConfig) {
        updateConfig(config)
    }

    /// Update the processor with new vocabulary configuration
    /// Pre-compiles all regex patterns for efficient repeated use
    func updateConfig(_ config: VocabularyConfig) {
        guard config.enabled && config.enablePostASRReplacement else {
            cachedReplacements = []
            return
        }

        // Sort by length (longest first) to avoid partial replacements
        let sortedKeys = config.replacementDictionary.keys.sorted { $0.count > $1.count }

        // Pre-compile all regex patterns
        cachedReplacements = sortedKeys.compactMap { key in
            guard let replacement = config.replacementDictionary[key] else { return nil }
            let pattern = NSRegularExpression.escapedPattern(for: key)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return CachedReplacement(regex: regex, replacement: replacement)
        }
    }

    /// Apply vocabulary replacements to text
    /// - Parameter text: The input text to process
    /// - Returns: Text with vocabulary replacements applied
    func process(_ text: String) -> String {
        guard !cachedReplacements.isEmpty else { return text }

        var result = text

        // Use pre-compiled regex patterns
        for cached in cachedReplacements {
            result = cached.regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: cached.replacement
            )
        }

        return result
    }
}
