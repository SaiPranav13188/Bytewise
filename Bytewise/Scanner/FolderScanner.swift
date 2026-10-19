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

/// Scans a folder off the main thread. Sizes use allocated bytes and
/// symbolic links are not followed, so nothing is counted twice through a link.
nonisolated enum FolderScanner {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey
    ]

    /// Returns the `limit` largest direct children of `root`, folders sized
    /// by everything inside them.
    static func largestItems(in root: URL, limit: Int = 20) throws -> [ScanItem] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        )) ?? []

        var items: [ScanItem] = []
        for child in children {
            try Task.checkCancellation()
            guard let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true else { continue }

            let isDirectory = values.isDirectory ?? false
            let size = isDirectory
                ? try folderSize(child)
                : Int64(values.totalFileAllocatedSize ?? 0)
            items.append(ScanItem(url: child, name: child.lastPathComponent,
                                  isDirectory: isDirectory, size: size))
        }

        return Array(items.sorted { $0.size > $1.size }.prefix(limit))
    }

    /// Sums allocated sizes of every file under `folder`. Unreadable
    /// subfolders are skipped instead of failing the scan.
    private static func folderSize(_ folder: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            if count % 1000 == 0 { try Task.checkCancellation() }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true,
                  values.isDirectory != true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
