//
//  AppUsage.swift
//  Bytewise
//

import AppKit

nonisolated struct RunningApp: Sendable {
    let name: String
    let bundleID: String?
    /// The program's file name inside the app, which data folders are
    /// sometimes named after instead of the app, such as "Code".
    var executableName: String? = nil

    /// Apps open right now, except Bytewise itself.
    @MainActor
    static func current() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let name = app.localizedName else { return nil }
            return RunningApp(name: name, bundleID: app.bundleIdentifier,
                              executableName: app.executableURL?.lastPathComponent)
        }
    }
}

/// Best-effort check for whether an open app owns an item, by comparing
/// folder names with app names, program names and bundle IDs. Caches are
/// usually named after one of these, e.g. "com.google.Chrome" or
/// "Google/Chrome". A wrong match only means an item is skipped, so the
/// check leans towards matching.
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
            if let program = app.executableName.map(normalize), program.count >= 3,
               !genericPrograms.contains(program), tokens.contains(program) {
                return app.name
            }
            // The last part of a bundle ID, e.g. "VSCode" in com.microsoft.VSCode.
            if let last = app.bundleID?.split(separator: ".").last.map({ normalize(String($0)) }),
               last.count >= 5, tokens.contains(last) {
                return app.name
            }
            if let bundleID = app.bundleID?.lowercased(),
               rawNames.contains(where: { $0 == bundleID || $0.hasPrefix(bundleID + ".") }) {
                return app.name
            }
        }
        return nil
    }

    /// Program names shared by many apps, which say nothing about the owner.
    private static let genericPrograms: Set<String> = ["electron", "java", "python", "python3", "node", "helper"]

    private static func normalize(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
