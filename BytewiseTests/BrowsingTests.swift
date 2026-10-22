//
//  BrowsingTests.swift
//  BytewiseTests
//

import Foundation
import Testing
@testable import Bytewise

/// Builds an in-memory tree from paths and sizes, without touching the disk.
private func tree(_ root: String, _ files: [(String, Int64)], lastUsed: Date? = nil) -> FileNode {
    let rootNode = FileNode(url: URL(fileURLWithPath: root), isDirectory: true, kind: .folder)
    var folders = [root: rootNode]
    for (path, size) in files {
        var parent = rootNode
        var current = root
        let parts = path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() {
            current += "/" + part
            if index == parts.count - 1 {
                let url = URL(fileURLWithPath: current)
                parent.addChild(FileNode(url: url, isDirectory: false,
                                         kind: FileKind(fileExtension: url.pathExtension.lowercased()),
                                         size: size, lastUsed: lastUsed))
            } else if let folder = folders[current] {
                parent = folder
            } else {
                let folder = FileNode(url: URL(fileURLWithPath: current), isDirectory: true, kind: .folder)
                parent.addChild(folder)
                folders[current] = folder
                parent = folder
            }
        }
    }
    rootNode.rollUpSizes()
    return rootNode
}

struct BrowsingTests {
    @Test func foldersCountFilesAndBytesPerKind() throws {
        let root = tree("/r", [("a/movie.mov", 500), ("a/b/song.mp3", 200), ("c.dmg", 300)])
        #expect(root.fileCount == 3)
        #expect(root.kindSizes[.video] == 500)
        #expect(root.kindSizes[.archive] == 300)
        #expect(root.kindSizes.dominant == .video)

        let a = try #require(root.children.first { $0.name == "a" })
        a.detach()
        #expect(root.fileCount == 1)
        #expect(root.kindSizes[.video] == 0)
        #expect(root.size == 300)

        a.attach(to: root)
        #expect(root.fileCount == 3)
        #expect(root.kindSizes[.audio] == 200)
    }

    @Test func searchParsesFilters() {
        let query = SearchQuery("ext:dmg,.pkg size:>300mb age:<2w Install")
        #expect(query.extensions == ["dmg", "pkg"])
        #expect(query.minSize == 300_000_000)
        #expect(query.maxAge == TimeInterval(14 * 86_400))
        #expect(query.words == ["install"])
        #expect(SearchQuery("  ").isEmpty)
    }

    @Test func searchFindsMatchesLargestFirst() {
        let old = Date(timeIntervalSinceNow: -200 * 86_400)
        let root = tree("/r", [("Installer.dmg", 400_000_000), ("x/Big Installer.dmg", 900_000_000),
                               ("small.dmg", 1_000), ("notes.txt", 500_000_000)], lastUsed: old)
        #expect(SearchQuery("ext:dmg size:>300mb").results(in: root).map(\.name) == ["Big Installer.dmg", "Installer.dmg"])
        #expect(SearchQuery("kind:document").results(in: root).map(\.name) == ["notes.txt"])
        #expect(SearchQuery("age:>90d ext:dmg").results(in: root).count == 3)
        #expect(SearchQuery("age:<30d").results(in: root).isEmpty)
    }

    @Test func biggestFilesLooksAtEveryDepth() {
        let root = tree("/r", [("a/b/c/deep.bin", 900), ("top.bin", 100), ("a/mid.bin", 500)])
        #expect(BiggestFiles.find(in: root, limit: 2).map(\.name) == ["deep.bin", "mid.bin"])
    }

    @Test func cleanupListsInnerItemsAndNeverUserData() {
        let home = "/Users/test"
        let rules = RulesEngine(home: home)
        let root = tree(home, [
            ("Library/Caches/com.example.app/blob", 5_000_000),
            ("Library/Caches/org.other/blob", 3_000_000),
            ("Library/Developer/Xcode/DerivedData/App-abc/build", 9_000_000),
            ("Documents/Big.mov", 90_000_000),
            ("Projects/site/node_modules/pkg/index.js", 2_000_000),
        ])
        let found = CleanupFinder.candidates(in: root, rules: rules).map(\.name)
        #expect(found == ["DerivedData", "com.example.app", "org.other", "node_modules"])
    }
}
