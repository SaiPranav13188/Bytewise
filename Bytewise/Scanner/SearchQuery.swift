//
//  SearchQuery.swift
//  Bytewise
//

import Foundation

/// A search typed into the search field, such as `ext:dmg size:>300mb`.
/// Plain words match names. Every part must match.
///
/// - `ext:dmg` or `ext:dmg,pkg`: file extension
/// - `kind:video`: one of video, audio, image, archive, code, document, other, folder
/// - `size:>300mb`, `size:<1gb`: size, in b, kb, mb, gb or tb
/// - `age:>90d`, `age:<2w`: time since last use, in d, w, m (months) or y
nonisolated struct SearchQuery: Sendable, Equatable {
    var words: [String] = []
    var extensions: Set<String> = []
    var kinds: Set<FileKind> = []
    var minSize: Int64?
    var maxSize: Int64?
    var minAge: TimeInterval?
    var maxAge: TimeInterval?

    init(_ text: String) {
        for token in text.lowercased().split(separator: " ") {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[1].isEmpty else {
                words.append(String(token))
                continue
            }
            let value = parts[1]
            switch parts[0] {
            case "ext":
                extensions.formUnion(value.split(separator: ",").map { $0.hasPrefix(".") ? String($0.dropFirst()) : String($0) })
            case "kind":
                if let kind = Self.kind(named: value) { kinds.insert(kind) }
            case "size":
                if let (less, amount) = Self.comparison(value), let bytes = Self.bytes(amount) {
                    if less { maxSize = bytes } else { minSize = bytes }
                }
            case "age":
                if let (less, amount) = Self.comparison(value), let seconds = Self.seconds(amount) {
                    if less { maxAge = seconds } else { minAge = seconds }
                }
            default:
                words.append(String(token))
            }
        }
    }

    var isEmpty: Bool { self == SearchQuery("") }

    func matches(_ node: FileNode, now: Date = Date()) -> Bool {
        let name = node.name.lowercased()
        if !words.allSatisfy({ name.contains($0) }) { return false }
        if !extensions.isEmpty && (node.isDirectory || !extensions.contains(node.url.pathExtension.lowercased())) { return false }
        if !kinds.isEmpty && !kinds.contains(node.kind) { return false }
        if let minSize, node.size < minSize { return false }
        if let maxSize, node.size > maxSize { return false }
        if minAge != nil || maxAge != nil {
            guard let used = node.lastUsed else { return false }
            let age = now.timeIntervalSince(used)
            if let minAge, age < minAge { return false }
            if let maxAge, age > maxAge { return false }
        }
        return true
    }

    /// Items below `root` that match, largest first, up to `limit`.
    func results(in root: FileNode, limit: Int = 500) -> [FileNode] {
        var found: [FileNode] = []
        let now = Date()
        func visit(_ node: FileNode) {
            for child in node.children {
                if matches(child, now: now) { found.append(child) }
                if child.isDirectory { visit(child) }
            }
        }
        visit(root)
        return Array(found.sorted { $0.size > $1.size }.prefix(limit))
    }

    private static func kind(named name: String) -> FileKind? {
        switch name {
        case "folder", "folders", "dir": .folder
        case "video", "videos", "movie": .video
        case "audio", "music": .audio
        case "image", "images", "photo": .image
        case "archive", "archives", "dmg": .archive
        case "code": .code
        case "document", "documents", "doc", "docs": .document
        case "other": .other
        default: nil
        }
    }

    /// Splits `>300mb` into (less: false, "300mb"). No sign means "at least".
    private static func comparison(_ value: String) -> (Bool, String)? {
        if value.hasPrefix("<") { return (true, String(value.dropFirst())) }
        if value.hasPrefix(">") { return (false, String(value.dropFirst())) }
        return (false, value)
    }

    private static func split(_ amount: String) -> (Double, String)? {
        let digits = amount.prefix { $0.isNumber || $0 == "." }
        guard let number = Double(digits) else { return nil }
        return (number, String(amount.dropFirst(digits.count)))
    }

    private static func bytes(_ amount: String) -> Int64? {
        guard let (number, unit) = split(amount) else { return nil }
        let scale: Double
        switch unit {
        case "", "b": scale = 1
        case "k", "kb": scale = 1e3
        case "m", "mb": scale = 1e6
        case "g", "gb": scale = 1e9
        case "t", "tb": scale = 1e12
        default: return nil
        }
        return Int64(number * scale)
    }

    private static func seconds(_ amount: String) -> TimeInterval? {
        guard let (number, unit) = split(amount) else { return nil }
        let day = 86_400.0
        switch unit {
        case "", "d": return number * day
        case "w": return number * 7 * day
        case "m": return number * 30 * day
        case "y": return number * 365 * day
        default: return nil
        }
    }
}
