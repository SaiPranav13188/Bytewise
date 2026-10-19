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
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose Folder") { showImporter = true }
                    .disabled(isScanning)
                if let folder {
                    Text(folder.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").foregroundStyle(.secondary)
                }
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
        errorMessage = nil
        isScanning = true

        scanTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                // The app is sandboxed, so the picked folder must be opened
                // through its security scope before reading it.
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return Result { try FolderScanner.largestItems(in: url) }
            }.value

            guard !Task.isCancelled else { return }
            switch result {
            case .success(let found): items = found
            case .failure(let error): errorMessage = error.localizedDescription
            }
            isScanning = false
        }
    }
}

#Preview {
    ContentView()
}
