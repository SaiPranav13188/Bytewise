//
//  HoldingAreaView.swift
//  Bytewise
//

import SwiftUI

/// Items waiting in the holding area, with Restore. Items older than the
/// retention period can be emptied for good, after a confirmation.
struct HoldingAreaView: View {
    let holdingArea: HoldingArea
    let retentionDays: Int
    let onRestored: ([(item: HeldItem, url: URL)]) -> Void
    let onClose: () -> Void

    @State private var items: [HeldItem] = []
    @State private var expired: [HeldItem] = []
    @State private var message: String?
    @State private var confirmEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Holding Area")
                .font(.title2)
                .bold()
            Text("Items you cleaned up wait here for \(retentionDays) days before they can be emptied. Restore puts an item back where it was. You can change the number of days in Settings.")
                .fixedSize(horizontal: false, vertical: true)

            if items.isEmpty {
                Spacer()
                Text("The holding area is empty.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).bold()
                            Text(item.originalPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(heldText(for: item))
                                .font(.caption)
                                .foregroundStyle(expired.contains { $0.id == item.id } ? .orange : .secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                            .monospacedDigit()
                        Button("Restore") { restore([item]) }
                    }
                }
            }

            if let message {
                Text(message).foregroundStyle(.secondary)
            }

            HStack {
                Text("\(items.count) \(items.count == 1 ? "item" : "items"), \(ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.size }, countStyle: .file))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Empty \(expired.count) Expired…") { confirmEmpty = true }
                    .disabled(expired.isEmpty)
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
        .onAppear(perform: reload)
        .confirmationDialog(
            "Permanently delete \(expired.count) \(expired.count == 1 ? "item" : "items") (\(ByteCountFormatter.string(fromByteCount: expired.reduce(0) { $0 + $1.size }, countStyle: .file)))?",
            isPresented: $confirmEmpty
        ) {
            Button("Delete Permanently", role: .destructive, action: emptyExpired)
        } message: {
            Text("These items have been in the holding area for more than \(retentionDays) days. This cannot be undone.")
        }
    }

    private func heldText(for item: HeldItem) -> String {
        let days = Calendar.current.dateComponents([.day], from: item.movedAt, to: Date()).day ?? 0
        let moved = days == 0 ? "Moved today" : "Moved \(days) \(days == 1 ? "day" : "days") ago"
        let left = retentionDays - days
        return left > 0 ? "\(moved) · can be emptied in \(left) \(left == 1 ? "day" : "days")" : "\(moved) · ready to empty"
    }

    private func reload() {
        items = holdingArea.items()
        expired = holdingArea.expiredItems(olderThan: retentionDays)
    }

    private func restore(_ toRestore: [HeldItem]) {
        var restored: [(item: HeldItem, url: URL)] = []
        var failures: [String] = []
        for item in toRestore {
            do {
                restored.append((item, try holdingArea.restore(item)))
            } catch {
                failures.append("\(item.name): \(FriendlyError.message(for: error))")
            }
        }
        reload()
        onRestored(restored)
        message = failures.isEmpty
            ? "Restored \(restored.count) \(restored.count == 1 ? "item" : "items")."
            : "Could not restore " + failures.joined(separator: "; ")
    }

    private func emptyExpired() {
        var failures: [String] = []
        for item in expired {
            do { try holdingArea.empty(item) } catch { failures.append(item.name) }
        }
        reload()
        message = failures.isEmpty ? "Expired items deleted." : "Could not delete " + failures.joined(separator: ", ")
    }
}
