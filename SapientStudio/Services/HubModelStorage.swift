// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// `ModelStorageService` over the Hugging Face cache layout SAPIENT downloads
/// into: `<root>/hub/models--{org}--{name}/{blobs,snapshots,refs}`.
/// Sizes are summed over `blobs/` only, since `snapshots/` holds symlinks
/// to the same files.
nonisolated struct HubModelStorage: ModelStorageService {
    /// The directory passed to SAPIENT's `setCacheDir` (its `HF_HOME`).
    let root: URL

    static let appDefault = HubModelStorage(root: .cachesDirectory.appending(path: "sapient"))

    private var hub: URL { root.appending(path: "hub") }

    func folder(forRepo repoId: String) -> URL {
        hub.appending(path: "models--" + repoId.replacing("/", with: "--"))
    }

    func download(forRepo repoId: String) -> ModelDownload {
        let repo = folder(forRepo: repoId)
        let blobs = repo.appending(path: "blobs")
        let bytes = Self.size(of: blobs)
        guard bytes > 0 else { return .notDownloaded }
        // hf-hub writes in-flight files as `*.part` (`.sync.part` from the
        // async client) and renames them when complete.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: blobs.path(percentEncoded: false))) ?? []
        if names.contains(where: { $0.hasSuffix(".part") }) { return .partial(bytes: bytes) }
        // Small files (config, tokenizer) finish first while the weights are
        // still being written elsewhere: only the weights make it complete.
        return Self.hasCompleteWeights(in: repo.appending(path: "snapshots")) ? .downloaded(bytes: bytes) : .partial(bytes: bytes)
    }

    /// The snapshot holds a GGUF, or safetensors with every shard its index
    /// lists, or a single safetensors/bin file. A snapshot entry appears
    /// only once its file is complete.
    static func hasCompleteWeights(in snapshots: URL) -> Bool {
        let manager = FileManager.default
        guard let entries = manager.enumerator(at: snapshots, includingPropertiesForKeys: nil) else { return false }
        var files: [String: URL] = [:]
        for case let url as URL in entries where manager.fileExists(atPath: url.path(percentEncoded: false)) {
            files[url.lastPathComponent] = url
        }
        if files.keys.contains(where: { $0.hasSuffix(".gguf") }) { return true }
        if let index = files.first(where: { $0.key.hasSuffix(".safetensors.index.json") })?.value {
            guard let data = try? Data(contentsOf: index),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let map = json["weight_map"] as? [String: String]
            else { return false }
            return Set(map.values).allSatisfy { files[$0] != nil }
        }
        return files.keys.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".bin") }
    }

    func deleteDownload(forRepo repoId: String) throws {
        let folder = folder(forRepo: repoId)
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    func deleteAllDownloads() throws {
        guard FileManager.default.fileExists(atPath: hub.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: hub)
    }

    func totalDownloadBytes() -> UInt64 {
        let repos = (try? FileManager.default.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil)) ?? []
        return repos.reduce(0) { $0 + Self.size(of: $1.appending(path: "blobs")) }
    }

    /// Total size of the regular files under `directory`.
    private static func size(of directory: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }
        var total: UInt64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
    }
}
