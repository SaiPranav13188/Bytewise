//
//  FolderScanner.swift
//  Bytewise
//

import Foundation

/// How far a scan has got. `itemsDone` and `itemsTotal` count the direct
/// children of the scanned folder; `filesScanned` counts every file visited.
nonisolated struct ScanProgress: Sendable {
    var itemsDone = 0
    var itemsTotal = 0
    var currentItem = ""
    var filesScanned = 0
}

/// Scans a folder off the main thread and builds its full tree. Sizes use
/// allocated bytes and symbolic links are not followed, so nothing is counted
/// twice through a link.
nonisolated enum FolderScanner {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey
    ]

    /// How many files to visit between progress reports.
    private static let progressInterval = 500

    /// Returns the tree rooted at `root`. Runs in the background and stops
    /// with `CancellationError` when the calling task is cancelled.
    @concurrent
    static func scan(
        _ root: URL,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws -> FileNode {
        try buildTree(root, progress: progress)
    }

    private static func buildTree(
        _ root: URL,
        progress: (ScanProgress) -> Void
    ) throws -> FileNode {
        let rootNode = FileNode(url: root, isDirectory: true, kind: .folder)
        var state = ScanProgress(
            itemsTotal: (try? FileManager.default.contentsOfDirectory(atPath: root.path).count) ?? 0)

        // Unreadable subfolders are skipped instead of failing the scan.
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return rootNode }

        let keySet = Set(keys)
        var kinds: [String: FileKind] = [:]
        // stack[n] is the folder at depth n on the current path; the
        // enumerator visits each folder before its contents.
        var stack = [rootNode]
        var topLevelSeen = 0

        for case let url as URL in enumerator {
            let level = enumerator.level
            if level == 1 {
                try Task.checkCancellation()
                state.itemsDone = topLevelSeen
                state.currentItem = url.lastPathComponent
                topLevelSeen += 1
                progress(state)
            }
            if stack.count > level { stack.removeLast(stack.count - level) }
            guard stack.count == level,
                  let values = try? url.resourceValues(forKeys: keySet) else {
                enumerator.skipDescendants()
                continue
            }
            if values.isSymbolicLink == true { continue }

            let parent = stack[stack.count - 1]
            if values.isDirectory == true {
                let node = FileNode(url: url, isDirectory: true, kind: .folder)
                parent.addChild(node)
                stack.append(node)
            } else {
                let ext = url.pathExtension.lowercased()
                let kind = kinds[ext] ?? {
                    let kind = FileKind(fileExtension: ext)
                    kinds[ext] = kind
                    return kind
                }()
                parent.addChild(FileNode(url: url, isDirectory: false, kind: kind,
                                         size: Int64(values.totalFileAllocatedSize ?? 0)))
                state.filesScanned += 1
                if state.filesScanned % progressInterval == 0 {
                    try Task.checkCancellation()
                    progress(state)
                }
            }
        }

        state.itemsDone = state.itemsTotal
        progress(state)
        rootNode.rollUpSizes()
        return rootNode
    }
}
