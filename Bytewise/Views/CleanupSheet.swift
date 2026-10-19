//
//  CleanupSheet.swift
//  Bytewise
//

import SwiftUI

/// Preview before anything moves: each item, its size and reason, and why
/// any are skipped. Dry Run checks again and reports without moving.
struct CleanupSheet: View {
    let plan: [PlannedMove]
    let retentionDays: Int
    let onDryRun: () -> [PlannedMove]
    let onMove: ([PlannedMove]) -> Void
    let onCancel: () -> Void

    @State private var dryRunResult: String?
    @State private var current: [PlannedMove] = []

    private var moving: [PlannedMove] { current.filter(\.willMove) }
    private var totalSize: Int64 { moving.reduce(0) { $0 + $1.candidate.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move to Holding Area")
                .font(.title2)
                .bold()
            Text("These items will be moved to Bytewise's holding area, not deleted. You can put any of them back from the Holding Area. They stay there until you empty them, which you can do after \(retentionDays) days.")
                .fixedSize(horizontal: false, vertical: true)

            List(current) { entry in
                HStack(alignment: .top) {
                    Image(systemName: entry.willMove ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(entry.willMove ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.candidate.url.lastPathComponent).bold()
                            VerdictChip(verdict: entry.candidate.assessment.verdict)
                        }
                        Text(entry.candidate.url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let skip = entry.skipReason {
                            Text("Skipped: \(skip)").font(.caption).foregroundStyle(.orange)
                        } else if let reason = entry.candidate.assessment.reason {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: entry.candidate.size, countStyle: .file))
                        .monospacedDigit()
                        .foregroundStyle(entry.willMove ? .primary : .secondary)
                }
            }
            .frame(minHeight: 220)

            Text(summary).bold()

            if let dryRunResult {
                Label(dryRunResult, systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Dry Run") {
                    current = onDryRun()
                    dryRunResult = "Dry run: \(moving.count) \(moving.count == 1 ? "item" : "items") (\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))) would be moved. Nothing was changed."
                }
                Button("Move to Holding Area") { onMove(current) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(moving.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .onAppear { current = plan }
    }

    private var summary: String {
        let skipped = current.count - moving.count
        var text = "\(moving.count) \(moving.count == 1 ? "item" : "items"), \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)) will be moved."
        if skipped > 0 { text += " \(skipped) skipped." }
        return text
    }
}
