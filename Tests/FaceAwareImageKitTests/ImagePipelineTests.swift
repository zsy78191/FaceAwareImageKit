import CoreGraphics
import Foundation
import XCTest
@testable import FaceAwareImageKit

@MainActor
final class ImagePipelineTests: XCTestCase {
    private struct EmptyVision: VisionRequestRunning {
        nonisolated func faceRegions(in image: CGImage) throws -> [CGRect] { [] }
        nonisolated func salientRegions(in image: CGImage) throws -> [CGRect] { [] }
    }

    private func fixture(ignoresCancellation: Bool = false,
                         storeBarrier: HTTPStoreBarrier? = nil,
                         successBarrier: PipelineSuccessBarrier? = nil) -> Fixture {
        let url = URL(string: "https://\(UUID().uuidString).example/image.png")!
        let control = MockURLProtocol.Control()
        MockURLProtocol.register(control, for: url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let httpCache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0)
        configuration.urlCache = httpCache
        let session = URLSession(configuration: configuration)
        let cache = DecodedImageCache(capacity: .max)
        let transport: ImagePipeline.Transport?
        if ignoresCancellation {
            transport = { request in
                // URLSession itself respects cancellation. This deliberately independent
                // transport delivers a REAL late success to the cancelled pipeline worker.
                let operation = Task.detached { try await session.data(for: request) }
                return try await operation.value
            }
        } else {
            transport = nil
        }
        let pipeline = ImagePipeline(
            configuration: .default, session: session, decodedCache: cache,
            analyzer: VisionAnalyzer(requestRunner: EmptyVision()),
            transport: transport,
            cacheDecorator: { cache in
                if let storeBarrier { return DelayedHTTPStoreCache(backing: cache, barrier: storeBarrier) }
                return cache
            },
            beforeFinish: { _ in await successBarrier?.pause() }
        )
        addTeardownBlock {
            session.invalidateAndCancel()
            MockURLProtocol.unregister(url)
        }
        return Fixture(url: url, control: control, pipeline: pipeline, cache: cache, httpCache: httpCache)
    }

    private struct Fixture {
        let url: URL
        let control: MockURLProtocol.Control
        let pipeline: ImagePipeline
        let cache: DecodedImageCache
        let httpCache: URLCache
        var key: ResourceKey { ResourceKey(url: url, configuration: .default) }
    }

    // Predicate barriers observe registration, never assume scheduling after a yield.
    private func waitForWaiters(_ count: Int, in fixture: Fixture) async {
        while await fixture.pipeline.inFlight[fixture.key]?.waiterIDs.count != count {
            await Task.yield()
        }
    }

