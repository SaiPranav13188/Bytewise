//
//  AIModelFinder.swift
//  Bytewise
//

import Foundation

/// A downloaded AI model, or a folder of them, found in a scan.
nonisolated struct AIModel: Identifiable, Sendable {
    let node: FileNode
    let name: String
    /// The app or tool that downloaded it, e.g. "Ollama".
    let source: String
    /// Model names inside, when one folder holds several (Ollama).
    let contents: [String]
    let note: String?

    var id: ObjectIdentifier { ObjectIdentifier(node) }
}

/// Finds AI models in a scanned tree by where common tools keep them, plus
/// any large model file elsewhere. Works only from names and sizes, so it
/// never opens a file.
nonisolated enum AIModelFinder {
    /// Extensions used by model files.
    static let modelExtensions: Set<String> = ["gguf", "ggml", "safetensors", "onnx", "pt", "pth", "ckpt", "mlmodel"]
    /// Smaller files with those extensions are left out, since small `.pt`
    /// or `.onnx` files are often not models people think of.
    static let minimumLooseFileSize: Int64 = 50 * 1024 * 1024

    static func find(in root: FileNode, home: String = RulesEngine.realHomePath) -> [AIModel] {
        var models: [AIModel] = []
        visit(root, home: home, into: &models)
        return models.sorted { $0.node.size > $1.node.size }
    }

    private static func visit(_ node: FileNode, home: String, into models: inout [AIModel]) {
        if let model = match(node, home: home) {
            // Do not look inside a match, so its files are not listed twice.
            if model.node.size > 0 { models.append(model) }
            return
        }
        for child in node.children {
            visit(child, home: home, into: &models)
        }
    }

    private static func match(_ node: FileNode, home: String) -> AIModel? {
        let path = node.url.path
        let parent = node.url.deletingLastPathComponent().path
        let grandparent = node.url.deletingLastPathComponent().deletingLastPathComponent().path
        let name = node.name

        if path == home + "/.ollama/models" {
            return AIModel(node: node, name: "Ollama models", source: "Ollama",
                           contents: ollamaModelNames(in: node),
                           note: "Remove models with ollama rm <name> so Ollama stays consistent.")
        }
        if node.isDirectory, parent == home + "/.cache/huggingface/hub", name.hasPrefix("models--") {
            let modelName = name.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
            return AIModel(node: node, name: modelName, source: "Hugging Face", contents: [],
                           note: "Downloaded again the next time a project uses it.")
        }
        if node.isDirectory,
           grandparent == home + "/.lmstudio/models" || grandparent == home + "/.cache/lm-studio/models" {
            let publisher = node.url.deletingLastPathComponent().lastPathComponent
            return AIModel(node: node, name: "\(publisher)/\(name)", source: "LM Studio", contents: [],
                           note: "Can be downloaded again from LM Studio.")
        }
        if node.isDirectory, name == "OptGuideOnDeviceModel",
           path.hasPrefix(home + "/Library/Application Support/Google/") {
            return AIModel(node: node, name: "Chrome on-device AI model", source: "Google Chrome", contents: [],
                           note: "Used by Chrome's built-in AI features. Chrome downloads it again while those features are on.")
        }
        if !node.isDirectory, parent == home + "/Library/Application Support/nomic.ai/GPT4All",
           ["gguf", "bin"].contains(node.url.pathExtension.lowercased()) {
            return AIModel(node: node, name: name, source: "GPT4All", contents: [],
                           note: "Can be downloaded again from GPT4All.")
        }
        if !node.isDirectory, parent == home + "/.cache/torch/hub/checkpoints" {
            return AIModel(node: node, name: name, source: "PyTorch", contents: [],
                           note: "Downloaded again the next time a project loads it.")
        }
        if !node.isDirectory, node.size >= minimumLooseFileSize,
           modelExtensions.contains(node.url.pathExtension.lowercased()) {
            return AIModel(node: node, name: name, source: "Model file", contents: [], note: nil)
        }
        return nil
    }

    /// Ollama keeps one small file per model at
    /// manifests/<registry>/<namespace>/<model>/<tag>. The names come from
    /// those paths, so the files themselves are never opened.
    static func ollamaModelNames(in models: FileNode) -> [String] {
        guard let manifests = models.children.first(where: { $0.name == "manifests" }) else { return [] }
        var names: [String] = []
        func walk(_ node: FileNode, _ parts: [String]) {
            if node.isDirectory {
                for child in node.children { walk(child, parts + [child.name]) }
                return
            }
            // parts: registry, namespace, model, tag
            guard parts.count >= 4 else { return }
            let tag = parts[parts.count - 1]
            let model = parts[parts.count - 2]
            let prefix = parts[0] == "registry.ollama.ai" && parts[1] == "library"
                ? "" : parts[0..<(parts.count - 2)].joined(separator: "/") + "/"
            names.append("\(prefix)\(model):\(tag)")
        }
        walk(manifests, [])
        return names.sorted()
    }
}
