//
//  RulesEngine.swift
//  Bytewise
//

import Foundation

/// What Bytewise thinks should happen to an item.
nonisolated enum Verdict: Sendable {
    case safeToClear      // caches that rebuild themselves
    case review           // user should decide
    case keep             // user data
    case managedByMacOS   // do not touch
    case unknown          // no rule matched

    var label: String {
        switch self {
        case .safeToClear: "Safe to clear"
        case .review: "Review"
        case .keep: "Keep"
        case .managedByMacOS: "Managed by macOS"
        case .unknown: "Unknown"
        }
    }
}

nonisolated struct Assessment: Sendable, Equatable {
    let verdict: Verdict
    /// One line in plain words, or nil when no rule matched.
    let reason: String?
}

nonisolated struct Rule: Sendable {
    enum Pattern: Sendable {
        /// Exactly this path. Paths may start with `~` for the home folder.
        case at(String)
        /// Everything below this path, but not the path itself.
        case inside(String)
        /// This path and everything below it.
        case atOrInside(String)
        /// Any path starting with this text, e.g. `~/Library/Caches/com.apple.`
        case pathPrefix(String)
        /// Any folder with this name, and everything inside it.
        case folderNamed(String)
        /// Files with one of these extensions anywhere below a path.
        case fileTypes(inside: String, extensions: Set<String>)
    }

    let pattern: Pattern
    let verdict: Verdict
    let reason: String
}