    private func assertCancelled(_ task: Task<FaceAwareImageResource, Error>,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await task.value
            XCTFail("Expected cancellation", file: file, line: line)
        } catch FaceAwareImageError.cancelled {
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func testConcurrentLoadsDeduplicateAndCompletedLoadHitsMemory() async throws {
        let f = fixture()
        let first = Task { try await f.pipeline.load(url: f.url) }
        let second = Task { try await f.pipeline.load(url: URL(string: f.url.absoluteString + "#view")!) }
        await waitForWaiters(2, in: f)
        await f.control.waitForRequests(1)
        XCTAssertEqual(f.control.requestCount, 1)
        f.control.complete(data: try GeneratedImageFixture.makePNGData(width: 16, height: 8))
        let a = try await first.value
        let b = try await second.value
        let cached = try await f.pipeline.load(url: f.url)
        XCTAssertTrue(a.image === b.image)
        XCTAssertTrue(a.image === cached.image)
        XCTAssertEqual(cached.pixelSize, CGSize(width: 16, height: 8))
        XCTAssertEqual(f.control.requestCount, 1)
        let remaining = await f.pipeline.inFlight.count
        XCTAssertEqual(remaining, 0)
    }

    func testNonSuccessStatusIsMappedAndFailedEntryCanRetry() async throws {
        let f = fixture()
        let first = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(1)
        f.control.complete(status: 503)
        do {
            _ = try await first.value
            XCTFail("Expected HTTP failure")
        } catch FaceAwareImageError.unacceptableStatusCode(503) {} catch { XCTFail("\(error)") }
        let retry = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(2)
        f.control.complete(1, data: try GeneratedImageFixture.makePNGData(width: 16, height: 8))
        _ = try await retry.value
    }

    func testTransportErrorIsMapped() async {
        let f = fixture()
        let task = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(1)
        f.control.complete(error: URLError(.notConnectedToInternet))
        do {
            _ = try await task.value
            XCTFail("Expected network failure")
        } catch FaceAwareImageError.network(let description) {
            XCTAssertFalse(description.isEmpty)
        } catch { XCTFail("\(error)") }
    }

    func testInvalidSchemeCreatesNoWork() async {
        let f = fixture()
        for url in [URL(fileURLWithPath: "/image.png"), URL(string: "ftp://example.com/image.png")!] {
            do {
                _ = try await f.pipeline.load(url: url)
                XCTFail("Expected invalid URL")
            } catch FaceAwareImageError.invalidURL {} catch { XCTFail("\(error)") }
        }
        XCTAssertEqual(f.control.requestCount, 0)
        let entries = await f.pipeline.inFlight.count
        XCTAssertEqual(entries, 0)
    }

    func testCancellingOneWaiterReturnsPromptlyAndPreservesOtherWaiter() async throws {
        let f = fixture()
        let first = Task { try await f.pipeline.load(url: f.url) }
        let second = Task { try await f.pipeline.load(url: f.url) }
        await waitForWaiters(2, in: f)
        await f.control.waitForRequests(1)
        first.cancel()
        await assertCancelled(first) // Must finish while transport is still suspended.
        await waitForWaiters(1, in: f)
        XCTAssertEqual(f.control.cancellationCount, 0)
        f.control.complete(data: try GeneratedImageFixture.makePNGData(width: 16, height: 8))
        let result = try await second.value
        XCTAssertEqual(result.pixelSize.width, 16)
        XCTAssertEqual(f.control.requestCount, 1)
    }

    func testCancellingLastWaiterCancelsUnderlyingRequest() async {
        let f = fixture()
        let first = Task { try await f.pipeline.load(url: f.url) }
        let second = Task { try await f.pipeline.load(url: f.url) }
        await waitForWaiters(2, in: f)
        await f.control.waitForRequests(1)
        first.cancel()
        second.cancel()
        await assertCancelled(first)
        await assertCancelled(second)
        await f.control.waitForCancellations(1)
        let entries = await f.pipeline.inFlight.count
        XCTAssertEqual(entries, 0)
        let cached = f.cache.value(for: f.key)
        XCTAssertNil(cached)
    }

    func testRemovalCancelsSuspendedRequest() async {
        let f = fixture()
        let task = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(1)
        await f.pipeline.removeCachedResource(for: URL(string: f.url.absoluteString + "#ignored")!)
        await assertCancelled(task)
        await f.control.waitForCancellations(1)
        let entries = await f.pipeline.inFlight.count
        XCTAssertEqual(entries, 0)
    }

    func testStaleSuccessAfterRemovalCannotWriteOrRemoveReplacementEntry() async throws {
        let f = fixture(ignoresCancellation: true)
        let stale = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(1)
        let oldWorkerValue = await f.pipeline.inFlight[f.key]?.task
        let oldWorker = try XCTUnwrap(oldWorkerValue)
        await f.pipeline.removeCachedResource(for: f.url)
        await assertCancelled(stale)
        let replacement = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(2)
        f.control.complete(data: try GeneratedImageFixture.makePNGData(width: 32, height: 8))
        _ = await oldWorker.result // Fence the late worker's actual writeback attempt.
        let staleCache = f.cache.value(for: f.key)
        XCTAssertNil(staleCache)
        let waiters = await f.pipeline.inFlight[f.key]?.waiterIDs.count
        XCTAssertEqual(waiters, 1)
        f.control.complete(1, data: try GeneratedImageFixture.makePNGData(width: 16, height: 8))
        let result = try await replacement.value
        XCTAssertEqual(result.pixelSize.width, 16)
        let cached = try await f.pipeline.load(url: f.url)
        XCTAssertTrue(cached.image === result.image)
        XCTAssertEqual(f.control.requestCount, 2)
    }

    func testLateCancelledWorkerCannotOverwriteCompletedReplacement() async throws {
        let f = fixture(ignoresCancellation: true)
        let stale = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(1)
        let workerValue = await f.pipeline.inFlight[f.key]?.task
        let worker = try XCTUnwrap(workerValue)
        stale.cancel()
        await assertCancelled(stale)
        let replacement = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(2)
        f.control.complete(1, data: try GeneratedImageFixture.makePNGData(width: 16, height: 8))
        let fresh = try await replacement.value
        f.control.complete(data: try GeneratedImageFixture.makePNGData(width: 32, height: 8))
        _ = await worker.result
        let cached = try await f.pipeline.load(url: f.url)
        XCTAssertTrue(cached.image === fresh.image)
    }

    func testRemovalClearsAllDecodedVariantsAndCanonicalHTTPResponseOnlyForURL() async throws {
        let f = fixture()
        let resource = try await f.pipeline.analyze(data: GeneratedImageFixture.makePNGData(width: 16, height: 8))
        let variant = ResourceKey(url: f.url, configuration: .init(displayMaxPixelSize: 8))
        let otherURL = f.url.appendingPathComponent("other")
        let other = ResourceKey(url: otherURL, configuration: .default)
        for key in [f.key, variant, other] { f.cache.insert(resource, for: key) }
        for url in [f.url, otherURL] {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            f.httpCache.storeCachedResponse(CachedURLResponse(response: response, data: Data([1])), for: URLRequest(url: url))
        }
        await f.pipeline.removeCachedResource(for: URL(string: f.url.absoluteString + "#view")!)
        let a = f.cache.value(for: f.key)
        let b = f.cache.value(for: variant)
        let c = f.cache.value(for: other)
        XCTAssertNil(a)
        XCTAssertNil(b)
        XCTAssertNotNil(c)
        XCTAssertNil(f.httpCache.cachedResponse(for: URLRequest(url: f.url)))
        XCTAssertNotNil(f.httpCache.cachedResponse(for: URLRequest(url: otherURL)))
    }

    func testAnalyzeAndIndependentCacheClears() async throws {
        let f = fixture()
        let image = try GeneratedImageFixture.makeImage(width: 16, height: 8)
        let resource = try await f.pipeline.analyze(cgImage: image)
        XCTAssertTrue(resource.image === image)
        XCTAssertEqual(resource.analysis.focusSource, .imageCenter)
        f.cache.insert(resource, for: f.key)
        let response = HTTPURLResponse(url: f.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        f.httpCache.storeCachedResponse(CachedURLResponse(response: response, data: Data([1])), for: URLRequest(url: f.url))
        f.pipeline.clearMemoryCache()
        let cleared = f.cache.value(for: f.key)
        XCTAssertNil(cleared)
        XCTAssertNotNil(f.httpCache.cachedResponse(for: URLRequest(url: f.url)))
        f.cache.insert(resource, for: f.key)
        await f.pipeline.clearDiskCache()
        XCTAssertNil(f.httpCache.cachedResponse(for: URLRequest(url: f.url)))
        let retained = f.cache.value(for: f.key)
        XCTAssertNotNil(retained)
        do {
            _ = try await f.pipeline.analyze(data: Data([0]))
            XCTFail("Expected decoding failure")
        } catch FaceAwareImageError.decodingFailed {} catch { XCTFail("\(error)") }
    }

    func testAlreadyCancelledLoadCreatesNoRequest() async {
        let f = fixture()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await f.pipeline.load(url: f.url)
        }
        await assertCancelled(task)
        XCTAssertEqual(f.control.requestCount, 0)
    }

    func testCancellationErrorFromTransportMapsToCancelled() async {
        let pipeline = ImagePipeline(configuration: .default, transport: { _ in throw CancellationError() })
        await assertCancelled(Task { try await pipeline.load(url: URL(string: "https://example.com/image")!) })
    }

    func testBothAnalysisInputsBoundDisplayAndVisionImageSizes() async throws {
        struct ThumbnailVision: VisionRequestRunning {
            nonisolated func faceRegions(in image: CGImage) throws -> [CGRect] {
                guard image.width == 4, image.height == 2 else {
                    throw NSError(domain: "Unexpected analysis thumbnail size", code: 1)
                }
                return [CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)]
            }
            nonisolated func salientRegions(in image: CGImage) throws -> [CGRect] { [] }
        }
        let pipeline = ImagePipeline(
            configuration: .init(displayMaxPixelSize: 10, analysisMaxPixelSize: 4,
                                 analysisFailurePolicy: .failRequest),
            analyzer: VisionAnalyzer(requestRunner: ThumbnailVision())
        )
        let image = try GeneratedImageFixture.makeImage(width: 20, height: 10)
        let data = try GeneratedImageFixture.makePNGData(width: 20, height: 10)
        let fromImage = try await pipeline.analyze(cgImage: image)
        let fromData = try await pipeline.analyze(data: data)
        for resource in [fromImage, fromData] {
            XCTAssertEqual(resource.pixelSize, CGSize(width: 10, height: 5))
            XCTAssertEqual(resource.image.width, 10)
            XCTAssertEqual(resource.image.height, 5)
            XCTAssertEqual(resource.analysis.focusSource, .face)
        }
    }

