//
//  ContentView.swift
//  Bytewise
//
//  Created by Sai Pranav on 19/10/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var folder: URL?
    @State private var root: FileNode?
    @State private var current: FileNode?
    @State private var hovered: FileNode?
    @State private var isScanning = false
    @State private var progress = ScanProgress()
    @State private var showImporter = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var scanTask: Task<Void, Never>?
    @State private var unreadable: [URL] = []
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var scopeBookmark: Data?
    @State private var selected: [ObjectIdentifier: FileNode] = [:]
    @State private var cleanupPlan: [PlannedMove]?
    @State private var showHoldingArea = false
    /// The last move, kept so it can be undone and put back on the map.
    @State private var lastMoved: [(held: HeldItem, node: FileNode, parent: FileNode)] = []
    @State private var treeVersion = 0

    private static let rules = RulesEngine()
    private static let holdingArea = HoldingArea.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose Folder") { showImporter = true }
                    .disabled(isScanning)
                if isScanning {
                    Button("Cancel") { scanTask?.cancel() }
                }
                if let folder {
                    Text(folder.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Holding Area…") { showHoldingArea = true }
            }

            if isScanning {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(progress.itemsDone),
                                 total: Double(max(progress.itemsTotal, 1)))
                    Text("Scanning \(progress.currentItem) (\(min(progress.itemsDone + 1, progress.itemsTotal)) of \(progress.itemsTotal)) · \(progress.filesScanned.formatted()) files")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let statusMessage {
                HStack {
                    Text(statusMessage).foregroundStyle(.secondary)
                    if !lastMoved.isEmpty {
                        Button("Undo", action: undoLastMove)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if !unreadable.isEmpty {
                accessNotice
            }

            if let current {
                breadcrumb(for: current)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        TreemapView(folder: current, version: treeVersion, hovered: $hovered) { self.current = $0 }
                        TreemapLegend()
                        details(hovered: hovered, in: current)
                    }

                    VStack(spacing: 8) {
                        List(Array(current.children.prefix(20))) { item in
                            HStack {
                                Toggle("", isOn: selection(for: item))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .disabled(!Self.canSelect(item))
                                Image(systemName: item.isDirectory ? "folder" : "doc")
                                    .foregroundStyle(.secondary)
                                Text(item.name).lineLimit(1)
                                VerdictChip(verdict: Self.rules.assess(item.url).verdict)
                                Spacer()
                                Text(Self.format(item.size))
                                    .monospacedDigit()
                            }
                            .help(Self.rules.assess(item.url).reason ?? "")
                        }
                        Button("Review \(selected.count) Selected (\(Self.format(selected.values.reduce(0) { $0 + $1.size })))…") {
                            cleanupPlan = makePlan()
                        }
                        .disabled(selected.isEmpty)
                    }
                    .frame(width: 320)
                }
            } else {
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 900, minHeight: 550)
        .sheet(isPresented: Binding(get: { !hasSeenWelcome },
                                    set: { hasSeenWelcome = !$0 })) {
            WelcomeView { hasSeenWelcome = true }
        }
        .sheet(isPresented: Binding(get: { cleanupPlan != nil },
                                    set: { if !$0 { cleanupPlan = nil } })) {
            CleanupSheet(plan: cleanupPlan ?? [],
                         onDryRun: makePlan,
                         onMove: performMove,
                         onCancel: { cleanupPlan = nil })
        }
        .sheet(isPresented: $showHoldingArea) {
            HoldingAreaView(holdingArea: Self.holdingArea,
                            onRestored: putBack,
                            onClose: { showHoldingArea = false })
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): startScan(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Cleanup

    /// Only items a rule calls safe or worth reviewing can be picked.
    /// Keep, macOS and unlabelled items never can.
    private static func canSelect(_ node: FileNode) -> Bool {
        let verdict = rules.assess(node.url).verdict
        return verdict == .safeToClear || verdict == .review
    }

    private func selection(for node: FileNode) -> Binding<Bool> {
        Binding(get: { selected[ObjectIdentifier(node)] != nil },
                set: { selected[ObjectIdentifier(node)] = $0 ? node : nil })
    }

    /// Runs `body` with the scanned folder opened through its security
    /// scope, which the sandbox needs before Bytewise can check or move
    /// anything inside it.
    private func withFolderAccess<T>(_ body: () -> T) -> T {
        let accessing = folder?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { folder?.stopAccessingSecurityScopedResource() } }
        return body()
    }

    private func makePlan() -> [PlannedMove] {
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

    private func performMove(_ plan: [PlannedMove]) {
        let result = withFolderAccess { Self.holdingArea.move(plan, scopeBookmark: scopeBookmark) }
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
        selected = [:]
        cleanupPlan = nil
        hovered = nil
        treeVersion += 1
        let size = result.moved.reduce(0) { $0 + $1.size }
        statusMessage = "Moved \(result.moved.count) \(result.moved.count == 1 ? "item" : "items") (\(Self.format(size))) to the holding area."
        errorMessage = result.failures.isEmpty ? nil
            : "Could not move " + result.failures.map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: "; ")
    }

    private func undoLastMove() {
        var restored: [(item: HeldItem, url: URL)] = []
        var failures: [String] = []
        withFolderAccess {
            for entry in lastMoved {
                do {
                    restored.append((entry.held, try Self.holdingArea.restore(entry.held)))
                } catch {
                    failures.append("\(entry.held.name): \(error.localizedDescription)")
                }
            }
        }
        putBack(restored)
        statusMessage = "Restored \(restored.count) \(restored.count == 1 ? "item" : "items")."
        errorMessage = failures.isEmpty ? nil : "Could not restore " + failures.joined(separator: "; ")
    }

    /// Puts restored items back on the map when they came from the last move
    /// and went back to their original place.
    private func putBack(_ restored: [(item: HeldItem, url: URL)]) {
        for (item, url) in restored {
            guard let index = lastMoved.firstIndex(where: { $0.held.id == item.id }) else { continue }
            let entry = lastMoved.remove(at: index)
            if url.path == item.originalPath && isInTree(entry.parent) {
                entry.node.attach(to: entry.parent)
            }
        }
        treeVersion += 1
    }

    private func isInTree(_ node: FileNode) -> Bool {
        var top = node
        while let parent = top.parent { top = parent }
        return top === root
    }

    /// Shown when macOS blocked some folders, so their sizes are missing.
    private var accessNotice: some View {
        HStack {
            Image(systemName: "lock")
            Text("macOS blocked \(unreadable.count.formatted()) \(unreadable.count == 1 ? "folder" : "folders"), so some sizes may be low. Full Disk Access lets Bytewise include them.")
                .help(unreadable.prefix(10).map(\.path).joined(separator: "\n"))
            Spacer()
            Button("Open Full Disk Access Settings") { FullDiskAccess.openSettings() }
        }
        .font(.callout)
        .padding(8)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    /// The path from the scanned folder down to the open one. Click a part to
    /// go back up to it.
    private func breadcrumb(for node: FileNode) -> some View {
        var chain: [FileNode] = []
        var next: FileNode? = node
        while let step = next {
            chain.insert(step, at: 0)
            next = step.parent
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(chain) { step in
                    if step !== chain.first {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(step.name) { current = step }
                        .buttonStyle(.link)
                        .disabled(step === node)
                }
            }
        }
    }

    /// Two lines under the map: what the item is and how big, then its
    /// verdict and reason. Only the path is shortened when space runs out.
    private func details(hovered: FileNode?, in folder: FileNode) -> some View {
        let item = hovered ?? folder
        let name: String
        let numbers: String
        if let hovered {
            name = hovered.url.path.replacingOccurrences(of: folder.url.path + "/", with: "")
            let share = folder.size > 0 ? Double(hovered.size) / Double(folder.size) : 0
            numbers = "· \(Self.format(hovered.size)) · \(share.formatted(.percent.precision(.fractionLength(1)))) of \(folder.name)"
        } else {
            name = folder.name
            numbers = "· \(Self.format(folder.size)) · \(folder.children.count.formatted()) items"
        }
        let assessment = Self.rules.assess(item.url)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(numbers)
                    .fixedSize()
            }
            HStack(spacing: 6) {
                VerdictChip(verdict: assessment.verdict)
                // A blank line when there is no reason, so the map does not jump.
                Text(assessment.reason ?? " ")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.callout)
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func startScan(_ url: URL) {
        scanTask?.cancel()
        folder = url
        root = nil
        current = nil
        hovered = nil
        unreadable = []
        selected = [:]
        lastMoved = []
        scopeBookmark = nil
        progress = ScanProgress()
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
                let result = try await FolderScanner.scan(url) { continuation.yield($0) }
                continuation.finish()
                await progressTask.value
                root = result.root
                current = result.root
                unreadable = result.unreadable
                let seconds = Date().timeIntervalSince(start)
                statusMessage = "Scanned \(progress.filesScanned.formatted()) files in \(seconds.formatted(.number.precision(.fractionLength(1)))) s"
            } catch is CancellationError {
                statusMessage = "Scan cancelled."
            } catch {
                errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }
}

#Preview {
    ContentView()
}
