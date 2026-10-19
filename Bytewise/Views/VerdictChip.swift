//
//  VerdictChip.swift
//  Bytewise
//

import SwiftUI

/// A small coloured label for a verdict. Shows nothing when no rule matched.
struct VerdictChip: View {
    let verdict: Verdict

    var body: some View {
        if let color {
            Text(verdict.label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(color)
                .background(color.opacity(0.18), in: Capsule())
        }
    }

    private var color: Color? {
        switch verdict {
        case .safeToClear: .green
        case .review: .orange
        case .keep: .blue
        case .managedByMacOS: .gray
        case .unknown: nil
        }
    }
}
