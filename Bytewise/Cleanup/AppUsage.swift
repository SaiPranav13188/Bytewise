//
//  AppUsage.swift
//  Bytewise
//

import AppKit

nonisolated struct RunningApp: Sendable {
    let name: String
    let bundleID: String?

    /// Apps open right now, except Bytewise itself.
    @MainActor
    static func current() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let name = app.localizedName else { return nil }
            return RunningApp(name: name, bundleID: app.bundleIdentifier)
        }
    }
}

/// Best-effort check for whether an open app owns an item, by comparing
/// folder names with app names and bundle IDs. Caches are usually named
/// after one or the other, e.g. "com.google.Chrome" or "Google/Chrome".
nonisolated enum AppUsage {
    /// `chains` are runs of folder names, parent first, such as the item's
    /// path and its paths to its children. Neighbouring names are also
    /// joined, so "Google" + "Chrome" matches the app "Google Chrome".
    static func app(using chains: [[String]], among apps: [RunningApp]) -> String? {
        var tokens = Set<String>()
        var rawNames: [String] = []
        for chain in chains {
            for (index, name) in chain.enumerated() {
                tokens.insert(normalize(name))
                rawNames.append(name.lowercased())
                if index > 0 { tokens.insert(normalize(chain[index - 1] + name)) }
            }
        }

        for app in apps {
            let appName = normalize(app.name)
            if appName.count >= 3 && tokens.contains(appName) { return app.name }
            if let bundleID = app.bundleID?.lowercased(),
               rawNames.contains(where: { $0 == bundleID || $0.hasPrefix(bundleID + ".") }) {
                return app.name
            }
        }
        return nil
    }

    private static func normalize(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
