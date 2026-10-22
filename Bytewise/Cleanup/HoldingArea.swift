//
//  HoldingArea.swift
//  Bytewise
//

import Foundation

/// Something the user picked for cleanup.
nonisolated struct CleanupCandidate: Sendable {
    let url: URL
    let size: Int64
    let assessment: Assessment
    /// The name of an open app that uses this item, if any.
    let usedBy: String?
}

/// Which item is on disk at a path: its disk, its file number and whether
/// it is a symbolic link. If any of these change after the preview, a
/// different item is now at that path.
nonisolated struct FileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let isSymbolicLink: Bool

    /// The item at `url` itself, without following a symbolic link.
    init?(of url: URL) {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        device = UInt64(info.st_dev)
        inode = UInt64(info.st_ino)
        isSymbolicLink = (info.st_mode & S_IFMT) == S_IFLNK
    }
}

/// One line of a cleanup preview: the item, and why it will be skipped if
/// it will not be moved.
nonisolated struct PlannedMove: Identifiable, Sendable {
    let id = UUID()
    let candidate: CleanupCandidate
    let skipReason: String?
    /// The item the preview showed. Moving stops if it has changed.
    var identity: FileIdentity?

    var willMove: Bool { skipReason == nil }
}

/// An item waiting in the holding area. Stored in the holding area's log.
nonisolated struct HeldItem: Codable, Identifiable, Sendable {
    let id: UUID
    let originalPath: String
    let heldPath: String
    let size: Int64
    let movedAt: Date
    let reason: String?
    /// Lets Bytewise write to the original location again after a relaunch,
    /// which the app sandbox would otherwise block.
    let scopeBookmark: Data?

    var name: String { (originalPath as NSString).lastPathComponent }
}

nonisolated struct MoveFailure: Sendable {
    let url: URL
    let message: String
}

nonisolated enum HoldingAreaError: LocalizedError {
    case missing(String)
    case invalidEntry(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name): "\(name) is no longer in the holding area."
        case .invalidEntry(let name): "The holding area's record for \(name) is damaged, so Bytewise left it alone."
        }
    }
}

