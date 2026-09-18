import CoreGraphics
import Foundation
import XCTest
@testable import FaceAwareImageKit

final class DecodedImageCacheTests: XCTestCase {
    func testCacheEvictsLeastRecentlyUsedResourceAfterRead() async throws {
        let first = try makeResource()
        let second = try makeResource()
        let third = try makeResource()
        let cache = DecodedImageCache(capacity: 2 * cost(of: first.image))
        let configuration = FaceAwareImageConfiguration()
        let firstKey = ResourceKey(url: URL(string: "https://example.com/first.png")!, configuration: configuration)
        let secondKey = ResourceKey(url: URL(string: "https://example.com/second.png")!, configuration: configuration)
        let thirdKey = ResourceKey(url: URL(string: "https://example.com/third.png")!, configuration: configuration)

        cache.insert(first, for: firstKey)
        cache.insert(second, for: secondKey)
        let recentlyRead = cache.value(for: firstKey)
        cache.insert(third, for: thirdKey)
        let retainedFirst = cache.value(for: firstKey)
        let evictedSecond = cache.value(for: secondKey)
        let retainedThird = cache.value(for: thirdKey)

        XCTAssertTrue(recentlyRead?.image === first.image)
        XCTAssertTrue(retainedFirst?.image === first.image)
        XCTAssertNil(evictedSecond)
        XCTAssertTrue(retainedThird?.image === third.image)
    }

    func testRemoveAllForURLRemovesEveryConfigurationVariantOnlyForThatURL() async throws {
        let cache = DecodedImageCache(capacity: .max)
        let url = URL(string: "https://example.com/portrait.png")!
        let firstKey = ResourceKey(url: url, configuration: FaceAwareImageConfiguration(displayMaxPixelSize: 400))
        let secondKey = ResourceKey(url: url, configuration: FaceAwareImageConfiguration(analysisFailurePolicy: .failRequest))
        let otherKey = ResourceKey(
            url: URL(string: "https://example.com/other.png")!,
            configuration: FaceAwareImageConfiguration()
        )

        cache.insert(try makeResource(), for: firstKey)
        cache.insert(try makeResource(), for: secondKey)
        cache.insert(try makeResource(), for: otherKey)
        cache.removeAll(for: url)
        let removedFirst = cache.value(for: firstKey)
        let removedSecond = cache.value(for: secondKey)
        let retainedOther = cache.value(for: otherKey)

        XCTAssertNil(removedFirst)
        XCTAssertNil(removedSecond)
        XCTAssertNotNil(retainedOther)
    }

    func testZeroCapacityRetainsNoResources() async throws {
        let cache = DecodedImageCache(capacity: 0)
        let key = ResourceKey(url: URL(string: "https://example.com/portrait.png")!, configuration: FaceAwareImageConfiguration())

        cache.insert(try makeResource(), for: key)
        let value = cache.value(for: key)

        XCTAssertNil(value)
    }

    func testMemoryWarningNotificationClearsCache() async throws {
        let notificationCenter = NotificationCenter()
        let notification = Notification.Name("DecodedImageCacheTests.memoryWarning")
        let cache = DecodedImageCache(
            capacity: .max,
            notificationCenter: notificationCenter,
            memoryWarningNotification: notification
        )
        let key = ResourceKey(url: URL(string: "https://example.com/portrait.png")!, configuration: FaceAwareImageConfiguration())

        cache.insert(try makeResource(), for: key)
        notificationCenter.post(name: notification, object: nil)

        XCTAssertNil(cache.value(for: key))
    }

    func testConcurrentAccessAndClearLeaveCacheReusable() async throws {
        let resource = try makeResource()
        let cache = DecodedImageCache(capacity: cost(of: resource.image))
        let keys = (0..<8).map {
            ResourceKey(url: URL(string: "https://example.com/\($0).png")!, configuration: .default)
        }
        await withTaskGroup(of: Void.self) { group in
            for worker in 0..<32 {
                group.addTask {
                    for iteration in 0..<64 {
                        let key = keys[(worker + iteration) % keys.count]
                        cache.insert(resource, for: key)
                        _ = cache.value(for: key)
                        if iteration.isMultiple(of: 2) {
                            cache.removeAll()
                        } else {
                            cache.removeAll(for: key.url)
                        }
                    }
                }
            }
        }
        cache.removeAll()
        for key in keys { XCTAssertNil(cache.value(for: key)) }

        cache.insert(resource, for: keys[0])
        cache.insert(resource, for: keys[1])
        XCTAssertNil(cache.value(for: keys[0]))
        XCTAssertTrue(cache.value(for: keys[1])?.image === resource.image)
    }

    func testDeinitUnregistersTheMemoryWarningObserver() throws {
        let center = RecordingNotificationCenter()
        let notification = Notification.Name("DecodedImageCacheTests.deinit")
        weak var weakCache: DecodedImageCache?
        var observed = false
        autoreleasepool {
            let cache = DecodedImageCache(
                capacity: .max,
                notificationCenter: center,
                memoryWarningNotification: notification
            )
            weakCache = cache
            observed = weakCache != nil
            XCTAssertEqual(center.addedObservers, 1)
            XCTAssertEqual(center.removedObservers, 0, "The token must stay registered for the cache's lifetime")
        }

        guard observed else {
            return XCTFail("The weak reference was not set; the test cannot observe release")
        }
        XCTAssertNil(weakCache, "The cache must be released once its test scope ends")
        XCTAssertEqual(center.removedObservers, 1, "deinit must unregister the memory-warning observer")
    }

    private func makeResource() throws -> FaceAwareImageResource {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let image = context.makeImage() else {
            throw CacheTestError.imageCreationFailed
        }

        return FaceAwareImageResource(
            image: image,
            pixelSize: CGSize(width: image.width, height: image.height),
            analysis: FaceAwareImageAnalysis(
                focalPoint: CGPoint(x: 0.5, y: 0.5),
                focusSource: .imageCenter,
                faceCount: 0,
                salientObjectCount: 0
            )
        )
    }

    private func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}

private enum CacheTestError: Error {
    case imageCreationFailed
}

/// Counts the observer registrations a `DecodedImageCache` makes and removes, so a test
/// can see that `deinit` unregisters its token.
///
/// `nonisolated` for the same reason the framework's own caches are: the enclosing test
/// class is main-actor isolated, and an isolated override of a nonisolated
/// `NotificationCenter` method would be a strict-concurrency warning.
private nonisolated final class RecordingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var added = 0
    private var removed = 0

    var addedObservers: Int { lock.withLock { added } }
    var removedObservers: Int { lock.withLock { removed } }

    override func addObserver(
        forName name: NSNotification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        lock.withLock { added += 1 }
        return super.addObserver(forName: name, object: obj, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        lock.withLock { removed += 1 }
        super.removeObserver(observer)
    }
}
