import Foundation

/// Owns the on-disk directory tree of the framework's HTTP response caches.
///
/// Every pipeline builds its `URLCache` over a directory of its own under the app's
/// caches directory, so `clearDiskCache()` and `removeCachedResource(for:)` can only
/// ever reach the cache of the client that owns them. Foundation's
/// `URLCache(memoryCapacity:diskCapacity:directory:)` documents `directory: nil` as the
/// process-wide default directory, which every client — and the host app's own
/// `URLCache.shared` — would otherwise share.
///
/// A directory per pipeline would orphan one directory per process launch, so creation
/// also sweeps sibling directories this process did not create: leftovers from earlier
/// launches. The sweep never touches anything outside the framework's own root.
enum HTTPCacheDirectory {
    /// The directory that holds every HTTP cache directory this process created.
    private static let createdLock = NSLock()
    nonisolated(unsafe) private static var createdDirectories: Set<URL> = []

    private static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FaceAwareImageKit/HTTPCache", isDirectory: true)
    }

    /// Records `directory` as created by this process.
    static func noteCreated(_ directory: URL) {
        _ = createdLock.withLock { createdDirectories.insert(directory.standardizedFileURL) }
    }

    /// Reports whether this process created `directory`.
    static func didCreate(_ directory: URL) -> Bool {
        createdLock.withLock { createdDirectories.contains(directory.standardizedFileURL) }
    }

    /// Creates and returns a directory of this process under `root`, after removing the
    /// sibling directories of any earlier launch.
    ///
    /// The work is synchronous and happens once, at pipeline construction. A failure to
    /// create the directory is answered with `nil`, which leaves `URLCache` on the
    /// process-wide default rather than failing the client.
    static func create(under root: URL) -> URL? {
        let manager = FileManager.default
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        noteCreated(directory)
        sweep(under: root)
        return directory
    }

    /// Removes the framework's own stale siblings under `root`, keeping every directory
    /// this process created. The root itself survives, so a sweep cannot cascade.
    static func sweep(under root: URL) {
        let manager = FileManager.default
        let children = (try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        for child in children where isDirectory(child, manager: manager) && !didCreate(child) {
            try? manager.removeItem(at: child)
        }
    }

    /// Removes the directory of a released pipeline. Best-effort: an open `URLCache`
    /// may still hold files here, and the next launch's sweep is the backstop.
    static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The root the framework uses when the caller does not inject one.
    static var defaultRoot: URL { root }

    private static func isDirectory(_ url: URL, manager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