/// A folder that Bytewise controls, where cleaned-up items wait before they
/// are deleted for good. Nothing is ever deleted directly: items are moved
/// here, every move is logged, and any item can be put back.
nonisolated struct HoldingArea: Sendable {
    /// Days before an item can be emptied, unless changed in Settings.
    static let defaultRetentionDays = 30

    let directory: URL

    /// The app's own holding area, inside its Application Support folder.
    static var standard: HoldingArea {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return HoldingArea(directory: support.appendingPathComponent("Bytewise/Holding", isDirectory: true))
    }

    private var logURL: URL { directory.appendingPathComponent("log.json") }

    /// Items currently held, newest first.
    func items() -> [HeldItem] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([HeldItem].self, from: data)) ?? [])
            .sorted { $0.movedAt > $1.movedAt }
    }

    /// Items held for more than `days` days, which may now be emptied.
    func expiredItems(olderThan days: Int, now: Date = Date()) -> [HeldItem] {
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        return items().filter { $0.movedAt < cutoff }
    }

    /// Decides what would be moved, without touching the disk. This is what
    /// the dry run shows.
    func plan(_ candidates: [CleanupCandidate]) -> [PlannedMove] {
        let holdingVolume = volume(of: directory.deletingLastPathComponent())
        let paths = candidates.map { $0.url.path }

        return candidates.map { candidate in
            let path = candidate.url.path
            let skip: String?
            switch candidate.assessment.verdict {
            case .keep:
                skip = "Marked Keep. Bytewise never moves these."
            case .managedByMacOS:
                skip = "Managed by macOS. Bytewise never moves these."
            case .unknown:
                skip = "No rule covers this item, so Bytewise will not move it."
            case .safeToClear, .review:
                if let app = candidate.usedBy {
                    skip = "\(app) is open. Quit it first."
                } else if let parent = paths.first(where: { path.hasPrefix($0 + "/") }) {
                    skip = "Already included in \((parent as NSString).lastPathComponent)."
                } else if path == directory.path || path.hasPrefix(directory.path + "/") {
                    skip = "Already in the holding area."
                } else if !FileManager.default.fileExists(atPath: path) {
                    skip = "No longer exists."
                } else if let holdingVolume, let itemVolume = volume(of: candidate.url),
                          !holdingVolume.isEqual(itemVolume) {
                    skip = "On a different disk. Moving between disks is not supported yet."
                } else {
                    skip = nil
                }
            }
            return PlannedMove(candidate: candidate, skipReason: skip,
                               identity: skip == nil ? FileIdentity(of: candidate.url) : nil)
        }
    }

    /// Moves every item in `plan` that is marked to move. Items are moved
    /// one by one and the log is saved after each, so a failure part way
    /// leaves an accurate record.
    func move(_ plan: [PlannedMove], scopeBookmark: Data?) -> (moved: [HeldItem], failures: [MoveFailure]) {
        var moved: [HeldItem] = []
        var failures: [MoveFailure] = []
        var log = items()

        for entry in plan where entry.willMove {
            let source = entry.candidate.url
            // Check again right before moving: the item must be the one the
            // preview showed, not something put at the same path since.
            guard let identity = entry.identity, FileIdentity(of: source) == identity else {
                failures.append(MoveFailure(url: source, message: "It changed after the preview, so it was not moved. Review it again."))
                continue
            }
            guard !isInside(source.path) && source.path != directory.path else {
                failures.append(MoveFailure(url: source, message: "It is already in the holding area."))
                continue
            }
            let id = UUID()
            let slot = directory.appendingPathComponent(id.uuidString, isDirectory: true)
            let destination = slot.appendingPathComponent(source.lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: source, to: destination)
                let held = HeldItem(id: id, originalPath: source.path, heldPath: destination.path,
                                    size: entry.candidate.size, movedAt: Date(),
                                    reason: entry.candidate.assessment.reason, scopeBookmark: scopeBookmark)
                log.append(held)
                try save(log)
                moved.append(held)
            } catch {
                try? FileManager.default.removeItem(at: slot)
                failures.append(MoveFailure(url: source, message: FriendlyError.message(for: error)))
            }
        }
        return (moved, failures)
    }

    /// Puts an item back where it came from. If something new now has that
    /// name, the item comes back as "name (restored)". Returns where it went.
    @discardableResult
    func restore(_ item: HeldItem) throws -> URL {
        try validate(item)
        let held = URL(fileURLWithPath: item.heldPath)
        guard FileManager.default.fileExists(atPath: held.path) else {
            throw HoldingAreaError.missing(item.name)
        }

        var scope: URL?
        if let bookmark = item.scopeBookmark {
            var isStale = false
            scope = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                             relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
        let accessing = scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scope?.stopAccessingSecurityScopedResource() } }

        let original = URL(fileURLWithPath: item.originalPath)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let target = Self.freeName(for: original)
        try FileManager.default.moveItem(at: held, to: target)
        try? FileManager.default.removeItem(at: held.deletingLastPathComponent())
        try save(items().filter { $0.id != item.id })
        return target
    }

    /// Deletes a held item for good. Only called after the user confirms.
    func empty(_ item: HeldItem) throws {
        try validate(item)
        let slot = URL(fileURLWithPath: item.heldPath).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: slot.path) {
            try FileManager.default.removeItem(at: slot)
        }
        try save(items().filter { $0.id != item.id })
    }

    /// Checks a log entry before acting on it. The log is a file on disk,
    /// so a damaged or edited entry must not be able to point Bytewise at
    /// files outside the holding area.
    private func validate(_ item: HeldItem) throws {
        let held = URL(fileURLWithPath: item.heldPath)
        let slot = held.deletingLastPathComponent()
        guard Self.isPlain(item.heldPath), Self.isPlain(item.originalPath),
              slot.deletingLastPathComponent().path == directory.path,
              slot.lastPathComponent == item.id.uuidString,
              !held.lastPathComponent.isEmpty else {
            throw HoldingAreaError.invalidEntry(item.name)
        }
    }

    /// Whether `path` is somewhere below the holding area.
    private func isInside(_ path: String) -> Bool {
        Self.isPlain(path) && path.hasPrefix(directory.path + "/")
    }

    /// An absolute path with no "." or ".." parts, so it means what it says.
    private static func isPlain(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.split(separator: "/").contains { $0 == ".." || $0 == "." }
    }

    private func save(_ log: [HeldItem]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(log).write(to: logURL, options: .atomic)
    }

    private func volume(of url: URL) -> (any NSObjectProtocol)? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier
    }

    /// `url` if nothing is there, otherwise "name (restored).ext",
    /// "name (restored 2).ext" and so on.
    static func freeName(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var count = 1
        while true {
            let suffix = count == 1 ? " (restored)" : " (restored \(count))"
            let name = ext.isEmpty ? base + suffix : "\(base)\(suffix).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            count += 1
        }
    }
}
