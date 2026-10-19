//
//  AppSettings.swift
//  Bytewise
//

import Foundation

/// Keys and defaults for the Settings window, stored in UserDefaults.
enum AppSettings {
    /// Folders to leave out of scans, one path per line.
    static let excludedFoldersKey = "excludedFolders"
    static let holdingDaysKey = "holdingDays"
    static let hasSeenWelcomeKey = "hasSeenWelcome"

    static let holdingDayChoices = [7, 14, 30, 60, 90]

    static func excludedFolders(from text: String) -> [String] {
        text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static var excludedFolders: Set<String> {
        Set(excludedFolders(from: UserDefaults.standard.string(forKey: excludedFoldersKey) ?? ""))
    }

    static var holdingDays: Int {
        let days = UserDefaults.standard.integer(forKey: holdingDaysKey)
        return days > 0 ? days : HoldingArea.defaultRetentionDays
    }
}
