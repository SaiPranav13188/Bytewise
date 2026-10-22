//
//  ScanModel.swift
//  Bytewise
//

import Foundation
import Observation

/// Everything the main window shows: the scanned tree, the open folder,
/// scan progress, the cleanup selection and the last move for Undo.
@Observable
final class ScanModel {
    private(set) var folder: URL?
    private(set) var root: FileNode?
    var current: FileNode?
    private(set) var isScanning = false
    private(set) var progress = ScanProgress()
    private(set) var scanSeconds: Double?
    var statusMessage: String?
    var errorMessage: String?
    private(set) var unreadable: [URL] = []
    private(set) var aiModels: [AIModel] = []
    private(set) var selected: [ObjectIdentifier: FileNode] = [:]
    /// The last move, kept so it can be undone and put back on the map.
    private(set) var lastMoved: [(held: HeldItem, node: FileNode, parent: FileNode)] = []
    /// Bumped whenever the tree changes, so views redraw and recount.
    private(set) var treeVersion = 0
    private(set) var heldItems: [HeldItem] = []

    private var scanTask: Task<Void, Never>?
    private var scopeBookmark: Data?
    /// The scanned folder stays open while it is shown, so Finder icons
    /// and Show in Finder work for items inside it.
    private var openScope: URL?

    nonisolated static let rules = RulesEngine()
    nonisolated static let holdingArea = HoldingArea.standard

    init() {
        refreshHeldItems()
    }

    // MARK: Scanning

    /// Scans a sidebar place, asking for access the first time.
    func scan(_ place: Place) {
        if let url = FolderAccess.savedURL(for: place.url) {
            startScan(url)
        } else if let url = FolderAccess.request(place.url, title: place.title) {
            startScan(url)
        }
    }

    /// Asks for any folder, then scans it.
    func chooseFolder() {
        if let url = FolderAccess.request(folder, title: nil) {
            startScan(url)
        }
    }

    func rescan() {
        if let folder { startScan(folder) }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func startScan(_ url: URL) {
        scanTask?.cancel()
        openScope?.stopAccessingSecurityScopedResource()
        openScope = url.startAccessingSecurityScopedResource() ? url : nil
        folder = url
        root = nil
        current = nil
        unreadable = []
        selected = [:]
        lastMoved = []
        scopeBookmark = nil
        aiModels = []
        progress = ScanProgress()
        scanSeconds = nil
        statusMessage = nil
        errorMessage = nil
        isScanning = true

        scanTask = Task {
            // The app is sandboxed, so the picked folder must be opened
            // through its security scope before reading it.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            // Saved with each moved item so it can be restored after a relaunch.
            scopeBookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                  includingResourceValuesForKeys: nil, relativeTo: nil)

            // Progress arrives from the background scan; keep only the
            // latest report so the interface never falls behind.
            let (updates, continuation) = AsyncStream.makeStream(
                of: ScanProgress.self, bufferingPolicy: .bufferingNewest(1))
            let progressTask = Task {
                for await update in updates { progress = update }
            }
            defer { progressTask.cancel() }

            let start = Date()
            do {
                let result = try await FolderScanner.scan(url, excluding: AppSettings.excludedFolders) {
                    continuation.yield($0)
                }
                continuation.finish()
                await progressTask.value
                root = result.root
                current = result.root
                unreadable = result.unreadable
                aiModels = AIModelFinder.find(in: result.root)
                if result.root.children.isEmpty && result.unreadable.contains(where: { $0.path == url.path }) {
                    errorMessage = "Bytewise could not open this folder. macOS may be protecting it. Turn on Full Disk Access for Bytewise, then scan again."
                }
                scanSeconds = Date().timeIntervalSince(start)
            } catch is CancellationError {
                statusMessage = "Scan cancelled."
                folder = nil
            } catch {
                errorMessage = FriendlyError.message(for: error)
            }
            isScanning = false
        }
    }

    // MARK: Navigation

    /// Opens a folder, or the folder a file is in.
    func open(_ node: FileNode) {
        if let target = node.isDirectory ? node : node.parent {
            current = target
        }
    }

    func goUp() {
        if let parent = current?.parent { current = parent }
    }

