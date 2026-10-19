//
//  HoldingAreaTests.swift
//  BytewiseTests
//

import Foundation
import Testing
@testable import Bytewise

/// A throwaway workspace with a "disk" folder holding the user's files and
/// a separate holding area, both removed afterwards.
private final class Workspace {
    let root: URL
    let disk: URL
    let holding: HoldingArea

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BytewiseHolding-\(UUID().uuidString)")
        disk = root.appendingPathComponent("disk")
        holding = HoldingArea(directory: root.appendingPathComponent("holding"))
        try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ path: String, text: String = "hello") throws -> URL {
        let url = disk.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func candidate(_ url: URL, _ verdict: Verdict = .safeToClear, usedBy: String? = nil) -> CleanupCandidate {
        CleanupCandidate(url: url, size: 5, assessment: Assessment(verdict: verdict, reason: "test"),
                         usedBy: usedBy)
    }
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

struct HoldingAreaTests {
    @Test func moveThenRestoreRoundTrip() throws {
        let space = try Workspace()
        let cache = try space.file("Caches/app/data.txt", text: "keep me")
        let folder = cache.deletingLastPathComponent()

        let result = space.holding.move(space.holding.plan([space.candidate(folder)]), scopeBookmark: nil)
        #expect(result.failures.isEmpty)
        #expect(result.moved.count == 1)
        #expect(!exists(folder))
        #expect(space.holding.items().count == 1)

        let restored = try space.holding.restore(try #require(result.moved.first))
        #expect(restored.path == folder.path)
        #expect(try String(contentsOf: cache, encoding: .utf8) == "keep me")
        #expect(space.holding.items().isEmpty)
    }

    @Test func planningIsADryRunThatChangesNothing() throws {
        let space = try Workspace()
        let file = try space.file("Caches/a.txt")

        let plan = space.holding.plan([space.candidate(file)])
        #expect(plan.count == 1 && plan[0].willMove)
        #expect(exists(file))
        #expect(space.holding.items().isEmpty)
        #expect(!exists(space.holding.directory))
    }

    @Test(arguments: [Verdict.keep, .managedByMacOS, .unknown])
    func protectedVerdictsAreNeverMoved(_ verdict: Verdict) throws {
        let space = try Workspace()
        let file = try space.file("Documents/report.txt")

        let plan = space.holding.plan([space.candidate(file, verdict)])
        #expect(!plan[0].willMove)
        let result = space.holding.move(plan, scopeBookmark: nil)
        #expect(result.moved.isEmpty)
        #expect(exists(file))
    }

    @Test func itemsUsedByAnOpenAppAreSkipped() throws {
        let space = try Workspace()
        let file = try space.file("Caches/Chrome/a.txt")

        let plan = space.holding.plan([space.candidate(file, usedBy: "Google Chrome")])
        #expect(plan[0].skipReason?.contains("Google Chrome") == true)
    }

    @Test func childOfASelectedFolderIsNotMovedTwice() throws {
        let space = try Workspace()
        let child = try space.file("Caches/app/inner.txt")
        let parent = child.deletingLastPathComponent()

        let plan = space.holding.plan([space.candidate(parent), space.candidate(child)])
        #expect(plan[0].willMove)
        #expect(!plan[1].willMove)
        #expect(space.holding.move(plan, scopeBookmark: nil).moved.count == 1)
    }

    @Test func missingItemsAreSkipped() throws {
        let space = try Workspace()
        let gone = space.disk.appendingPathComponent("nothing-here")
        #expect(space.holding.plan([space.candidate(gone)])[0].skipReason == "No longer exists.")
    }

    @Test func itemsAlreadyInTheHoldingAreaAreSkipped() throws {
        let space = try Workspace()
        let file = try space.file("Caches/a.txt")
        let held = try #require(space.holding.move(space.holding.plan([space.candidate(file)]),
                                                   scopeBookmark: nil).moved.first)

        let plan = space.holding.plan([space.candidate(URL(fileURLWithPath: held.heldPath))])
        #expect(plan[0].skipReason == "Already in the holding area.")
    }

    @Test func restoreDoesNotOverwriteANewItemWithTheSameName() throws {
        let space = try Workspace()
        let file = try space.file("Caches/notes.txt", text: "old")
        let held = try #require(space.holding.move(space.holding.plan([space.candidate(file)]),
                                                   scopeBookmark: nil).moved.first)
        try space.file("Caches/notes.txt", text: "new")

        let restored = try space.holding.restore(held)
        #expect(restored.lastPathComponent == "notes (restored).txt")
        #expect(try String(contentsOf: file, encoding: .utf8) == "new")
        #expect(try String(contentsOf: restored, encoding: .utf8) == "old")
    }

    @Test func restoreRecreatesAMissingParentFolder() throws {
        let space = try Workspace()
        let file = try space.file("Caches/app/a.txt")
        let held = try #require(space.holding.move(space.holding.plan([space.candidate(file)]),
                                                   scopeBookmark: nil).moved.first)
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())

        #expect(try space.holding.restore(held).path == file.path)
        #expect(exists(file))
    }

    @Test func logSurvivesARelaunch() throws {
        let space = try Workspace()
        let file = try space.file("Caches/a.txt")
        _ = space.holding.move(space.holding.plan([space.candidate(file)]), scopeBookmark: nil)

        let reopened = HoldingArea(directory: space.holding.directory)
        #expect(reopened.items().map(\.originalPath) == [file.path])
    }

    @Test func onlyOldItemsExpire() throws {
        let space = try Workspace()
        let file = try space.file("Caches/a.txt")
        _ = space.holding.move(space.holding.plan([space.candidate(file)]), scopeBookmark: nil)

        #expect(space.holding.expiredItems().isEmpty)
        let later = Date().addingTimeInterval(31 * 24 * 60 * 60)
        #expect(space.holding.expiredItems(now: later).count == 1)
    }

    @Test func emptyingDeletesOnlyThatItem() throws {
        let space = try Workspace()
        let a = try space.file("Caches/a.txt")
        let b = try space.file("Caches/b.txt")
        let moved = space.holding.move(space.holding.plan([space.candidate(a), space.candidate(b)]),
                                       scopeBookmark: nil).moved
        let heldA = try #require(moved.first { $0.originalPath == a.path })

        try space.holding.empty(heldA)
        #expect(!exists(URL(fileURLWithPath: heldA.heldPath)))
        #expect(space.holding.items().map(\.originalPath) == [b.path])
    }
}

struct AppUsageTests {
    private let apps = [
        RunningApp(name: "Google Chrome", bundleID: "com.google.Chrome"),
        RunningApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        RunningApp(name: "Brave Browser", bundleID: "com.brave.Browser"),
    ]

    @Test func matchesNeighbouringFolderNames() {
        #expect(AppUsage.app(using: [["Caches", "Google", "Chrome"]], among: apps) == "Google Chrome")
    }

    @Test func matchesNamesWithPunctuation() {
        #expect(AppUsage.app(using: [["BraveSoftware", "Brave-Browser"]], among: apps) == "Brave Browser")
    }

    @Test func matchesBundleIDFolders() {
        #expect(AppUsage.app(using: [["Caches", "com.google.Chrome"]], among: apps) == "Google Chrome")
        #expect(AppUsage.app(using: [["com.todesktop.230313mzl4w4u92.ShipIt"]], among: apps) == "Cursor")
    }

    @Test func ignoresUnrelatedFolders() {
        #expect(AppUsage.app(using: [["Caches", "Homebrew", "downloads"]], among: apps) == nil)
        // A bundle ID must match whole parts, not just the start of a word.
        #expect(AppUsage.app(using: [["com.google.ChromeHelperOld"]], among: apps) == nil)
    }
}
