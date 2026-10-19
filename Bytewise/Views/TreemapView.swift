//
//  TreemapView.swift
//  Bytewise
//

import SwiftUI

extension FileKind {
    var color: Color {
        switch self {
        case .folder: .gray.opacity(0.3)
        case .video: .purple.opacity(0.8)
        case .audio: .pink.opacity(0.8)
        case .image: .green.opacity(0.8)
        case .archive: .orange.opacity(0.8)
        case .code: .blue.opacity(0.8)
        case .document: .yellow.opacity(0.8)
        // Distinct from the grey folders, so files stand out from the boxes they sit in.
        case .other: .teal.opacity(0.8)
        }
    }
}

/// The size map for one folder. Hover shows an item's details and clicking
/// opens the folder under the pointer.
struct TreemapView: View {
    let folder: FileNode
    @Binding var hovered: FileNode?
    let onOpen: (FileNode) -> Void

    @State private var layout: TreemapLayout?
    @State private var hoverRect: CGRect?

    private struct LayoutKey: Equatable {
        let folder: ObjectIdentifier
        let size: CGSize
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let layout {
                    TreemapCanvas(layout: layout).equatable()
                }
                if let hoverRect {
                    Rectangle()
                        .strokeBorder(.primary, lineWidth: 2)
                        .frame(width: hoverRect.width, height: hoverRect.height)
                        .offset(x: hoverRect.minX, y: hoverRect.minY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let tile = layout?.tile(at: point)
                    if tile?.node !== hovered {
                        hovered = tile?.node
                        hoverRect = tile?.rect
                    }
                case .ended:
                    hovered = nil
                    hoverRect = nil
                }
            }
            .onTapGesture { point in
                guard let node = layout?.tile(at: point)?.node else { return }
                // Clicking a file opens the folder it is in.
                if let target = node.isDirectory ? node : node.parent, target !== folder {
                    onOpen(target)
                }
            }
            .onChange(of: LayoutKey(folder: ObjectIdentifier(folder), size: geometry.size),
                      initial: true) {
                layout = TreemapLayout(folder: folder, size: geometry.size)
                hovered = nil
                hoverRect = nil
            }
        }
    }
}

/// Draws a layout. It only redraws when the layout itself changes, not on
/// every hover.
private struct TreemapCanvas: View, Equatable {
    let layout: TreemapLayout

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.layout === rhs.layout }

    var body: some View {
        Canvas { context, _ in
            for path in layout.folderPaths {
                context.fill(path, with: .color(FileKind.folder.color))
            }
            for (kind, path) in layout.filePaths {
                context.fill(path, with: .color(kind.color))
            }
            for label in layout.labels {
                var labelContext = context
                labelContext.clip(to: Path(label.rect))
                labelContext.draw(Text(label.name).font(.caption),
                                  at: CGPoint(x: label.rect.minX + 3, y: label.rect.midY),
                                  anchor: .leading)
            }
        }
    }
}

/// Colour key for the map.
struct TreemapLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(FileKind.allCases, id: \.self) { kind in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(kind.color)
                        .frame(width: 10, height: 10)
                    Text(kind.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
