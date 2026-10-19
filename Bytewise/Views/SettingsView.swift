//
//  SettingsView.swift
//  Bytewise
//

import SwiftUI
import UniformTypeIdentifiers

/// The Settings window: excluded folders, how long the holding area keeps
/// items, and the welcome screen.
struct SettingsView: View {
    @AppStorage(AppSettings.excludedFoldersKey) private var excludedText = ""
    @AppStorage(AppSettings.holdingDaysKey) private var holdingDays = HoldingArea.defaultRetentionDays
    @AppStorage(AppSettings.hasSeenWelcomeKey) private var hasSeenWelcome = false
    @State private var showImporter = false

    private var excluded: [String] { AppSettings.excludedFolders(from: excludedText) }

    var body: some View {
        Form {
            Section {
                if excluded.isEmpty {
                    Text("No folders are excluded.")
                        .foregroundStyle(.secondary)
                }
                ForEach(excluded, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove") { setExcluded(excluded.filter { $0 != path }) }
                    }
                }
                Button("Add Folder…") { showImporter = true }
            } header: {
                Text("Excluded folders")
            } footer: {
                Text("Scans skip these folders and everything in them. Takes effect on the next scan.")
            }

            Section {
                Picker("Keep items for", selection: $holdingDays) {
                    ForEach(AppSettings.holdingDayChoices, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
            } header: {
                Text("Holding area")
            } footer: {
                Text("Items can be emptied from the holding area after this many days. They are never deleted without asking you first.")
            }

            Section {
                Button("Show Welcome Screen Again") { hasSeenWelcome = false }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                setExcluded(excluded + urls.map(\.path).filter { !excluded.contains($0) })
            }
        }
    }

    private func setExcluded(_ paths: [String]) {
        excludedText = paths.joined(separator: "\n")
    }
}

#Preview {
    SettingsView()
}
