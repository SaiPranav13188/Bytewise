//
//  TreemapLayout.swift
//  Bytewise
//

import SwiftUI

/// One rectangle on the map.
struct TreemapTile {
    let node: FileNode
    let rect: CGRect
}

/// Lays out a folder as a nested, squarified treemap and prepares it for
/// drawing. Rectangles of the same colour are merged into one path, so the
/// map draws in a handful of fills however many items it shows.
final class TreemapLayout {
    /// Tiles in drawing order: every folder comes before its contents.
    private(set) var tiles: [TreemapTile] = []
    /// Folder backgrounds, one path per nesting depth, shallowest first.
    private(set) var folderPaths: [Path] = []
    private(set) var filePaths: [FileKind: Path] = [:]
    private(set) var labels: [(rect: CGRect, name: String)] = []

    /// Items smaller than this on either side are not drawn.
    private static let minSide: CGFloat = 2
    private static let maxDepth = 8
    /// Only the outer levels get names, to keep the map readable.
    private static let labelDepth = 2
    private static let headerHeight: CGFloat = 14

    init(folder: FileNode, size: CGSize) {
        layOut(folder.children, in: CGRect(origin: .zero, size: size), depth: 1)
    }

    /// The deepest tile under `point`.
    func tile(at point: CGPoint) -> TreemapTile? {
        tiles.last { $0.rect.contains(point) }
    }

    private func layOut(_ nodes: [FileNode], in rect: CGRect, depth: Int) {
        // Children are sorted largest first, so empty items are at the end.
        let visible = nodes.prefix { $0.size > 0 }
        let rects = Self.squarify(visible.map { Double($0.size) }, in: rect)

        for (node, r) in zip(visible, rects) {
            guard r.width >= Self.minSide, r.height >= Self.minSide else { continue }
            tiles.append(TreemapTile(node: node, rect: r))
            let canLabel = depth <= Self.labelDepth && r.width >= 60

            if node.isDirectory {
                if folderPaths.count < depth { folderPaths.append(Path()) }
                folderPaths[depth - 1].addRect(r.insetBy(dx: 0.5, dy: 0.5))

                var inner = r.insetBy(dx: 2, dy: 2)
                if canLabel && r.height >= 40 {
                    labels.append((CGRect(x: inner.minX, y: inner.minY,
                                          width: inner.width, height: Self.headerHeight), node.name))
                    inner.origin.y += Self.headerHeight
                    inner.size.height -= Self.headerHeight
                }
                if depth < Self.maxDepth, inner.width >= 4, inner.height >= 4 {
                    layOut(node.children, in: inner, depth: depth + 1)
                }
            } else {
                filePaths[node.kind, default: Path()].addRect(r.insetBy(dx: 0.5, dy: 0.5))
                if canLabel && r.height >= 18 {
                    labels.append((CGRect(x: r.minX, y: r.minY + 1,
                                          width: r.width, height: Self.headerHeight), node.name))
                }
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
