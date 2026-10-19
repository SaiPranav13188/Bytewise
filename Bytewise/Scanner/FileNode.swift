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
/// Nodes are built on the scanner's background task and never changed after
/// the scan returns, which is why sharing them across threads is safe.
nonisolated final class FileNode: Identifiable, @unchecked Sendable {
    let url: URL
    let isDirectory: Bool
    let kind: FileKind
    private(set) var size: Int64
    private(set) var children: [FileNode] = []
    private(set) weak var parent: FileNode?

    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool, kind: FileKind, size: Int64 = 0) {
        self.url = url
        self.isDirectory = isDirectory
        self.kind = kind
        self.size = size
    }

    func addChild(_ child: FileNode) {
        child.parent = self
        children.append(child)
    }

    /// Sets every folder's size to the total of its children and sorts the
    /// children largest first. Call once, after the whole tree is built.
    @discardableResult
    func rollUpSizes() -> Int64 {
        if isDirectory {
            size = children.reduce(0) { $0 + $1.rollUpSizes() }
            children.sort { $0.size > $1.size }
        }
        return size
    }
}
