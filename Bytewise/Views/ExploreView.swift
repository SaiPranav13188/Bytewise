//
//  ExploreView.swift
//  Bytewise
//

import AppKit
import SwiftUI

/// The main tab: a summary of the open folder, its contents largest first,
/// and the size map.
struct ExploreView: View {
    @Bindable var model: ScanModel
    let folder: FileNode

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                SummaryCard(folder: folder, seconds: folder === model.root ? model.scanSeconds : nil)
                ItemList(model: model, folder: folder)
            }
            .frame(minWidth: 340, idealWidth: 400, maxWidth: 440)

            TreemapView(folder: folder, version: model.treeVersion, onOpen: model.open)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }
}

/// The open folder's total, file count, and how its space splits by kind.
struct SummaryCard: View {
    let folder: FileNode
    let seconds: Double?

    var body: some View {
        let kinds = folder.kindSizes.sorted.filter { $0.kind != .folder }
        let total = max(folder.size, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                SizeText(bytes: folder.size, size: 40)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.files(folder.fileCount))
                        .font(.callout.weight(.medium))
                    if let seconds {
                        Text("scanned in \(seconds.formatted(.number.precision(.fractionLength(1)))) s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(Format.lastUsed(folder.lastUsed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(kinds, id: \.kind) { entry in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.kind.color)
                            .frame(width: max(2, (geometry.size.width - CGFloat(kinds.count) * 2) * CGFloat(entry.size) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                ForEach(kinds.prefix(8), id: \.kind) { entry in
                    HStack(spacing: 6) {
                        Circle().fill(entry.kind.color).frame(width: 7, height: 7)
                        Text(entry.kind.label)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(Format.bytes(entry.size))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    .font(.callout)
                }
            }
        }
        .card(padding: 18)
    }
}

/// The open folder's items, largest first. Click a folder to open it.
private struct ItemList: View {
    @Bindable var model: ScanModel
    let folder: FileNode

    /// Very large folders show their biggest items first, then more on request.
    @State private var limit = 200

    var body: some View {
        let items = Array(folder.children.prefix(limit))
        let largest = max(folder.children.first?.size ?? 1, 1)
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    FileRow(model: model, node: item, subtitle: item.isDirectory ? Format.files(item.fileCount) : Format.lastUsed(item.lastUsed),
                            fraction: Double(item.size) / Double(largest)) {
                        if item.isDirectory { model.open(item) }
                    }
                }
                if folder.children.count > limit {
                    Button("Show \(min(200, folder.children.count - limit)) more of \(folder.children.count.formatted())") {
                        limit += 200
                    }
                    .buttonStyle(.link)
                    .padding(8)
                }
                if folder.children.isEmpty {
                    Text("This folder is empty.")
                        .foregroundStyle(.secondary)
                        .padding(24)
                }
            }
            .padding(6)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        .onChange(of: ObjectIdentifier(folder)) { limit = 200 }
    }
}

/// One item: icon, name, a detail line, verdict, share bar and size.
/// Right-click for Finder and cleanup actions.
struct FileRow: View {
    @Bindable var model: ScanModel
    let node: FileNode
    let subtitle: String
    var fraction: Double?
    var showsCheckbox = false
    var onOpen: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        let assessment = ScanModel.rules.assess(node.url)
        let selectable = ScanModel.canSelect(node)
        HStack(spacing: 10) {
            if showsCheckbox {
                Toggle("", isOn: Binding(get: { model.isSelected(node) },
                                         set: { model.setSelected(node, $0) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(!selectable)
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    VerdictChip(verdict: assessment.verdict)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let fraction {
                ShareBar(fraction: fraction, tint: node.kindSizes.dominant.color)
                    .frame(width: 60)
            }
            SizeText(bytes: node.size)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isHovered ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear)))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
        .help(assessment.reason ?? node.url.path)
        .contextMenu {
            if node.isDirectory {
                Button("Open") { model.open(node) }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            Divider()
            if model.isSelected(node) {
                Button("Remove from Cleanup") { model.setSelected(node, false) }
            } else {
                Button("Add to Cleanup") { model.setSelected(node, true) }
                    .disabled(!selectable)
            }
        }
    }
}
