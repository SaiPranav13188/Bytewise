//
//  AIModelFinderTests.swift
//  BytewiseTests
//

import Foundation
import Testing
@testable import Bytewise

/// Builds an in-memory tree from paths and sizes, so no files are needed.
private func tree(_ root: String, _ files: [(String, Int64)]) -> FileNode {
    let rootNode = FileNode(url: URL(fileURLWithPath: root), isDirectory: true, kind: .folder)
    var folders = [root: rootNode]
    for (path, size) in files {
        var parent = rootNode
        var current = root
        let parts = path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() {
            current += "/" + part
            if index == parts.count - 1 {
                parent.addChild(FileNode(url: URL(fileURLWithPath: current), isDirectory: false,
                                         kind: .other, size: size))
            } else if let folder = folders[current] {
                parent = folder
            } else {
                let folder = FileNode(url: URL(fileURLWithPath: current), isDirectory: true, kind: .folder)
                parent.addChild(folder)
                folders[current] = folder
                parent = folder
            }
        }
    }
    rootNode.rollUpSizes()
    return rootNode
}

struct AIModelFinderTests {
    private let home = "/Users/test"
    private let gigabyte: Int64 = 1_000_000_000

    @Test func findsModelsFromKnownTools() {
        let root = tree(home, [
            (".ollama/models/manifests/registry.ollama.ai/library/llama3/latest", 1_000),
            (".ollama/models/manifests/registry.ollama.ai/library/mistral/7b", 1_000),
            (".ollama/models/blobs/sha256-aaa", 4 * gigabyte),
            (".cache/huggingface/hub/models--openai--whisper-small/blobs/x", 900_000_000),
            (".lmstudio/models/lmstudio-community/Qwen-7B-GGUF/qwen.gguf", 3 * gigabyte),
            ("Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/2025.1/weights.bin", 4 * gigabyte),
            ("Library/Application Support/nomic.ai/GPT4All/orca.gguf", 2 * gigabyte),
            (".cache/torch/hub/checkpoints/resnet50.pth", 100_000_000),
        ])

        let models = AIModelFinder.find(in: root, home: home)
        let byName = Dictionary(uniqueKeysWithValues: models.map { ($0.name, $0) })

        #expect(byName["Ollama models"]?.source == "Ollama")
        #expect(byName["Ollama models"]?.contents == ["llama3:latest", "mistral:7b"])
        #expect(byName["openai/whisper-small"]?.source == "Hugging Face")
        #expect(byName["lmstudio-community/Qwen-7B-GGUF"]?.source == "LM Studio")
        #expect(byName["Chrome on-device AI model"]?.source == "Google Chrome")
        #expect(byName["orca.gguf"]?.source == "GPT4All")
        #expect(byName["resnet50.pth"]?.source == "PyTorch")
        #expect(models.count == 6)
    }

    @Test func modelsAreSortedLargestFirst() {
        let root = tree(home, [
            ("a/small.gguf", 100_000_000),
            ("b/big.gguf", 5 * gigabyte),
            ("c/mid.safetensors", gigabyte),
        ])
        #expect(AIModelFinder.find(in: root, home: home).map(\.name) == ["big.gguf", "mid.safetensors", "small.gguf"])
    }

    @Test func smallFilesWithModelExtensionsAreIgnored() {
        let root = tree(home, [("project/tiny.onnx", 2_000_000), ("project/real.onnx", 200_000_000)])
        #expect(AIModelFinder.find(in: root, home: home).map(\.name) == ["real.onnx"])
    }

    @Test func filesInsideAKnownModelAreNotListedAgain() {
        let root = tree(home, [(".lmstudio/models/pub/model/weights.gguf", 3 * gigabyte)])
        let models = AIModelFinder.find(in: root, home: home)
        #expect(models.map(\.name) == ["pub/model"])
    }

    @Test func ollamaNamesFromOtherRegistriesKeepTheirPrefix() {
        let root = tree(home, [
            (".ollama/models/manifests/hf.co/bartowski/Llama-GGUF/Q4", 1_000),
            (".ollama/models/blobs/sha256-b", gigabyte),
        ])
        let ollama = AIModelFinder.find(in: root, home: home).first
        #expect(ollama?.contents == ["hf.co/bartowski/Llama-GGUF:Q4"])
    }

    @Test func modelLocationsGetModelReasonsNotGenericOnes() {
        let rules = RulesEngine(home: home)
        let chrome = rules.assess(URL(fileURLWithPath: "\(home)/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"))
        #expect(chrome.verdict == .review)
        #expect(chrome.reason?.contains("Chrome") == true)
        #expect(rules.assess(URL(fileURLWithPath: "\(home)/.ollama/models")).reason?.contains("ollama rm") == true)
        #expect(rules.assess(URL(fileURLWithPath: "\(home)/.cache/huggingface/hub")).verdict == .review)
        #expect(rules.assess(URL(fileURLWithPath: "\(home)/.lmstudio/models/a/b")).verdict == .review)
    }

    @Test func modelsInsideProtectedFoldersStayProtected() {
        let rules = RulesEngine(home: home)
        #expect(rules.assess(URL(fileURLWithPath: "\(home)/Documents/models/llama.gguf")).verdict == .keep)
    }
}

struct FriendlyErrorTests {
    @Test func permissionErrorsExplainWhatToDo() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        #expect(FriendlyError.message(for: error).contains("Choose Folder"))
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        #expect(FriendlyError.message(for: posix).contains("Full Disk Access"))
    }

    @Test func missingFilesSaySo() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        #expect(FriendlyError.message(for: error).contains("no longer there"))
    }

    @Test func otherErrorsFallBackToTheSystemMessage() {
        let error = NSError(domain: "Example", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something odd"])
        #expect(FriendlyError.message(for: error) == "Something odd")
    }
}
