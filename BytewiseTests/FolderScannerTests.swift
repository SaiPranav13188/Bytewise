//
//  FolderScannerTests.swift
//  BytewiseTests
//

import Foundation
import Testing
@testable import Bytewise

/// Builds a throwaway folder with known contents and removes it afterwards.
private final class TestFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BytewiseTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        // Restore permissions first so locked test folders can be removed.
        if let items = FileManager.default.enumerator(atPath: url.path) {
            for case let item as String in items {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: url.appendingPathComponent(item).path)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ path: String, bytes: Int) throws -> URL {
        let fileURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: fileURL)
        return fileURL
    }

    func folder(_ path: String) throws -> URL {
        let folderURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}

private func allocatedSize(_ url: URL) throws -> Int64 {
    Int64(try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0)
}

struct FolderScannerTests {
    @Test func foldersAddUpTheirContents() async throws {
        let folder = try TestFolder()
        let a = try folder.file("big/a.bin", bytes: 300_000)
        let b = try folder.file("big/nested/b.bin", bytes: 100_000)
        let c = try folder.file("small.txt", bytes: 5_000)

        let result = try await FolderScanner.scan(folder.url)
        let root = result.root

        let expected = try allocatedSize(a) + allocatedSize(b) + allocatedSize(c)
        #expect(root.size == expected)
        #expect(root.children.map(\.name) == ["big", "small.txt"])
        #expect(root.children[0].size == (try allocatedSize(a) + allocatedSize(b)))
        #expect(result.unreadable.isEmpty)
    }

    @Test func childrenAreSortedLargestFirst() async throws {
        let folder = try TestFolder()
        try folder.file("one.bin", bytes: 10_000)
        try folder.file("three.bin", bytes: 900_000)
        try folder.file("two.bin", bytes: 200_000)

        let root = try await FolderScanner.scan(folder.url).root
        #expect(root.children.map(\.name) == ["three.bin", "two.bin", "one.bin"])
    }

    @Test func symbolicLinksAreNotFollowedOrCounted() async throws {
        let folder = try TestFolder()
        let target = try folder.file("real/data.bin", bytes: 500_000)
        try FileManager.default.createSymbolicLink(
            at: folder.url.appendingPathComponent("link"),
            withDestinationURL: target.deletingLastPathComponent())

        let root = try await FolderScanner.scan(folder.url).root
        #expect(root.children.map(\.name) == ["real"])
        #expect(root.size == (try allocatedSize(target)))
    }

    @Test func unreadableFoldersAreReportedNotFatal() async throws {
        let folder = try TestFolder()
        try folder.file("open/ok.bin", bytes: 50_000)
        let locked = try folder.folder("locked")
        try folder.file("locked/hidden.bin", bytes: 50_000)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)

        let result = try await FolderScanner.scan(folder.url)
        #expect(result.unreadable.map(\.lastPathComponent) == ["locked"])
        #expect(result.root.children.first { $0.name == "locked" }?.size == 0)
        #expect(result.root.children.first { $0.name == "open" }?.size ?? 0 > 0)
    }

    @Test func parentLinksPointUpTheTree() async throws {
        let folder = try TestFolder()
        try folder.file("a/b/c.txt", bytes: 1_000)

        let root = try await FolderScanner.scan(folder.url).root
        let c = try #require(root.children.first?.children.first?.children.first)
        #expect(c.name == "c.txt")
        #expect(c.parent?.parent?.parent === root)
    }

    @Test func excludedFoldersAreLeftOut() async throws {
        let folder = try TestFolder()
        try folder.file("keep/a.bin", bytes: 50_000)
        let skipped = try folder.file("skip/inner/b.bin", bytes: 500_000).deletingLastPathComponent().deletingLastPathComponent()

        let result = try await FolderScanner.scan(folder.url, excluding: [skipped.path])
        #expect(result.root.children.map(\.name) == ["keep"])
        #expect(result.root.size == result.root.children[0].size)
    }

    @Test func foldersTakeTheLatestDateOfTheirContents() async throws {
        let folder = try TestFolder()
        let old = try folder.file("box/old.txt", bytes: 10)
        let new = try folder.file("box/new.txt", bytes: 10)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: new.path)

        let box = try #require(try await FolderScanner.scan(folder.url).root.children.first)
        // Opening a file can move its date later still, so only a lower bound is certain.
        #expect(try #require(box.lastUsed) >= newDate)
    }

    @Test func fileKindsComeFromExtensions() {
        #expect(FileKind(fileExtension: "mov") == .video)
        #expect(FileKind(fileExtension: "mp3") == .audio)
        #expect(FileKind(fileExtension: "png") == .image)
        #expect(FileKind(fileExtension: "dmg") == .archive)
        #expect(FileKind(fileExtension: "zip") == .archive)
        #expect(FileKind(fileExtension: "swift") == .code)
        #expect(FileKind(fileExtension: "pdf") == .document)
        #expect(FileKind(fileExtension: "bin") == .other)
        #expect(FileKind(fileExtension: "") == .other)
    }
}
