import Foundation
#if canImport(UIKit)
import UIKit
#endif

// NSLock supports the framework's iOS 15 deployment target. Every access to
// entries, totalCost, and accessCounter is protected by lock; no critical section
// suspends or calls client code. Resources are immutable, checked-Sendable values.
final class DecodedImageCache: @unchecked Sendable {
    private struct Entry {
        let resource: FaceAwareImageResource
        let cost: Int
        var lastAccess: UInt64
    }

    private let capacity: Int
    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private var memoryWarningObserver: NSObjectProtocol?
    private var entries: [ResourceKey: Entry] = [:]
    private var totalCost = 0
    private var accessCounter: UInt64 = 0

    init(
        capacity: Int,
        notificationCenter: NotificationCenter = .default,
        memoryWarningNotification: Notification.Name? = nil
    ) {
        self.capacity = max(0, capacity)
        self.notificationCenter = notificationCenter
        // Pick the notification name. On UIKit platforms the default is the
        // system memory warning; on other platforms the caller must opt in by
        // supplying a custom name (or pass `nil` explicitly to skip listening).
        let resolvedName: Notification.Name?
        if let memoryWarningNotification {
            resolvedName = memoryWarningNotification
        } else {
            #if canImport(UIKit)
            resolvedName = UIApplication.didReceiveMemoryWarningNotification
            #else
            resolvedName = nil
            #endif
        }
        if let resolvedName {
            // The block captures self weakly, so the registration cannot keep the cache
            // alive; holding the token lets deinit unregister it deterministically.
            let observer = notificationCenter.addObserver(
                forName: resolvedName,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.removeAll()
            }
            memoryWarningObserver = observer
        }
    }

    deinit {
        if let memoryWarningObserver {
            notificationCenter.removeObserver(memoryWarningObserver)
        }
    }

    func value(for key: ResourceKey) -> FaceAwareImageResource? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else {
            return nil
        }

        entry.lastAccess = nextAccess()
        entries[key] = entry
        return entry.resource
    }

    func insert(_ resource: FaceAwareImageResource, for key: ResourceKey) {
        lock.lock()
        defer { lock.unlock() }
        guard capacity > 0 else {
            return
        }

        if let existing = entries.removeValue(forKey: key) {
            totalCost -= existing.cost
        }

        let entry = Entry(
            resource: resource,
            cost: resource.image.bytesPerRow * resource.image.height,
            lastAccess: nextAccess()
        )
        entries[key] = entry
        totalCost += entry.cost
        evictIfNeeded()
    }

    func removeAll(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let normalizedURL = ResourceKey.normalizedURL(url)
        let matchingKeys = entries.keys.filter { $0.url == normalizedURL }

        for key in matchingKeys {
            guard let removedEntry = entries.removeValue(forKey: key) else {
                continue
            }
            totalCost -= removedEntry.cost
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        totalCost = 0
    }

    // Called only while lock is held.
    private func nextAccess() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }

    // Called only while lock is held.
    private func evictIfNeeded() {
        while totalCost > capacity, let leastRecentlyUsedKey = entries.min(by: {
            $0.value.lastAccess < $1.value.lastAccess
        })?.key, let removedEntry = entries.removeValue(forKey: leastRecentlyUsedKey) {
            totalCost -= removedEntry.cost
        }
    }
}
