//
//  RulesEngineTests.swift
//  BytewiseTests
//

import Foundation
import Testing
@testable import Bytewise

struct RulesEngineTests {
    private let rules = RulesEngine(home: "/Users/test")

    private func verdict(_ path: String) -> Verdict {
        rules.assess(URL(fileURLWithPath: path)).verdict
    }

    @Test(arguments: [
        "/Users/test/Library/Caches/com.example.app",
        "/Users/test/Library/Caches/com.example.app/data/blob",
        "/Users/test/Library/Developer/Xcode/DerivedData",
        "/Users/test/Library/Developer/Xcode/DerivedData/MyApp-abc/Build",
    ])
    func safeLocations(_ path: String) {
        #expect(verdict(path) == .safeToClear)
    }

    @Test(arguments: [
        "/Users/test/Library/Caches",
        "/Users/test/Library/Caches/com.apple.Safari",
        "/Users/test/Library/Application Support/Google",
        "/Users/test/Library/Logs/DiagnosticReports",
        "/Users/test/Library/Developer/Xcode/Archives/2026-10-01",
        "/Users/test/Library/Developer/CoreSimulator/Devices",
        "/Users/test/Downloads/Installer.dmg",
        "/Users/test/Downloads/old/Setup.PKG",
        "/Users/test/code/site/node_modules",
        "/Users/test/code/site/node_modules/react/index.js",
        "/Users/test/.Trash/old.zip",
    ])
    func reviewLocations(_ path: String) {
        #expect(verdict(path) == .review)
    }

    @Test(arguments: [
        "/Users/test/Documents/report.pdf",
        "/Users/test/Desktop/notes.txt",
        "/Users/test/Pictures/Photos Library.photoslibrary",
        "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/file.txt",
        "/Users/test/Library/Mail/V10",
        "/Applications/Xcode.app",
    ])
    func keepLocations(_ path: String) {
        #expect(verdict(path) == .keep)
    }

    @Test(arguments: [
        "/System/Library/Caches",
        "/Library/Caches/com.example",
        "/private/var/vm/sleepimage",
        "/var/vm/sleepimage",
        "/private/tmp/file",
        "/tmp/file",
        "/usr/lib",
    ])
    func systemLocations(_ path: String) {
        #expect(verdict(path) == .managedByMacOS)
    }

    /// Places that look like caches or build files but sit inside user data
    /// or system folders. None of these may ever be marked safe.
    @Test(arguments: [
        "/Users/test/Documents/Library/Caches/thing",
        "/Users/test/Desktop/Projects/app/node_modules",
        "/Users/test/Desktop/DerivedData",
        "/Users/test/Library/Mobile Documents/Library/Caches/x",
        "/Users/test/Pictures/Caches/x",
        "/Library/Developer/Xcode/DerivedData",
        "/System/Library/Caches/com.apple.x",
        "/Users/test/Library/Containers/com.app/Data/Library/Caches/x",
        "/Users/test",
        "/Users/test/Library",
    ])
    func neverSafe(_ path: String) {
        #expect(verdict(path) != .safeToClear)
    }

    @Test func unmatchedPathsAreUnknownWithNoReason() {
        let assessment = rules.assess(URL(fileURLWithPath: "/Users/test/Downloads/notes.txt"))
        #expect(assessment == Assessment(verdict: .unknown, reason: nil))
    }

    @Test func everyMatchHasAReason() {
        let assessment = rules.assess(URL(fileURLWithPath: "/Users/test/Library/Caches/com.example"))
        #expect(assessment.reason?.isEmpty == false)
    }

    @Test func similarNamesDoNotMatch() {
        // "/Library" must not match "/LibraryBackup", and "~/Library/Caches"
        // must not match "~/Library/CachesOld".
        #expect(verdict("/LibraryBackup/file") == .unknown)
        #expect(verdict("/Users/test/Library/CachesOld/file") == .unknown)
    }

    @Test func trailingSlashIsIgnored() {
        #expect(verdict("/Users/test/Library/Caches/") == .review)
    }
}
