//
//  ContentView.swift
//  Bytewise
//
//  Created by Sai Pranav on 19/10/26.
//

import SwiftUI

struct ContentView: View {
    @State private var model = ScanModel()
    @State private var tab = Tab.explore
    @State private var searchText = ""
    @State private var cleanupPlan: [PlannedMove]?
    @State private var showHoldingArea = false
    @FocusState private var searchFocused: Bool
    @AppStorage(AppSettings.hasSeenWelcomeKey) private var hasSeenWelcome = false
    @AppStorage(AppSettings.holdingDaysKey) private var holdingDays = HoldingArea.defaultRetentionDays

    private enum Tab: String, CaseIterable {
        case explore = "Explore"
        case biggest = "Biggest files"
        case cleanup = "Clean up"
        case models = "AI models"
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model) { showHoldingArea = true }
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            detail
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(removing: .title)
        .frame(minWidth: 1000, minHeight: 600)
        .onChange(of: model.folder) {
            tab = .explore
            searchText = ""
        }
        .sheet(isPresented: Binding(get: { !hasSeenWelcome },
                                    set: { hasSeenWelcome = !$0 })) {
            WelcomeView { hasSeenWelcome = true }
        }
        .sheet(isPresented: Binding(get: { cleanupPlan != nil },
                                    set: { if !$0 { cleanupPlan = nil } })) {
            CleanupSheet(plan: cleanupPlan ?? [],
                         retentionDays: holdingDays,
                         onDryRun: model.makePlan,
                         onMove: { plan in
                             model.performMove(plan)
                             cleanupPlan = nil
                         },
                         onCancel: { cleanupPlan = nil })
        }
        .sheet(isPresented: $showHoldingArea) {
            HoldingAreaView(holdingArea: ScanModel.holdingArea,
                            retentionDays: holdingDays,
                            onRestored: model.putBack,
                            onClose: {
                                showHoldingArea = false
                                model.refreshHeldItems()
                            })
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.isScanning {
            ScanningView(model: model)
        } else if let current = model.current, let root = model.root {
            VStack(alignment: .leading, spacing: 14) {
                header(current)
                tabBar
                banners
                Group {
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        SearchResultsView(model: model, folder: current, text: searchText)
                    } else {
                        switch tab {
                        case .explore: ExploreView(model: model, folder: current)
                        case .biggest: BiggestFilesView(model: model, folder: current)
                        case .cleanup: CleanupListView(model: model, root: root)
                        case .models:
                            AIModelsView(models: model.aiModels, rules: ScanModel.rules) { node in
                                // Open the folder that holds the model, so it
                                // shows in the list and can be picked for cleanup.
                                model.current = node.parent ?? node
                                tab = .explore
                            }
                            .card(padding: 18)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                if !model.selected.isEmpty {
                    selectionBar
                }
            }
        } else {
            EmptyStateView(model: model)
        }
    }

    // MARK: Header

    private func header(_ current: FileNode) -> some View {
        HStack(spacing: 12) {
            Button(action: model.goUp) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(current.parent == nil)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("Go up one folder (⌘↑)")

            VStack(alignment: .leading, spacing: 1) {
                Text(current.name)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                breadcrumb
            }

            Spacer(minLength: 20)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search, e.g. ext:dmg size:>500mb", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onExitCommand { searchText = "" }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("⌘F").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 300)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden())

            Button(action: model.rescan) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.quaternary.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r")
            .help("Scan again (⌘R)")
        }
    }

    /// The path from the scanned folder down to the open one. Click a part
    /// to go back up to it.
    private var breadcrumb: some View {
        let chain = model.path
        return HStack(spacing: 3) {
            ForEach(chain) { step in
                if step !== chain.first {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Button(step === chain.first ? step.url.path : step.name) { model.current = step }
                    .buttonStyle(.plain)
                    .foregroundStyle(step === chain.last ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .truncationMode(.head)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { item in
                let isOn = tab == item && searchText.isEmpty
                Button {
                    tab = item
                    searchText = ""
                } label: {
                    HStack(spacing: 5) {
                        Text(item.rawValue)
                        if item == .models && !model.aiModels.isEmpty {
                            Text("\(model.aiModels.count)")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 5)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(isOn ? Color.white : .primary)
                    .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Messages

    @ViewBuilder
    private var banners: some View {
        if let message = model.statusMessage {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(message)
                Spacer()
                if !model.lastMoved.isEmpty {
                    Button("Undo", action: model.undoLastMove)
                }
                Button { model.statusMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .card(padding: 10)
        }
        if let message = model.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
                Spacer()
                Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .card(padding: 10)
        }
    }

    /// Shown while anything is picked for cleanup, on every tab.
    private var selectionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .foregroundStyle(Color.accentColor)
            Text("\(model.selected.count) \(model.selected.count == 1 ? "item" : "items") picked")
                .fontWeight(.semibold)
            SizeText(bytes: model.selectedSize)
            Spacer()
            Button("Clear", action: model.clearSelection)
            Button("Review and Clean Up…") { cleanupPlan = model.makePlan() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .card(padding: 12)
    }
}

/// Progress while a scan runs.
private struct ScanningView: View {
    let model: ScanModel

    var body: some View {
        let progress = model.progress
        VStack(spacing: 18) {
            ProgressView(value: Double(progress.itemsDone), total: Double(max(progress.itemsTotal, 1)))
                .progressViewStyle(.circular)
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("Reading \(model.folder?.lastPathComponent.isEmpty == false ? model.folder!.lastPathComponent : "your disk")…")
                    .font(.title2.weight(.semibold))
                Text(progress.currentItem.isEmpty ? " " : progress.currentItem)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(progress.filesScanned.formatted()) files · \(min(progress.itemsDone + 1, max(progress.itemsTotal, 1))) of \(progress.itemsTotal) top-level items")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: model.cancelScan)
                .keyboardShortcut(.cancelAction)
        }
        .frame(width: 420)
        .padding(32)
        .card()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shown before the first scan.
private struct EmptyStateView: View {
    let model: ScanModel

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "square.split.2x2.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor.gradient)
            VStack(spacing: 8) {
                Text("See where your space went")
                    .font(.largeTitle.weight(.bold))
                Text("Pick a place in the sidebar, or start with your Home folder. Bytewise reads names and sizes only, and nothing leaves your Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            if let disk = DiskSpace.current() {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(disk.name).fontWeight(.semibold)
                        Spacer()
                        Text("\(Format.bytes(disk.used)) used · \(Format.bytes(disk.available)) free")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    ShareBar(fraction: Double(disk.used) / Double(max(disk.total, 1)), tint: .orange)
                        .frame(height: 8)
                }
                .frame(width: 420)
                .card()
            }
            HStack(spacing: 10) {
                Button("Scan Home") { model.scan(.home) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("Scan Whole Disk") { model.scan(.disk) }
                    .controlSize(.large)
                Button("Choose Folder…", action: model.chooseFolder)
                    .controlSize(.large)
            }
            if let message = model.errorMessage ?? model.statusMessage {
                Text(message).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
