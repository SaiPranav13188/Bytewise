//
//  Theme.swift
//  Bytewise
//

import SwiftUI

extension FileKind {
    /// Map and legend colour. Bright enough that dark labels read on top.
    var color: Color {
        switch self {
        case .folder: Color(red: 0.62, green: 0.66, blue: 0.72)
        case .video: Color(red: 0.96, green: 0.52, blue: 0.45)
        case .audio: Color(red: 0.94, green: 0.55, blue: 0.75)
        case .image: Color(red: 0.66, green: 0.60, blue: 0.97)
        case .archive: Color(red: 0.98, green: 0.76, blue: 0.36)
        case .code: Color(red: 0.58, green: 0.83, blue: 0.47)
        case .document: Color(red: 0.47, green: 0.72, blue: 0.98)
        case .other: Color(red: 0.42, green: 0.80, blue: 0.75)
        }
    }

    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case .archive: "archivebox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .document: "doc.text"
        case .other: "doc"
        }
    }
}

enum Format {
    static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "51.12 GB" split into "51.12" and "GB", to show the unit smaller.
    static func splitBytes(_ bytes: Int64) -> (number: String, unit: String) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = false
        let number = formatter.string(fromByteCount: bytes)
        formatter.includesUnit = true
        formatter.includesCount = false
        return (number, formatter.string(fromByteCount: bytes))
    }

    static func files(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "file" : "files")"
    }

    static func lastUsed(_ date: Date?) -> String {
        guard let date else { return "Last use unknown" }
        return "Used " + date.formatted(.relative(presentation: .named))
    }
}

/// A size with the unit in smaller, lighter type.
struct SizeText: View {
    let bytes: Int64
    var size: CGFloat = 13

    var body: some View {
        let parts = Format.splitBytes(bytes)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts.number)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
            Text(parts.unit)
                .font(.system(size: size * 0.7, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// Rounded panel used for every section of the main window.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

/// A thin bar showing an item's share of its folder.
struct ShareBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

/// A rounded square with a white symbol, used for places and list rows.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}
