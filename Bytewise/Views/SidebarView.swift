//
//  SidebarView.swift
//  Bytewise
//

import SwiftUI

/// The left column: the startup disk, common places, and status cards for
/// Full Disk Access and the holding area.
struct SidebarView: View {
    @Bindable var model: ScanModel
    let onShowHoldingArea: () -> Void

    @State private var disk = DiskSpace.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sectionTitle("Disk")
                    diskRow

                    sectionTitle("Places")
                    ForEach(Place.folders) { place in
                        placeRow(place)
                    }
                    Button(action: model.chooseFolder) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                    .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                            Text("Other folder…")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isScanning)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            VStack(spacing: 8) {
                accessCard
                holdingCard
            }
            .padding(10)
        }
        .onAppear { disk = DiskSpace.current() }
        .onChange(of: model.treeVersion) { disk = DiskSpace.current() }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private func isOpen(_ place: Place) -> Bool {
        model.folder?.path == place.url.path
    }

    private var diskRow: some View {
        Button { model.scan(.disk) } label: {
            HStack(spacing: 10) {
                IconTile(symbol: Place.disk.symbol, tint: .orange, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Place.disk.title).font(.system(size: 13, weight: .semibold))
                    if let disk {
                        Text("\(Format.bytes(disk.available)) free of \(Format.bytes(disk.total))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ShareBar(fraction: Double(disk.used) / Double(max(disk.total, 1)), tint: .orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(rowBackground(isOpen(.disk)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isScanning)
        .help("Scan the whole disk")
    }

    private func placeRow(_ place: Place) -> some View {
        Button { model.scan(place) } label: {
            HStack(spacing: 10) {
                IconTile(symbol: place.symbol, tint: place.tint)
                Text(place.title).font(.system(size: 13, weight: .medium))
                Spacer()
                if !FolderAccess.hasAccess(to: place.url) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("Bytewise will ask you to confirm this folder the first time.")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(rowBackground(isOpen(place)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isScanning)
    }

    private func rowBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear))
    }

    /// Whether the last scan was blocked anywhere. Unknown before a scan.
    private var accessCard: some View {
        let blocked = model.unreadable.count
        let scanned = model.root != nil
        return Button { FullDiskAccess.openSettings() } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(!scanned ? Color.secondary : blocked == 0 ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text("Full Disk Access").font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                Text(!scanned ? "Lets Bytewise read protected folders."
                     : blocked == 0 ? "Every folder in this scan was readable."
                     : "\(blocked.formatted()) \(blocked == 1 ? "folder was" : "folders were") blocked, so sizes may be low. Click to fix.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.unreadable.prefix(10).map(\.path).joined(separator: "\n"))
    }

    private var holdingCard: some View {
        let items = model.heldItems
        return Button(action: onShowHoldingArea) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Holding area").font(.system(size: 12, weight: .semibold))
                    Text(items.isEmpty ? "Empty"
                         : "\(items.count) \(items.count == 1 ? "item" : "items") · \(Format.bytes(items.reduce(0) { $0 + $1.size }))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .card(padding: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
