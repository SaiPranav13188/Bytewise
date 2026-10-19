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
    @State private var items: [ScanItem] = []
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

            List(items) { item in
                HStack {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .foregroundStyle(.secondary)
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): startScan(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func startScan(_ url: URL) {
        scanTask?.cancel()
        folder = url
        items = []
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
                items = try await FolderScanner.largestItems(in: url) { continuation.yield($0) }
                continuation.finish()
                await progressTask.value
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