    func testDelayedAutomaticHTTPStoreCannotRepopulateRemovedURL() async throws {
        let stores = HTTPStoreBarrier()
        let f = fixture(storeBarrier: stores)
        let old = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(1)
        f.control.complete(data: try GeneratedImageFixture.makePNGData(width: 32, height: 8),
                           cacheControl: "public, max-age=3600", storagePolicy: .allowed)
        await stores.waitForStores(1)
        _ = try await old.value
        await f.pipeline.removeCachedResource(for: f.url)
        stores.release(0) // Actual Foundation write arrives after removal completed.
        XCTAssertNil(f.httpCache.cachedResponse(for: URLRequest(url: f.url)))
        let replacement = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(2)
        f.control.complete(1, data: try GeneratedImageFixture.makePNGData(width: 16, height: 8),
                           cacheControl: "public, max-age=3600", storagePolicy: .allowed)
        await stores.waitForStores(2)
        stores.release(1)
        let fresh = try await replacement.value
        XCTAssertEqual(fresh.pixelSize.width, 16)
        XCTAssertNotNil(f.httpCache.cachedResponse(for: URLRequest(url: f.url)))
    }

    func testSuccessfulRetiredWorkerPreservesPendingReplacementInSameGeneration() async throws {
        try await assertSuccessfulRetirement(removing: false)
    }

