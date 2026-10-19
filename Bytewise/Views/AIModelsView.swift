//
//  AIModelsView.swift
//  Bytewise
//

import AppKit
import SwiftUI

/// Downloaded AI models found in the scan, largest first, with size, last
/// use and where they came from.
struct AIModelsView: View {
    let models: [AIModel]
    let rules: RulesEngine
    let onShowInMap: (FileNode) -> Void

    private var total: Int64 { models.reduce(0) { $0 + $1.node.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if models.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No AI models found in this folder.")
                        .font(.headline)
                    Text("Bytewise looks for models from Ollama, Hugging Face, LM Studio, GPT4All, PyTorch and Chrome, and for large model files such as .gguf and .safetensors. Scan your home folder to find them all.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Text("\(models.count) \(models.count == 1 ? "model" : "models") · \(Self.format(total))")
                    .font(.headline)
                List(models) { model in
                    row(for: model)
                }
                Text("Last used dates are approximate, because macOS does not always record when a file was opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(for model: AIModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(model.name).bold()
                    Text(model.source)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    VerdictChip(verdict: rules.assess(model.node.url).verdict)
                }
                if !model.contents.isEmpty {
                    Text(model.contents.joined(separator: ", "))
                        .font(.callout)
                }
                Text(model.node.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = model.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Self.format(model.node.size))
                    .monospacedDigit()
                    .bold()
                Text(lastUsedText(model.node.lastUsed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Show in Map") { onShowInMap(model.node) }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([model.node.url])
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help("Show in Finder")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func lastUsedText(_ date: Date?) -> String {
        guard let date else { return "Last used: unknown" }
        return "Last used " + date.formatted(.relative(presentation: .named))
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
