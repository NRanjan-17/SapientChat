// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Testing
@testable import SapientStudio

struct HubModelStorageTests {
    /// Builds `<root>/hub/models--org--name/{blobs/<file>, snapshots/main/<link>}`.
    private func makeCache(blobBytes: Int) throws -> (HubModelStorage, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "hub-test-\(UUID().uuidString)")
        let repo = root.appending(path: "hub/models--org--name")
        let blobs = repo.appending(path: "blobs")
        let snapshot = repo.appending(path: "snapshots/main")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        let blob = blobs.appending(path: "abc123")
        try Data(count: blobBytes).write(to: blob)
        // The snapshot entry is a symlink to the blob, as in the real cache.
        try FileManager.default.createSymbolicLink(at: snapshot.appending(path: "model.gguf"), withDestinationURL: blob)
        return (HubModelStorage(root: root), root)
    }

    @Test func sizesCountBlobsOnceNotTheirSymlinks() throws {
        let (storage, root) = try makeCache(blobBytes: 4_096)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(storage.download(forRepo: "org/name") == .downloaded(bytes: 4_096))
        #expect(storage.download(forRepo: "org/other") == .notDownloaded)
        #expect(storage.totalDownloadBytes() == 4_096)
    }

    @Test func deletesOneModel() throws {
        let (storage, root) = try makeCache(blobBytes: 10)
        defer { try? FileManager.default.removeItem(at: root) }
        try storage.deleteDownload(forRepo: "org/name")
        #expect(storage.download(forRepo: "org/name") == .notDownloaded)
        // Deleting something that isn't there is not an error.
        try storage.deleteDownload(forRepo: "org/name")
    }

    @Test func deletesEverything() throws {
        let (storage, root) = try makeCache(blobBytes: 10)
        defer { try? FileManager.default.removeItem(at: root) }
        try storage.deleteAllDownloads()
        #expect(storage.totalDownloadBytes() == 0)
    }
}

/// Small files land before the weights: that's not a finished download.
struct HubModelStorageCompletenessTests {
    private func repo(_ files: [String: Data]) throws -> (HubModelStorage, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "hub-test-\(UUID().uuidString)")
        let repo = root.appending(path: "hub/models--org--name")
        let blobs = repo.appending(path: "blobs")
        let snapshot = repo.appending(path: "snapshots/main")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        for (name, data) in files {
            let blob = blobs.appending(path: UUID().uuidString)
            try data.write(to: blob)
            try FileManager.default.createSymbolicLink(at: snapshot.appending(path: name), withDestinationURL: blob)
        }
        return (HubModelStorage(root: root), root)
    }

    @Test func configAndTokenizerAloneArePartial() throws {
        let (storage, root) = try repo(["config.json": Data(count: 1_000), "tokenizer.json": Data(count: 1_000_000)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(storage.download(forRepo: "org/name") == .partial(bytes: 1_001_000))
    }

    @Test func shardedSafetensorsNeedEveryShard() throws {
        let index = Data(#"{"weight_map":{"a":"model-00001-of-00002.safetensors","b":"model-00002-of-00002.safetensors"}}"#.utf8)
        let (storage, root) = try repo([
            "config.json": Data(count: 10), "model.safetensors.index.json": index,
            "model-00001-of-00002.safetensors": Data(count: 100),
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!storage.download(forRepo: "org/name").isDownloaded, "shard 2 is missing")
        let snapshot = root.appending(path: "hub/models--org--name/snapshots/main")
        try Data(count: 100).write(to: snapshot.appending(path: "model-00002-of-00002.safetensors"))
        #expect(storage.download(forRepo: "org/name").isDownloaded)
    }

    @Test func aSingleWeightsFileIsComplete() throws {
        let (storage, root) = try repo(["config.json": Data(count: 10), "model.safetensors": Data(count: 100)])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(storage.download(forRepo: "org/name").isDownloaded)
    }
}
