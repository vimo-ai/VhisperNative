//
//  LocalizationManager.swift
//  VhisperNative
//
//  Manages app language settings and localization
//

import Foundation
import SwiftUI
import Combine

// MARK: - Localization Manager

@MainActor
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var currentLanguage: AppLanguage = .system
    @Published private(set) var bundle: Bundle = .main

    /// Notification name for language changes
    static let languageDidChangeNotification = Notification.Name("LocalizationManagerLanguageDidChange")

    private init() {
        // Load saved language preference
        loadSavedLanguage()
    }

    /// Set the app language
    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }

        currentLanguage = language
        updateBundle()

        // Post notification for non-SwiftUI components (like NSMenu)
        NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: nil)
    }

    /// Get localized string for the current language
    func localizedString(_ key: String, comment: String = "") -> String {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Load saved language preference from config
    func loadSavedLanguage() {
        // This will be called after VhisperManager loads config
        // For now, default to system
    }

    /// Update language from config
    func updateFromConfig(_ language: AppLanguage) {
        currentLanguage = language
        updateBundle()
    }

    // MARK: - Private

    private func updateBundle() {
        let languageCode: String

        if currentLanguage == .system {
            // Use system preferred language
            languageCode = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"
        } else {
            languageCode = currentLanguage.rawValue
        }

        // Find the appropriate .lproj bundle
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            bundle = languageBundle
        } else if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
                  let englishBundle = Bundle(path: path) {
            // Fallback to English
            bundle = englishBundle
        } else {
            bundle = .main
        }
    }
}

// MARK: - Localized String Extension

@MainActor
extension String {
    /// Get localized string using LocalizationManager
    func localized(comment: String = "") -> String {
        return LocalizationManager.shared.localizedString(self, comment: comment)
    }
}

// MARK: - View Extension for Localization

@MainActor
extension View {
    /// Force view refresh when language changes
    func localizedRefresh() -> some View {
        self.id(LocalizationManager.shared.currentLanguage)
    }
}
