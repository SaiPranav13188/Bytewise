//
//  FileListViews.swift
//  Bytewise
//

import SwiftUI

/// A list worked out in the background from the scanned tree, such as the
/// biggest files or search results, shown in one card.
struct ComputedFileList: View {
    @Bindable var model: ScanModel
    let title: String
    let caption: String
    let emptyText: String
    /// Changes when the list needs working out again.
    let key: String
    var showsCheckbox = false
    let compute: @Sendable () -> [FileNode]

    @State private var items: [FileNode]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.semibold))
                if let items {
                    Text("\(items.count.formatted()) \(items.count == 1 ? "item" : "items") · \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let items {
                if items.isEmpty {
                    Spacer()
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    let largest = max(items.first?.size ?? 1, 1)
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(items) { item in
                                FileRow(model: model, node: item, subtitle: subtitle(for: item),
                                        fraction: Double(item.size) / Double(largest),
                                        showsCheckbox: showsCheckbox) {
                                    if item.isDirectory { model.open(item) }
                                }
                            }
                        }
                    }
                }
            } else {
                Spacer()
                ProgressView().frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 18)
        .task(id: "\(key)#\(model.treeVersion)") {
            items = nil
            let work = compute
            items = await Task.detached(priority: .userInitiated) { work() }.value
        }
    }

    /// Where the item is, relative to the scanned folder, and when it was used.
    private func subtitle(for node: FileNode) -> String {
        let base = (model.root?.url.path ?? "") + "/"
        let parent = node.url.deletingLastPathComponent().path
        let place = parent.hasPrefix(base) ? String(parent.dropFirst(base.count)) : parent + "/"
        let location = place.isEmpty || place == base ? "Top level" : place
        return "\(location) · \(node.isDirectory ? Format.files(node.fileCount) : Format.lastUsed(node.lastUsed))"
    }
}

/// The largest files anywhere inside the open folder.
struct BiggestFilesView: View {
    @Bindable var model: ScanModel
    let folder: FileNode

    var body: some View {
        ComputedFileList(model: model,
                         title: "Biggest files in \(folder.name)",
                         caption: "The 200 largest files at any depth. Big files are often old downloads, videos and disk images.",
                         emptyText: "No files here.",
                         key: folder.url.path,
                         showsCheckbox: true) {
            BiggestFiles.find(in: folder)
        }
    }
}

/// Everything a rule says can be cleared or is worth a look.
struct CleanupListView: View {
    @Bindable var model: ScanModel
    let root: FileNode

    var body: some View {
        ComputedFileList(model: model,
                         title: "Clean up",
                         caption: "Caches, build files, installers and downloaded models that rules recognise. Tick items, then review them. Nothing moves until you confirm, and everything can be restored.",
                         emptyText: "Nothing to clean up in this scan. Try scanning your Home or Library folder.",
                         key: root.url.path,
                         showsCheckbox: true) {
            CleanupFinder.candidates(in: root, rules: ScanModel.rules)
        }
    }
}

/// Items matching the search field.
struct SearchResultsView: View {
    @Bindable var model: ScanModel
    let folder: FileNode
    let text: String

    var body: some View {
        let query = SearchQuery(text)
        ComputedFileList(model: model,
                         title: "Results in \(folder.name)",
                         caption: "Search by name, or use filters: ext:dmg  kind:video  size:>500mb  age:>90d",
                         emptyText: "Nothing matches “\(text)”.",
                         key: folder.url.path + "?" + text,
                         showsCheckbox: true) {
            query.results(in: folder)
        }
    }
}