    /// The path from the scanned folder down to the open one.
    var path: [FileNode] {
        var chain: [FileNode] = []
        var next = current
        while let step = next {
            chain.insert(step, at: 0)
            next = step.parent
        }
        return chain
    }

    // MARK: Cleanup

    /// Only items a rule calls safe or worth reviewing can be picked.
    /// Keep, macOS and unlabelled items never can.
    static func canSelect(_ node: FileNode) -> Bool {
        let verdict = rules.assess(node.url).verdict
        return verdict == .safeToClear || verdict == .review
    }

    func isSelected(_ node: FileNode) -> Bool {
        selected[ObjectIdentifier(node)] != nil
    }

    /// Picking an item drops anything already picked inside it or around
    /// it, so nothing is moved twice.
    func setSelected(_ node: FileNode, _ on: Bool) {
        guard on else {
            selected[ObjectIdentifier(node)] = nil
            return
        }
        let path = node.url.path + "/"
        selected = selected.filter { _, other in
            !other.url.path.hasPrefix(path) && !path.hasPrefix(other.url.path + "/")
        }
        selected[ObjectIdentifier(node)] = node
    }

    func clearSelection() {
        selected = [:]
    }

    var selectedSize: Int64 {
        selected.values.reduce(0) { $0 + $1.size }
    }

    /// Runs `body` with the scanned folder opened through its security
    /// scope, which the sandbox needs before Bytewise can check or move
    /// anything inside it.
    private func withFolderAccess<T>(_ body: () -> T) -> T {
        let accessing = folder?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { folder?.stopAccessingSecurityScopedResource() } }
        return body()
    }

    func makePlan() -> [PlannedMove] {
        let apps = RunningApp.current()
        let candidates = selected.values.sorted { $0.size > $1.size }.map { node in
            CleanupCandidate(url: node.url, size: node.size,
                             assessment: Self.rules.assess(node.url),
                             usedBy: AppUsage.app(using: Self.nameChains(for: node), among: apps))
        }
        return withFolderAccess { Self.holdingArea.plan(candidates) }
    }

    /// Folder names to compare with open apps: the item's path, plus its
    /// children and grandchildren, since a "Google" cache folder holds
    /// "Chrome".
    private static func nameChains(for node: FileNode) -> [[String]] {
        var chains = [node.url.pathComponents]
        for child in node.children.prefix(50) {
            chains.append([node.name, child.name])
            for grandchild in child.children.prefix(20) {
                chains.append([child.name, grandchild.name])
            }
        }
        return chains
    }

    func performMove(_ confirmed: [PlannedMove]) {
        // Check everything again now, not just when the preview was made:
        // the rules, open apps and whether each item still exists. Moving
        // then also checks each item is the one the preview showed.
        let fresh = Dictionary(makePlan().map { ($0.candidate.url.path, $0) }, uniquingKeysWith: { first, _ in first })
        var plan: [PlannedMove] = []
        var skipped: [MoveFailure] = []
        for entry in confirmed where entry.willMove {
            let url = entry.candidate.url
            if let now = fresh[url.path], now.willMove {
                plan.append(entry)
            } else {
                skipped.append(MoveFailure(url: url, message: fresh[url.path]?.skipReason ?? "It is no longer picked."))
            }
        }
        var result = withFolderAccess { Self.holdingArea.move(plan, scopeBookmark: scopeBookmark) }
        result.failures = skipped + result.failures
        let nodes = Dictionary(selected.values.map { ($0.url.path, $0) }, uniquingKeysWith: { first, _ in first })

        var moved: [(held: HeldItem, node: FileNode, parent: FileNode)] = []
        for held in result.moved {
            if let node = nodes[held.originalPath], let parent = node.parent {
                node.detach()
                moved.append((held, node, parent))
            }
        }
        if let current, !isInTree(current) { self.current = root }

        lastMoved = moved
        aiModels = root.map { AIModelFinder.find(in: $0) } ?? []
        selected = [:]
        treeVersion += 1
        refreshHeldItems()
        let size = result.moved.reduce(0) { $0 + $1.size }
        statusMessage = "Moved \(result.moved.count) \(result.moved.count == 1 ? "item" : "items") (\(Format.bytes(size))) to the holding area."
        errorMessage = result.failures.isEmpty ? nil
            : "Could not move " + result.failures.map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: " ")
    }

    func undoLastMove() {
        var restored: [(item: HeldItem, url: URL)] = []
        var failures: [String] = []
        withFolderAccess {
            for entry in lastMoved {
                do {
                    restored.append((entry.held, try Self.holdingArea.restore(entry.held)))
                } catch {
                    failures.append("\(entry.held.name): \(FriendlyError.message(for: error))")
                }
            }
        }
        putBack(restored)
        statusMessage = "Restored \(restored.count) \(restored.count == 1 ? "item" : "items")."
        errorMessage = failures.isEmpty ? nil : "Could not restore " + failures.joined(separator: "; ")
    }

    /// Puts restored items back on the map when they came from the last move
    /// and went back to their original place.
    func putBack(_ restored: [(item: HeldItem, url: URL)]) {
        for (item, url) in restored {
            guard let index = lastMoved.firstIndex(where: { $0.held.id == item.id }) else { continue }
            let entry = lastMoved.remove(at: index)
            if url.path == item.originalPath && isInTree(entry.parent) {
                entry.node.attach(to: entry.parent)
            }
        }
        aiModels = root.map { AIModelFinder.find(in: $0) } ?? []
        treeVersion += 1
        refreshHeldItems()
    }

    func refreshHeldItems() {
        heldItems = Self.holdingArea.items()
    }

    private func isInTree(_ node: FileNode) -> Bool {
        var top = node
        while let parent = top.parent { top = parent }
        return top === root
    }
}

