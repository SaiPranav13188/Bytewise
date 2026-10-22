//
//  TreemapView.swift
//  Bytewise
//

import SwiftUI

/// The size map for one folder. Hovering shows what is under the pointer;
/// clicking a tile opens it.
struct TreemapView: View {
    let folder: FileNode
    /// Bump to redraw after the tree changes, e.g. when items are moved away.
    let version: Int
    let onOpen: (FileNode) -> Void

    @State private var layout: TreemapLayout?
    @State private var hoveredTop: TreemapTile?
    @State private var hoveredDeep: TreemapTile?

    private struct LayoutKey: Equatable {
        let folder: ObjectIdentifier
        let version: Int
        let size: CGSize
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let layout {
                    TreemapCanvas(layout: layout).equatable()
                }
                if let layout {
                    TreemapLabels(layout: layout).equatable()
                        .allowsHitTesting(false)
                }
                // Only the tile a click would open is highlighted, so the
                // highlight moves once per tile, not with every small item.
                if let hoveredTop {
                    RoundedRectangle(cornerRadius: TreemapLayout.cornerRadius, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                        .frame(width: hoveredTop.rect.width, height: hoveredTop.rect.height)
                        .offset(x: hoveredTop.rect.minX, y: hoveredTop.rect.minY)
                        .allowsHitTesting(false)
                        .animation(.easeOut(duration: 0.12), value: hoveredTop.rect)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let deep = layout?.tile(at: point)
                    if deep?.node !== hoveredDeep?.node {
                        hoveredDeep = deep
                        hoveredTop = layout?.topTile(at: point)
                    }
                case .ended:
                    hoveredDeep = nil
                    hoveredTop = nil
                }
            }
            .onTapGesture { point in
                // Open the item directly in this folder, the one with the
                // label, so a click goes one level down.
                guard let node = layout?.topTile(at: point)?.node, node.isDirectory else { return }
                onOpen(node)
            }
            .overlay(alignment: .bottomLeading) {
                if let hoveredTop {
                    HoverCard(top: hoveredTop.node, deep: hoveredDeep?.node, folder: folder)
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: LayoutKey(folder: ObjectIdentifier(folder), version: version, size: geometry.size),
                      initial: true) {
                layout = TreemapLayout(folder: folder, size: geometry.size)
                hoveredTop = nil
                hoveredDeep = nil
            }
        }
    }
}

/// Details for the tile under the pointer.
private struct HoverCard: View {
    let top: FileNode
    let deep: FileNode?
    let folder: FileNode

    var body: some View {
        let share = folder.size > 0 ? Double(top.size) / Double(folder.size) : 0
        let assessment = ScanModel.rules.assess(top.url)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(top.name).font(.headline).lineLimit(1)
                VerdictChip(verdict: assessment.verdict)
            }
            Text("\(Format.bytes(top.size)) · \(share.formatted(.percent.precision(.fractionLength(1)))) of \(folder.name)\(top.isDirectory ? " · " + Format.files(top.fileCount) : "")")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let reason = assessment.reason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let deep, deep !== top {
                Label {
                    Text(deep.url.path.replacingOccurrences(of: top.url.path + "/", with: "") + " · " + Format.bytes(deep.size))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "arrow.turn.down.right")
                }
                .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

/// Draws the tiles and outlines. It only redraws when the layout changes, not on
/// every hover.
private struct TreemapCanvas: View, Equatable {
    let layout: TreemapLayout

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.layout === rhs.layout }

    var body: some View {
        Canvas { context, _ in
            for tile in layout.topTiles {
                let shape = Path(roundedRect: tile.rect, cornerRadius: TreemapLayout.cornerRadius, style: .continuous)
                let color = tile.node.kindSizes.dominant.color
                context.fill(shape, with: .linearGradient(
                    Gradient(colors: [color, color.mix(with: .black, by: 0.12)]),
                    startPoint: CGPoint(x: tile.rect.midX, y: tile.rect.minY),
                    endPoint: CGPoint(x: tile.rect.midX, y: tile.rect.maxY)))
            }
            for (index, path) in layout.innerPaths.enumerated() {
                context.stroke(path, with: .color(.black.opacity(index == 0 ? 0.16 : 0.08)), lineWidth: 1)
            }
        }
    }
}

/// Names and sizes, drawn above the hover tint so they stay readable.
private struct TreemapLabels: View, Equatable {
    let layout: TreemapLayout

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.layout === rhs.layout }

    var body: some View {
        Canvas { context, _ in
            for label in layout.labels {
                var labelContext = context
                labelContext.clip(to: Path(label.rect.insetBy(dx: 4, dy: 2)))
                let ink = Color.black.opacity(label.depth == 1 ? 0.82 : 0.6)
                if label.depth == 1 {
                    labelContext.draw(Text(label.node.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink),
                                      at: CGPoint(x: label.rect.minX + 10, y: label.rect.minY + 8), anchor: .topLeading)
                    labelContext.draw(Text(Format.bytes(label.node.size)).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(ink.opacity(0.7)),
                                      at: CGPoint(x: label.rect.minX + 10, y: label.rect.minY + 24), anchor: .topLeading)
                } else {
                    labelContext.draw(Text("\(label.node.name)  \(Format.bytes(label.node.size))").font(.system(size: 10, weight: .medium)).foregroundStyle(ink),
                                      at: CGPoint(x: label.rect.minX + 6, y: label.rect.minY + 3), anchor: .topLeading)
                }
            }
        }
    }
}
