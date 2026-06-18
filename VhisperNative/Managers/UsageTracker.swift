//
//  UsageTracker.swift
//  VhisperNative
//
//  Track ASR usage duration by day for cost estimation
//

import Foundation

/// Daily usage statistics
struct DailyUsage: Codable, Identifiable {
    let date: String  // yyyy-MM-dd format
    var totalDurationSec: Double
    var count: Int

    var id: String { date }

    /// Formatted duration string
    var formattedDuration: String {
        if totalDurationSec < 60 {
            return String(format: "%.1f 秒", totalDurationSec)
        } else {
            let minutes = Int(totalDurationSec / 60)
            let seconds = Int(totalDurationSec.truncatingRemainder(dividingBy: 60))
            return "\(minutes) 分 \(seconds) 秒"
        }
    }
}

/// Usage tracker for monitoring ASR costs
@MainActor
class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    private let userDefaultsKey = "vhisper_usage_data"
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // Current session tracking
    private var sessionStartTime: Date?
    private var currentProvider: String?

    // Published data for UI
    @Published private(set) var dailyUsages: [DailyUsage] = []

    private init() {
        loadData()
    }

    // MARK: - Session Tracking

    /// Call when recording starts
    func startSession(provider: String) {
        sessionStartTime = Date()
        currentProvider = provider
    }

    /// Call when recording ends (finalResult or cancelled)
    func endSession() {
        guard let startTime = sessionStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)

        // Only record if duration > 0.5 seconds (filter out noise)
        if duration > 0.5 {
            recordUsage(durationSec: duration, provider: currentProvider ?? "unknown")
        }

        sessionStartTime = nil
        currentProvider = nil
    }

    /// Cancel session without recording (e.g., user cancelled)
    func cancelSession() {
        sessionStartTime = nil
        currentProvider = nil
    }

    // MARK: - Data Management

    private func recordUsage(durationSec: Double, provider: String) {
        let today = dateFormatter.string(from: Date())

        if let index = dailyUsages.firstIndex(where: { $0.date == today }) {
            dailyUsages[index].totalDurationSec += durationSec
            dailyUsages[index].count += 1
        } else {
            let newUsage = DailyUsage(date: today, totalDurationSec: durationSec, count: 1)
            dailyUsages.insert(newUsage, at: 0)
        }

        // Keep only last 30 days
        if dailyUsages.count > 30 {
            dailyUsages = Array(dailyUsages.prefix(30))
        }

        saveData()
    }

    private func loadData() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let usages = try? JSONDecoder().decode([DailyUsage].self, from: data) else {
            return
        }
        dailyUsages = usages
    }

    private func saveData() {
        guard let data = try? JSONEncoder().encode(dailyUsages) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    /// Clear all usage data
    func clearData() {
        dailyUsages = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Statistics

    /// Total duration for today
    var todayUsage: DailyUsage? {
        let today = dateFormatter.string(from: Date())
        return dailyUsages.first { $0.date == today }
    }

    /// Total duration for the last 7 days
    var weeklyTotalSec: Double {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        return dailyUsages
            .filter { usage in
                guard let date = dateFormatter.date(from: usage.date) else { return false }
                return date >= weekAgo
            }
            .reduce(0) { $0 + $1.totalDurationSec }
    }
}
