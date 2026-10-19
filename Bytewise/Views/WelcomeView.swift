//
//  WelcomeView.swift
//  Bytewise
//

import AppKit
import SwiftUI

enum FullDiskAccess {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// Shows the app in Finder, so it can be dragged into the Full Disk
    /// Access list.
    static func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

/// First-run screen: what the app does, the privacy promise, and how to
/// grant Full Disk Access.
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Bytewise")
                .font(.title)
                .bold()
            Text("Bytewise shows what is using space on your Mac and explains what each location is.")

            Label("Everything stays on your Mac. There is no account, nothing is sent over the network, and Bytewise only reads file names and sizes, never what is inside your files.",
                  systemImage: "lock")

            Divider()

            Text("Full Disk Access")
                .font(.headline)
            Text("macOS protects some folders, such as Mail, Messages and parts of Library. To include them in scans, turn on Bytewise in System Settings › Privacy & Security › Full Disk Access. If Bytewise is not in the list, click +, or drag the app in from Finder.")
            Text("You can skip this now. After a scan, Bytewise tells you if any folders were blocked.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Open Full Disk Access Settings") { FullDiskAccess.openSettings() }
                Button("Show Bytewise in Finder") { FullDiskAccess.revealApp() }
                Spacer()
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

#Preview {
    WelcomeView {}
}