    func testSuccessfulInvalidatedWorkerPreservesPendingReplacement() async throws {
        try await assertSuccessfulRetirement(removing: true)
    }

    private func assertSuccessfulRetirement(removing: Bool) async throws {
        let barrier = PipelineSuccessBarrier()
        let stores = HTTPStoreBarrier()
        let f = fixture(storeBarrier: stores, successBarrier: barrier)
        let old = Task { try await f.pipeline.load(url: f.url) }
        await f.control.waitForRequests(1)
        let oldValue = await f.pipeline.inFlight[f.key]
        let oldEntry = try XCTUnwrap(oldValue)
        f.control.complete(data: try GeneratedImageFixture.makePNGData(width: 32, height: 8),
                           cacheControl: "public, max-age=3600", storagePolicy: .allowed)
        await barrier.waitUntilEntered()
        await stores.waitForStores(1)
        if removing { await f.pipeline.removeCachedResource(for: f.url) } else { old.cancel() }
        await assertCancelled(old)
        let first = Task { try await f.pipeline.load(url: f.url) }
        let second = Task { try await f.pipeline.load(url: f.url) }
        await waitForWaiters(2, in: f)
        await f.control.waitForRequests(2)
        let replacementValue = await f.pipeline.inFlight[f.key]
        let replacement = try XCTUnwrap(replacementValue)
        XCTAssertNotEqual(replacement.id, oldEntry.id)
        XCTAssertEqual(replacement.generation, oldEntry.generation + (removing ? 1 : 0))
        stores.release(0)
        XCTAssertNil(f.httpCache.cachedResponse(for: URLRequest(url: f.url)))
        await barrier.release()
        let successfulOldResource = try await oldEntry.task.value
        XCTAssertEqual(successfulOldResource.pixelSize.width, 32) // MUST reach finish as success.
        let after = await f.pipeline.inFlight[f.key]
        XCTAssertEqual(after?.id, replacement.id)
        XCTAssertEqual(after?.waiterIDs, replacement.waiterIDs)
        let stale = f.cache.value(for: f.key)
        XCTAssertNil(stale)
        f.control.complete(1, data: try GeneratedImageFixture.makePNGData(width: 16, height: 8),
                           cacheControl: "public, max-age=3600", storagePolicy: .allowed)
        await stores.waitForStores(2)
        stores.release(1)
        let a = try await first.value
        let b = try await second.value
        XCTAssertTrue(a.image === b.image)
        XCTAssertEqual(a.pixelSize.width, 16)
        let cached = f.cache.value(for: f.key)
        XCTAssertTrue(cached?.image === a.image)
        XCTAssertNotNil(f.httpCache.cachedResponse(for: URLRequest(url: f.url)))
    }

