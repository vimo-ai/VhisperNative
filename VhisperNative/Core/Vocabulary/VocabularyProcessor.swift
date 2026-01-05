//
//  VocabularyProcessor.swift
//  VhisperNative
//
//  Post-ASR vocabulary replacement processor
//

import Foundation

/// Processor for applying vocabulary replacements to transcribed text
final class VocabularyProcessor: @unchecked Sendable {
    private var replacementDict: [String: String] = [:]

    init(config: VocabularyConfig) {
        updateConfig(config)
    }

    /// Update the processor with new vocabulary configuration
    func updateConfig(_ config: VocabularyConfig) {
        guard config.enabled && config.enablePostASRReplacement else {
            replacementDict = [:]
            return
        }
        replacementDict = config.replacementDictionary
    }

    /// Apply vocabulary replacements to text
    /// - Parameter text: The input text to process
    /// - Returns: Text with vocabulary replacements applied
    func process(_ text: String) -> String {
        guard !replacementDict.isEmpty else { return text }

        var result = text

        // Sort by length (longest first) to avoid partial replacements
        let sortedKeys = replacementDict.keys.sorted { $0.count > $1.count }

        for key in sortedKeys {
            guard let replacement = replacementDict[key] else { continue }

            // Case-insensitive replacement using regex
            let pattern = NSRegularExpression.escapedPattern(for: key)
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }

        return result
    }
}
