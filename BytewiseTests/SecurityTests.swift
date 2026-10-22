//
//  SecurityTests.swift
//  BytewiseTests
//

import Foundation
import Testing
@testable import Bytewise

/// A throwaway folder with a holding area inside it, removed afterwards.
private final class Sandbox {
    let root: URL
    let holding: HoldingArea

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BytewiseSecurity-\(UUID().uuidString)")
        holding = HoldingArea(directory: root.appendingPathComponent("holding"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ name: String, text: String = "data") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func plan(_ url: URL) -> [PlannedMove] {
        holding.plan([CleanupCandidate(url: url, size: 4,
                                       assessment: Assessment(verdict: .safeToClear, reason: "test"),
                                       usedBy: nil)])
    }

    /// Writes a log entry by hand, as a damaged or edited log would.
    func forgeEntry(heldPath: String, originalPath: String) throws -> HeldItem {
        let item = HeldItem(id: UUID(), originalPath: originalPath, heldPath: heldPath, size: 1,
                            movedAt: .distantPast, reason: nil, scopeBookmark: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: holding.directory, withIntermediateDirectories: true)
        try encoder.encode([item]).write(to: holding.directory.appendingPathComponent("log.json"))
        return item
    }
}

struct SecurityTests {
    private let rules = RulesEngine(home: "/Users/test")

    private func verdict(_ path: String) -> Verdict {
        rules.assess(URL(fileURLWithPath: path)).verdict
    }

    @Test(arguments: [
        "/Users/test/documents/report.pdf",
        "/Users/test/DESKTOP",
        "/users/test/pictures/Photos Library.photoslibrary",
        "/Users/test/library/mobile documents/com~apple~CloudDocs",
    ])
    func userDataIsProtectedWhateverTheCase(_ path: String) {
        #expect(verdict(path) == .keep)
    }

    @Test func systemFoldersAreProtectedWhateverTheCase() {
        #expect(verdict("/system/Library") == .managedByMacOS)
        #expect(verdict("/LIBRARY/Caches") == .managedByMacOS)
    }

    @Test func cleanupRulesStillMatchExactly() {
        // On a case-sensitive disk this is a different folder, so it is not
        // trusted as a cache.
        #expect(verdict("/Users/test/library/caches/com.example.app") != .safeToClear)
        #expect(verdict("/Users/test/Library/Caches/com.example.app") == .safeToClear)
    }

    @Test func pathsWithDotPartsAreNeverTrusted() {
        let sneaky = URL(string: "file:///Users/test/Documents/../Library/Caches/com.example.app")!
        #expect(rules.assess(sneaky).verdict == .unknown)
        let dotted = URL(string: "file:///Users/test/Library/Caches/./com.example.app")!
        #expect(rules.assess(dotted).verdict == .unknown)
    }

    @Test func itemSwappedAfterPreviewIsNotMoved() throws {
        let box = try Sandbox()
        let file = try box.file("cache.bin", text: "old")
        let plan = box.plan(file)
        #expect(plan[0].willMove)

        // Something else takes the same name before the user confirms.
        try FileManager.default.removeItem(at: file)
        try box.file("other.bin", text: "important")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: box.root.appendingPathComponent("other.bin"))

        let result = box.holding.move(plan, scopeBookmark: nil)
        #expect(result.moved.isEmpty)
        #expect(result.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: box.root.appendingPathComponent("other.bin").path))
    }

    @Test func unchangedItemStillMoves() throws {
        let box = try Sandbox()
        let file = try box.file("cache.bin")
        #expect(box.holding.move(box.plan(file), scopeBookmark: nil).moved.count == 1)
    }

    @Test func forgedLogCannotDeleteFilesOutsideTheHoldingArea() throws {
        let box = try Sandbox()
        let victim = try box.file("precious.txt")
        let item = try box.forgeEntry(heldPath: victim.path, originalPath: "/tmp/x")

        #expect(throws: HoldingAreaError.self) { try box.holding.empty(item) }
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }

    @Test func forgedLogCannotMoveFilesFromOutsideTheHoldingArea() throws {
        let box = try Sandbox()
        let victim = try box.file("precious.txt")
        let traversal = box.holding.directory.path + "/\(UUID().uuidString)/../../precious.txt"
        let item = try box.forgeEntry(heldPath: traversal, originalPath: box.root.appendingPathComponent("moved.txt").path)

        #expect(throws: HoldingAreaError.self) { try box.holding.restore(item) }
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }

    @Test func openAppMatchedByProgramOrBundleName() {
        let apps = [RunningApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", executableName: "Code")]
        #expect(AppUsage.app(using: [["Application Support", "Code"]], among: apps) == "Visual Studio Code")
        #expect(AppUsage.app(using: [["Caches", "vscode"]], among: apps) == "Visual Studio Code")
        #expect(AppUsage.app(using: [["Caches", "Homebrew"]], among: apps) == nil)
    }
}
