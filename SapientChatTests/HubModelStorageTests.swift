import Foundation
import Testing
@testable import SapientChat

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
