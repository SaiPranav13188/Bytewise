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
                Text(statusMessage).foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            if let current {
                breadcrumb(for: current)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        TreemapView(folder: current, hovered: $hovered) { self.current = $0 }
                        TreemapLegend()
                        Text(details(hovered: hovered, in: current))
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    List(Array(current.children.prefix(20))) { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text(Self.format(item.size))
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 300)
                }
            } else {
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 900, minHeight: 550)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): startScan(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
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

    private func details(hovered: FileNode?, in folder: FileNode) -> String {
        guard let hovered else {
            return "\(folder.name) · \(Self.format(folder.size)) · \(folder.children.count.formatted()) items"
        }
        let relativePath = hovered.url.path.replacingOccurrences(of: folder.url.path + "/", with: "")
        let share = folder.size > 0 ? Double(hovered.size) / Double(folder.size) : 0
        return "\(relativePath) · \(Self.format(hovered.size)) · \(share.formatted(.percent.precision(.fractionLength(1)))) of \(folder.name)"
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
        progress = ScanProgress()
        statusMessage = nil
        errorMessage = nil
        isScanning = true

        scanTask = Task {
            // The app is sandboxed, so the picked folder must be opened
            // through its security scope before reading it.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

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
                let tree = try await FolderScanner.scan(url) { continuation.yield($0) }
                continuation.finish()
                await progressTask.value
                root = tree
                current = tree
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
