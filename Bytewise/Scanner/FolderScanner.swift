//
//  FolderScanner.swift
//  Bytewise
//

import Foundation

/// One direct child of the scanned folder, with its total allocated size.
nonisolated struct ScanItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
}

/// How far a scan has got. `itemsDone` and `itemsTotal` count the direct
/// children of the scanned folder; `filesScanned` counts everything visited.
nonisolated struct ScanProgress: Sendable {
    var itemsDone = 0
    var itemsTotal = 0
    var currentItem = ""
    var filesScanned = 0
}

/// Scans a folder off the main thread. Sizes use allocated bytes and
/// symbolic links are not followed, so nothing is counted twice through a link.
nonisolated enum FolderScanner {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey
    ]

    /// How many files to visit between progress reports.
    private static let progressInterval = 500

    /// Returns the `limit` largest direct children of `root`, folders sized
    /// by everything inside them. Runs in the background and stops with
    /// `CancellationError` when the calling task is cancelled.
    @concurrent
    static func largestItems(
        in root: URL,
        limit: Int = 20,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> [ScanItem] {
        try scan(root, limit: limit, progress: progress)
    }

    private static func scan(
        _ root: URL,
        limit: Int,
        progress: (ScanProgress) -> Void
    ) throws -> [ScanItem] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []

        var state = ScanProgress(itemsTotal: children.count)
        var items: [ScanItem] = []
        for child in children {
            try Task.checkCancellation()
            state.currentItem = child.lastPathComponent
            progress(state)

            if let values = try? child.resourceValues(forKeys: Set(keys)),
               values.isSymbolicLink != true {
                let isDirectory = values.isDirectory ?? false
                let size: Int64
                if isDirectory {
                    size = try folderSize(child, state: &state, progress: progress)
                } else {
                    size = Int64(values.totalFileAllocatedSize ?? 0)
                    state.filesScanned += 1
                }
                items.append(ScanItem(url: child, name: child.lastPathComponent,
                                      isDirectory: isDirectory, size: size))
            }
            state.itemsDone += 1
        }
        progress(state)

        return Array(items.sorted { $0.size > $1.size }.prefix(limit))
    }

    /// Sums allocated sizes of every file under `folder`. Unreadable
    /// subfolders are skipped instead of failing the scan.
    private static func folderSize(
        _ folder: URL,
        state: inout ScanProgress,
        progress: (ScanProgress) -> Void
    ) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true,
                  values.isDirectory != true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
            state.filesScanned += 1
            if state.filesScanned % progressInterval == 0 {
                try Task.checkCancellation()
                progress(state)
            }
        }
        return total
    }
}
