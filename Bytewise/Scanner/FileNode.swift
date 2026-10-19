//
//  FileNode.swift
//  Bytewise
//

import Foundation
import UniformTypeIdentifiers

/// Broad file kinds used to colour the map.
nonisolated enum FileKind: CaseIterable, Sendable {
    case folder, video, audio, image, archive, code, document, other

    init(fileExtension ext: String) {
        // macOS maps .bin to the old MacBinary archive format, but today it is
        // almost always raw data such as AI model weights or firmware.
        guard !ext.isEmpty, ext != "bin", let type = UTType(filenameExtension: ext) else {
            self = .other
            return
        }
        if type.conforms(to: .movie) { self = .video }
        else if type.conforms(to: .audio) { self = .audio }
        else if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .archive) || type.conforms(to: .diskImage) { self = .archive }
        // Source code is also plain text, so check it before documents.
        else if type.conforms(to: .sourceCode) || type.conforms(to: .script) { self = .code }
        else if type.conforms(to: .text) || type.conforms(to: .pdf)
                    || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet) {
            self = .document
        }
        else { self = .other }
    }

    var label: String {
        switch self {
        case .folder: "Folders"
        case .video: "Video"
        case .audio: "Audio"
        case .image: "Images"
        case .archive: "Archives & disk images"
        case .code: "Code"
        case .document: "Documents"
        case .other: "Other"
        }
    }
}

/// One file or folder in a scanned tree. Folder sizes include everything
/// inside them, and children are sorted largest first.
///
/// Nodes are built on the scanner's background task. After the scan returns
/// they are only changed on the main thread (when items are moved to or back
/// from the holding area), which is why sharing them across threads is safe.
nonisolated final class FileNode: Identifiable, @unchecked Sendable {
    let url: URL
    let isDirectory: Bool
    let kind: FileKind
    private(set) var size: Int64
    /// When the item was last opened or changed, whichever is later. For
    /// folders, the latest of everything inside. Approximate: macOS does
    /// not always record when a file was opened.
    private(set) var lastUsed: Date?
    private(set) var children: [FileNode] = []
    private(set) weak var parent: FileNode?

    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool, kind: FileKind, size: Int64 = 0, lastUsed: Date? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.kind = kind
        self.size = size
        self.lastUsed = lastUsed
    }

    func addChild(_ child: FileNode) {
        child.parent = self
        children.append(child)
    }

    /// Takes this node out of the tree, for when it has been moved away.
    /// Every folder above it shrinks by its size.
    func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        parent.adjustSize(by: -size)
        self.parent = nil
    }

    /// Puts a detached node back under `parent`, for when it is restored.
    func attach(to parent: FileNode) {
        parent.addChild(self)
        parent.adjustSize(by: size)
    }

    /// Changes this folder's size and every folder above it, keeping each
    /// level sorted largest first.
    private func adjustSize(by delta: Int64) {
        var node: FileNode? = self
        while let folder = node {
            folder.size += delta
            folder.children.sort { $0.size > $1.size }
            node = folder.parent
        }
    }

    /// Sets every folder's size to the total of its children and its last
    /// used date to the latest of theirs, and sorts the children largest
    /// first. Call once, after the whole tree is built.
    @discardableResult
    func rollUpSizes() -> Int64 {
        if isDirectory {
            size = children.reduce(0) { $0 + $1.rollUpSizes() }
            lastUsed = children.compactMap(\.lastUsed).max()
            children.sort { $0.size > $1.size }
        }
        return size
    }
}
