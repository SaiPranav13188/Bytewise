//
//  Places.swift
//  Bytewise
//

import AppKit
import SwiftUI

/// Folders listed in the sidebar, so a scan is one click away.
enum Place: String, CaseIterable, Identifiable {
    case disk, home, downloads, documents, desktop, applications, library

    var id: String { rawValue }

    var url: URL {
        let home = URL(fileURLWithPath: RulesEngine.realHomePath, isDirectory: true)
        switch self {
        case .disk: return URL(fileURLWithPath: "/", isDirectory: true)
        case .home: return home
        case .downloads: return home.appendingPathComponent("Downloads", isDirectory: true)
        case .documents: return home.appendingPathComponent("Documents", isDirectory: true)
        case .desktop: return home.appendingPathComponent("Desktop", isDirectory: true)
        case .applications: return URL(fileURLWithPath: "/Applications", isDirectory: true)
        case .library: return home.appendingPathComponent("Library", isDirectory: true)
        }
    }

    var title: String {
        switch self {
        case .disk: DiskSpace.current()?.name ?? "Macintosh HD"
        case .home: "Home"
        case .downloads: "Downloads"
        case .documents: "Documents"
        case .desktop: "Desktop"
        case .applications: "Applications"
        case .library: "Library"
        }
    }

    var symbol: String {
        switch self {
        case .disk: "internaldrive.fill"
        case .home: "house.fill"
        case .downloads: "arrow.down.circle.fill"
        case .documents: "doc.fill"
        case .desktop: "menubar.dock.rectangle"
        case .applications: "square.grid.3x3.fill"
        case .library: "books.vertical.fill"
        }
    }

    var tint: Color {
        switch self {
        case .disk: .gray
        case .home: .indigo
        case .downloads: .blue
        case .documents: .orange
        case .desktop: .pink
        case .applications: .green
        case .library: .brown
        }
    }

    static var folders: [Place] { allCases.filter { $0 != .disk } }
}

/// Space on the startup disk.
struct DiskSpace {
    let name: String
    let total: Int64
    let available: Int64

    var used: Int64 { max(0, total - available) }

    static func current() -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        return DiskSpace(name: values.volumeName ?? "Macintosh HD",
                         total: Int64(total),
                         available: values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

/// Remembers which folders the user has let Bytewise read. The app is
/// sandboxed, so each folder has to be picked once in an Open panel; after
/// that a saved bookmark opens it straight away.
enum FolderAccess {
    private static let key = "folderBookmarks"

    private static var bookmarks: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func hasAccess(to url: URL) -> Bool {
        bookmarks[url.path] != nil
    }

    /// A URL that can be opened through its security scope, or nil when
    /// the user has not picked this folder yet.
    static func savedURL(for url: URL) -> URL? {
        guard let data = bookmarks[url.path] else { return nil }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                      relativeTo: nil, bookmarkDataIsStale: &stale) else {
            bookmarks[url.path] = nil
            return nil
        }
        if stale { remember(resolved) }
        return resolved
    }

    /// Saves access to a folder the user picked.
    static func remember(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[url.path] = data
        }
    }

    /// Asks the user to confirm `url` in an Open panel, which is how a
    /// sandboxed app gets permission to read it. Returns the picked folder.
    static func request(_ url: URL?, title: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = url
        panel.prompt = "Scan"
        if let title {
            panel.message = "Select \(title) and click Scan. Bytewise remembers this, so you only do it once."
        }
        guard panel.runModal() == .OK, let picked = panel.url else { return nil }
        remember(picked)
        return picked
    }
}
