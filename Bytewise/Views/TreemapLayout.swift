//
//  TreemapLayout.swift
//  Bytewise
//

import SwiftUI

/// One rectangle on the map.
struct TreemapTile {
    let node: FileNode
    let rect: CGRect
    /// 1 for items directly in the open folder.
    let depth: Int
}

/// Lays out a folder as a squarified treemap. Items directly in the folder
/// become rounded, coloured tiles with their name and size; what is inside
/// them is outlined faintly, so big folders show their shape.
final class TreemapLayout {
    /// Tiles in drawing order: every folder comes before its contents.
    private(set) var tiles: [TreemapTile] = []
    private(set) var topTiles: [TreemapTile] = []
    /// Outlines of items inside the top tiles, one path per nesting depth.
    private(set) var innerPaths: [Path] = []
    private(set) var labels: [(rect: CGRect, node: FileNode, depth: Int)] = []

    static let cornerRadius: CGFloat = 8
    private static let gap: CGFloat = 3
    /// Items smaller than this on either side are not drawn.
    private static let minSide: CGFloat = 2
    private static let maxDepth = 6
    private static let outlineDepth = 2
    private static let headerHeight: CGFloat = 38
    private static let subHeaderHeight: CGFloat = 16

    init(folder: FileNode, size: CGSize) {
        let box = CGRect(origin: .zero, size: size)
        let visible = Array(folder.children.prefix { $0.size > 0 })
        let rects = Self.squarify(visible.map { Double($0.size) }, in: box)
        for (node, r) in zip(visible, rects) {
            let r = r.insetBy(dx: Self.gap / 2, dy: Self.gap / 2)
            guard r.width >= Self.minSide, r.height >= Self.minSide else { continue }
            let tile = TreemapTile(node: node, rect: r, depth: 1)
            tiles.append(tile)
            topTiles.append(tile)

            var inner = r.insetBy(dx: 5, dy: 5)
            if r.width >= 56 && r.height >= 34 {
                labels.append((r, node, 1))
                if r.height >= Self.headerHeight + 30 {
                    inner.origin.y += Self.headerHeight - 4
                    inner.size.height -= Self.headerHeight - 4
                } else {
                    continue
                }
            }
            if node.isDirectory, inner.width >= 8, inner.height >= 8 {
                layOut(node.children, in: inner, depth: 2)
            }
        }
    }

    /// The deepest tile under `point`.
    func tile(at point: CGPoint) -> TreemapTile? {
        tiles.last { $0.rect.contains(point) }
    }

    /// The tile directly in the open folder under `point`.
    func topTile(at point: CGPoint) -> TreemapTile? {
        topTiles.first { $0.rect.contains(point) }
    }

    private func layOut(_ nodes: [FileNode], in rect: CGRect, depth: Int) {
        // Children are sorted largest first, so empty items are at the end.
        let visible = nodes.prefix { $0.size > 0 }
        let rects = Self.squarify(visible.map { Double($0.size) }, in: rect)

        for (node, r) in zip(visible, rects) {
            guard r.width >= Self.minSide, r.height >= Self.minSide else { continue }
            tiles.append(TreemapTile(node: node, rect: r, depth: depth))
            if depth <= Self.outlineDepth {
                while innerPaths.count < depth - 1 { innerPaths.append(Path()) }
                innerPaths[depth - 2].addRoundedRect(in: r.insetBy(dx: 1, dy: 1),
                                                     cornerSize: CGSize(width: 3, height: 3))
            }
            var inner = r.insetBy(dx: 2, dy: 2)
            if depth == 2 && r.width >= 90 && r.height >= 36 {
                labels.append((r, node, depth))
                // Keep the label's strip clear, so nothing inside covers it.
                inner.origin.y += Self.subHeaderHeight
                inner.size.height -= Self.subHeaderHeight
            }
            if node.isDirectory, depth < Self.maxDepth, inner.width >= 6, inner.height >= 6 {
                layOut(node.children, in: inner, depth: depth + 1)
            }
        }
    }

    /// Squarified treemap (Bruls, Huizing and van Wijk): splits `rect` into
    /// one rectangle per value, in the same order, with areas proportional to
    /// the values and shapes kept close to square. Values must be sorted
    /// largest first and be positive.
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else {
            return Array(repeating: .zero, count: values.count)
        }
        let scale = Double(rect.width * rect.height) / total
        var result: [CGRect] = []
        result.reserveCapacity(values.count)
        var remaining = rect
        var start = 0

        while start < values.count {
            guard remaining.width > 0, remaining.height > 0 else {
                result.append(contentsOf: repeatElement(.zero, count: values.count - start))
                break
            }
            // Grow the row while it makes the worst aspect ratio better.
            let side = Double(min(remaining.width, remaining.height))
            let largest = values[start] * scale
            var end = start
            var rowSum = 0.0
            var bestWorst = Double.infinity
            while end < values.count {
                let value = values[end] * scale
                let sum = rowSum + value
                let worst = max(side * side * largest / (sum * sum),
                                (sum * sum) / (side * side * value))
                if worst > bestWorst { break }
                bestWorst = worst
                rowSum = sum
                end += 1
            }

            // Place the row along the shorter side of what is left.
            if remaining.width >= remaining.height {
                let width = rowSum / Double(remaining.height)
                var y = remaining.minY
                for i in start..<end {
                    let height = values[i] * scale / width
                    result.append(CGRect(x: remaining.minX, y: y, width: width, height: height))
                    y += height
                }
                remaining.origin.x += width
                remaining.size.width = max(0, remaining.width - width)
            } else {
                let height = rowSum / Double(remaining.width)
                var x = remaining.minX
                for i in start..<end {
                    let width = values[i] * scale / height
                    result.append(CGRect(x: x, y: remaining.minY, width: width, height: height))
                    x += width
                }
                remaining.origin.y += height
                remaining.size.height = max(0, remaining.height - height)
            }
            start = end
        }
        return result
    }
}