/// Labels locations with a verdict and a one-line reason. Rules are checked
/// in order and the first match wins, so user data and system rules come
/// first and can never be overridden by a "safe" rule further down. When
/// unsure, rules say `review`, never `safeToClear`.
nonisolated struct RulesEngine: Sendable {
    let home: String
    let rules: [Rule]

    init(home: String = RulesEngine.realHomePath, rules: [Rule] = RulesEngine.defaultRules) {
        self.home = home
        self.rules = rules
    }

    func assess(_ url: URL) -> Assessment {
        // Not `standardizedFileURL`: it rewrites /private/var as /var, which
        // would slip past the /private rule.
        var path = url.path
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        // A path that steps up or sideways could point anywhere, so no rule
        // can vouch for it.
        let parts = path.split(separator: "/")
        if !path.hasPrefix("/") || parts.contains(where: { $0 == ".." || $0 == "." }) {
            return Assessment(verdict: .unknown, reason: nil)
        }
        let folded = path.lowercased()
        for rule in rules {
            // Mac disks usually ignore case, so "~/documents" is the same
            // folder as "~/Documents". Protective rules ignore case too;
            // rules that allow cleanup match exactly, which is stricter.
            let isProtective = rule.verdict == .keep || rule.verdict == .managedByMacOS
            let hit = isProtective
                ? matches(rule.pattern, path: folded, url: url, ignoringCase: true)
                : matches(rule.pattern, path: path, url: url, ignoringCase: false)
            if hit { return Assessment(verdict: rule.verdict, reason: rule.reason) }
        }
        return Assessment(verdict: .unknown, reason: nil)
    }

    /// When `ignoringCase` is true, `path` must already be lowercased.
    private func matches(_ pattern: Rule.Pattern, path: String, url: URL, ignoringCase: Bool) -> Bool {
        let expand: (String) -> String = { ignoringCase ? self.expand($0).lowercased() : self.expand($0) }
        switch pattern {
        case .at(let base):
            return path == expand(base)
        case .inside(let base):
            return path.hasPrefix(expand(base) + "/")
        case .atOrInside(let base):
            let base = expand(base)
            return path == base || path.hasPrefix(base + "/")
        case .pathPrefix(let prefix):
            return path.hasPrefix(expand(prefix))
        case .folderNamed(let name):
            let name = ignoringCase ? name.lowercased() : name
            return path.split(separator: "/").contains { $0 == name }
        case .fileTypes(let base, let extensions):
            return path.hasPrefix(expand(base) + "/")
                && extensions.contains(url.pathExtension.lowercased())
        }
    }

    private func expand(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst() }
        return path
    }

    /// The user's real home folder. Inside the app sandbox, `NSHomeDirectory()`
    /// points at the app's container instead.
    static let realHomePath: String = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }()

    static let defaultRules: [Rule] = [
        // System locations. Never touch.
        Rule(pattern: .atOrInside("/System"), verdict: .managedByMacOS, reason: "Part of macOS. Do not touch."),
        Rule(pattern: .atOrInside("/Library"), verdict: .managedByMacOS, reason: "Shared system files used by macOS and all users."),
        Rule(pattern: .atOrInside("/private"), verdict: .managedByMacOS, reason: "macOS working files, including virtual memory and system logs."),
        Rule(pattern: .atOrInside("/var"), verdict: .managedByMacOS, reason: "macOS working files, including virtual memory and system logs."),
        Rule(pattern: .atOrInside("/tmp"), verdict: .managedByMacOS, reason: "Temporary files. macOS clears them on restart."),
        Rule(pattern: .atOrInside("/etc"), verdict: .managedByMacOS, reason: "System settings. Do not touch."),
        Rule(pattern: .atOrInside("/cores"), verdict: .managedByMacOS, reason: "Crash dumps managed by macOS."),
        Rule(pattern: .atOrInside("/usr"), verdict: .managedByMacOS, reason: "Part of macOS. Do not touch."),
        Rule(pattern: .atOrInside("/bin"), verdict: .managedByMacOS, reason: "Part of macOS. Do not touch."),
        Rule(pattern: .atOrInside("/sbin"), verdict: .managedByMacOS, reason: "Part of macOS. Do not touch."),
        Rule(pattern: .atOrInside("/Applications"), verdict: .keep, reason: "Installed apps. Remove an app by dragging it to the Trash in Finder."),

        // The user's own data. Never offered for cleanup.
        Rule(pattern: .atOrInside("~/Documents"), verdict: .keep, reason: "Your documents."),
        Rule(pattern: .atOrInside("~/Desktop"), verdict: .keep, reason: "Files on your desktop."),
        Rule(pattern: .atOrInside("~/Pictures"), verdict: .keep, reason: "Your pictures, including the Photos library."),
        Rule(pattern: .atOrInside("~/Movies"), verdict: .keep, reason: "Your videos."),
        Rule(pattern: .atOrInside("~/Music"), verdict: .keep, reason: "Your music."),
        Rule(pattern: .atOrInside("~/Library/Mobile Documents"), verdict: .keep, reason: "iCloud Drive. Removing files here removes them from iCloud too."),
        Rule(pattern: .atOrInside("~/Library/Mail"), verdict: .keep, reason: "Your email."),
        Rule(pattern: .atOrInside("~/Library/Messages"), verdict: .keep, reason: "Your messages and their attachments."),
        Rule(pattern: .atOrInside("~/Library/Containers"), verdict: .keep, reason: "Data for apps from the App Store. Managed by each app."),
        Rule(pattern: .atOrInside("~/Library/Group Containers"), verdict: .keep, reason: "Data shared between apps. Managed by the apps."),
        Rule(pattern: .atOrInside("~/Library/Keychains"), verdict: .keep, reason: "Your saved passwords and certificates."),
        Rule(pattern: .atOrInside("~/Library/Preferences"), verdict: .keep, reason: "App settings."),

        Rule(pattern: .atOrInside("~/.Trash"), verdict: .review, reason: "Already in the Trash. Empty the Trash in Finder to free this space."),

        // Developer files.
        Rule(pattern: .atOrInside("~/Library/Developer/Xcode/DerivedData"), verdict: .safeToClear, reason: "Xcode build files. Xcode rebuilds them when needed."),
        Rule(pattern: .atOrInside("~/Library/Developer/Xcode/Archives"), verdict: .review, reason: "App archives. Needed to read crash reports for builds you shipped."),
        Rule(pattern: .atOrInside("~/Library/Developer/Xcode/iOS DeviceSupport"), verdict: .review, reason: "Debug files for devices you connected. Xcode fetches them again when needed."),
        Rule(pattern: .atOrInside("~/Library/Developer/CoreSimulator"), verdict: .review, reason: "Simulators and their data. Some may need to be downloaded again."),

        // Caches.
        Rule(pattern: .pathPrefix("~/Library/Caches/com.apple."), verdict: .review, reason: "A macOS cache. Usually rebuilt, but leave it unless you know what it is."),
        Rule(pattern: .inside("~/Library/Caches"), verdict: .safeToClear, reason: "App cache. The app rebuilds it. Clear it while the app is closed."),
        Rule(pattern: .at("~/Library/Caches"), verdict: .review, reason: "Caches for all your apps. Open it to see each one."),

        // AI models. Above app data, so they get their own reasons.
        Rule(pattern: .atOrInside("~/.ollama"), verdict: .review, reason: "Ollama's AI models. Remove them with ollama rm so Ollama stays consistent."),
        Rule(pattern: .atOrInside("~/.cache/huggingface"), verdict: .review, reason: "Hugging Face downloads. Fetched again the next time a project needs them."),
        Rule(pattern: .atOrInside("~/.lmstudio/models"), verdict: .review, reason: "LM Studio models. Can be downloaded again from LM Studio."),
        Rule(pattern: .atOrInside("~/.cache/lm-studio"), verdict: .review, reason: "LM Studio models. Can be downloaded again from LM Studio."),
        Rule(pattern: .atOrInside("~/Library/Application Support/nomic.ai/GPT4All"), verdict: .review, reason: "GPT4All models and chats. Models can be downloaded again."),
        Rule(pattern: .atOrInside("~/.cache/torch"), verdict: .review, reason: "PyTorch downloads. Fetched again the next time a project loads them."),
        Rule(pattern: .folderNamed("OptGuideOnDeviceModel"), verdict: .review, reason: "Chrome's on-device AI model. Chrome downloads it again while its AI features are on."),

        // App data and logs.
        Rule(pattern: .atOrInside("~/Library/Application Support"), verdict: .review, reason: "App data. Some apps keep important files here."),
        Rule(pattern: .atOrInside("~/Library/Logs"), verdict: .review, reason: "Log files. Usually safe to remove, but useful for troubleshooting."),

        // Downloads.
        Rule(pattern: .fileTypes(inside: "~/Downloads", extensions: ["dmg", "pkg"]), verdict: .review, reason: "Installer. Usually already used and can be removed."),

        // Anywhere else.
        Rule(pattern: .folderNamed("node_modules"), verdict: .review, reason: "JavaScript packages. Reinstall with npm install, but it can be slow."),
    ]
}