/// Items worth cleaning up below a folder.
nonisolated enum CleanupFinder {
    /// The smallest item worth listing.
    static let minimumSize: Int64 = 1_000_000
    /// Files are only checked against rules when they are at least this big,
    /// so the walk stays quick on folders with millions of files.
    private static let minimumFileSize: Int64 = 50_000_000

    /// Items a rule marks safe to clear or worth reviewing, largest first.
    /// When a labelled folder holds items with their own label, such as
    /// Caches holding each app's cache, the inner items are listed instead.
    static func candidates(in root: FileNode, rules: RulesEngine, limit: Int = 300) -> [FileNode] {
        var found: [FileNode] = []
        _ = visit(root, parent: rules.assess(root.url), rules: rules, into: &found)
        return Array(found.sorted { $0.size > $1.size }.prefix(limit))
    }

    /// Returns whether anything at or below `node` was listed.
    private static func visit(_ node: FileNode, parent: Assessment, rules: RulesEngine,
                              into found: inout [FileNode]) -> Bool {
        var listedInside = false
        for child in node.children where child.size >= minimumSize {
            if !child.isDirectory && child.size < minimumFileSize { continue }
            let assessment = rules.assess(child.url)
            switch assessment.verdict {
            case .keep, .managedByMacOS:
                continue
            case .safeToClear where assessment != parent:
                found.append(child)
                listedInside = true
            case .review where assessment != parent:
                // A review folder that only holds other labelled items is a
                // container, so list what is inside instead.
                if child.isDirectory && visit(child, parent: assessment, rules: rules, into: &found) {
                    listedInside = true
                } else {
                    found.append(child)
                    listedInside = true
                }
            default:
                if child.isDirectory && visit(child, parent: assessment, rules: rules, into: &found) {
                    listedInside = true
                }
            }
        }
        return listedInside
    }
}

/// The largest files below a folder.
nonisolated enum BiggestFiles {
    static func find(in root: FileNode, limit: Int = 200) -> [FileNode] {
        var top: [FileNode] = []
        var smallest: Int64 = 0
        func visit(_ node: FileNode) {
            for child in node.children {
                // Children are sorted largest first, so stop once they get too small.
                if top.count >= limit && child.size <= smallest { break }
                if child.isDirectory {
                    visit(child)
                } else {
                    top.append(child)
                    if top.count > limit * 2 {
                        top.sort { $0.size > $1.size }
                        top.removeLast(top.count - limit)
                        smallest = top.last?.size ?? 0
                    }
                }
            }
        }
        visit(root)
        return Array(top.sorted { $0.size > $1.size }.prefix(limit))
    }
}