    func testNativeHTTPObeysFreshnessNoStoreAndRevalidationHeaders() async throws {
        let server = try PipelineHTTPServer(first: GeneratedImageFixture.makePNGData(width: 16, height: 8),
                                            next: GeneratedImageFixture.makePNGData(width: 32, height: 8))
        let base = try await server.start()
        defer { server.stop() }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0)
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let pipeline = ImagePipeline(configuration: .default, session: session,
                                     analyzer: VisionAnalyzer(requestRunner: EmptyVision()))
        for path in ["fresh", "no-store", "expired", "no-cache"] {
            let url = base.appendingPathComponent(path)
            let first = try await pipeline.load(url: url)
            XCTAssertEqual(first.pixelSize.width, 16)
            pipeline.clearMemoryCache()
            let second = try await pipeline.load(url: url)
            XCTAssertEqual(second.pixelSize.width, path == "fresh" ? 16 : 32, path)
            XCTAssertEqual(server.count(for: "/" + path), path == "fresh" ? 1 : 2, path)
        }
    }

    func testNativeHTTPLateStoreCannotServeRetiredBytesAndFreshReplacementIsReusable() async throws {
        let server = try PipelineHTTPServer(first: GeneratedImageFixture.makePNGData(width: 32, height: 8),
                                            next: GeneratedImageFixture.makePNGData(width: 16, height: 8))
        let base = try await server.start()
        defer { server.stop() }
        let url = base.appendingPathComponent("race")
        let cache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = cache
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let stores = HTTPStoreBarrier()
        let pipeline = ImagePipeline(configuration: .default, session: session,
                                     analyzer: VisionAnalyzer(requestRunner: EmptyVision()),
                                     cacheDecorator: { DelayedHTTPStoreCache(backing: $0, barrier: stores) })
        let old = try await pipeline.load(url: url)
        XCTAssertEqual(old.pixelSize.width, 32)
        await stores.waitForStores(1)
        await pipeline.removeCachedResource(for: url)
        stores.release(0)
        XCTAssertNil(cache.cachedResponse(for: URLRequest(url: url)))
        let replacement = try await pipeline.load(url: url)
        XCTAssertEqual(replacement.pixelSize.width, 16)
        XCTAssertEqual(server.count(for: "/race"), 2)
        await stores.waitForStores(2)
        stores.release(1)
        pipeline.clearMemoryCache()
        let cachedReplacement = try await pipeline.load(url: url)
        XCTAssertEqual(cachedReplacement.pixelSize.width, 16)
        XCTAssertEqual(server.count(for: "/race"), 2)
    }

    // MARK: - Per-client HTTP cache directories

    /// A root of its own per test, removed on teardown, so neither test observes the
    /// process-scoped "directories this process created" set of the other.
    private func makeTemporaryCacheRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FaceAwareImageKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testPipelinesWithTheSameConfigurationOwnDifferentExistingCacheDirectories() async throws {
        let root = try makeTemporaryCacheRoot()
        let first = ImagePipeline(configuration: .default, cacheRootDirectory: root)
        let second = ImagePipeline(configuration: .default, cacheRootDirectory: root)
        let firstOwned = await first.ownedHTTPCacheDirectory()
        let secondOwned = await second.ownedHTTPCacheDirectory()
        let firstDirectory = try XCTUnwrap(firstOwned)
        let secondDirectory = try XCTUnwrap(secondOwned)

        XCTAssertNotEqual(firstDirectory, secondDirectory)
        XCTAssertNotEqual(firstDirectory.lastPathComponent, secondDirectory.lastPathComponent)
        for directory in [firstDirectory, secondDirectory] {
            XCTAssertTrue(directory.path.hasPrefix(root.standardizedFileURL.path),
                          "\(directory.path) must live under the injected root")
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                          "\(directory.path) must exist on disk")
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testCacheDirectoryCreationSweepsStaleSiblingsAndKeepsProcessDirectories() async throws {
        let root = try makeTemporaryCacheRoot()
        let manager = FileManager.default
        let stale = root.appendingPathComponent("stale-from-an-earlier-launch", isDirectory: true)
        let strayFile = root.appendingPathComponent("not-a-cache-directory.txt")
        try manager.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data([1]).write(to: strayFile)

        // A directory this process created is recognizable before the sweep runs.
        let owned = ImagePipeline(configuration: .default, cacheRootDirectory: root)
        let ownedValue = await owned.ownedHTTPCacheDirectory()
        let ownedDirectory = try XCTUnwrap(ownedValue)
        XCTAssertTrue(HTTPCacheDirectory.didCreate(ownedDirectory))

        HTTPCacheDirectory.sweep(under: root)

        XCTAssertFalse(manager.fileExists(atPath: stale.path), "An earlier launch's directory must be swept")
        XCTAssertTrue(manager.fileExists(atPath: ownedDirectory.path),
                      "A directory this process created must survive the sweep")
        XCTAssertTrue(manager.fileExists(atPath: strayFile.path), "The sweep removes directories, not files")
        XCTAssertTrue(manager.fileExists(atPath: root.path), "The root itself must survive")
    }
}
