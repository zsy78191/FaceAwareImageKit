import CoreGraphics
import Foundation
import XCTest
@testable import FaceAwareImageKit

nonisolated final class FaceAwareImageClientTests: XCTestCase {
    @MainActor
    func testMemoryClearEvictsAllEntriesBeforeReturningWithoutSuspension() async throws {
        let cache = DecodedImageCache(capacity: .max)
        let otherCache = DecodedImageCache(capacity: .max)
        let url = URL(string: "https://example.com/cached.png")!
        let keys = [
            ResourceKey(url: url, configuration: .default),
            ResourceKey(url: url, configuration: .init(displayMaxPixelSize: 400)),
            ResourceKey(url: url.appendingPathComponent("other"), configuration: .default)
        ]
        let value = try resource()
        for key in keys { cache.insert(value, for: key) }
        otherCache.insert(value, for: keys[0])
        let client = FaceAwareImageClient(pipeline: ImagePipeline(configuration: .default, decodedCache: cache))

        await clearAndCheckSynchronously(client, cache: cache, otherCache: otherCache, keys: keys)
    }

    private func clearAndCheckSynchronously(
        _ client: isolated FaceAwareImageClient,
        cache: DecodedImageCache,
        otherCache: DecodedImageCache,
        keys: [ResourceKey]
    ) {
        for key in keys { XCTAssertNotNil(cache.value(for: key)) }
        client.clearMemoryCache()
        // No await or yield: a fire-and-forget eviction cannot satisfy this contract.
        for key in keys { XCTAssertNil(cache.value(for: key)) }
        XCTAssertNotNil(otherCache.value(for: keys[0]))
    }

    @MainActor
    private func resource() throws -> FaceAwareImageResource {
        FaceAwareImageResource(
            image: try GeneratedImageFixture.makeImage(width: 16, height: 8),
            pixelSize: CGSize(width: 16, height: 8),
            analysis: .init(focalPoint: CGPoint(x: 0.2, y: 0.7), focusSource: .face,
                            faceCount: 2, salientObjectCount: 0)
        )
    }

    private func assertUnchanged(_ actual: FaceAwareImageResource, _ expected: FaceAwareImageResource) {
        XCTAssertTrue(actual.image === expected.image)
        XCTAssertEqual(actual.pixelSize, expected.pixelSize)
        XCTAssertEqual(actual.analysis, expected.analysis)
    }

    @MainActor
    func testLoadDelegatesExactlyOnceWithUnchangedURLAndResult() async throws {
        let expected = try resource()
        let spy = PipelineSpy(result: .success(expected))
        let client = FaceAwareImageClient(pipeline: spy)
        let url = URL(string: "https://example.com/image.png?size=2#original")!

        let actual = try await client.load(url: url)

        assertUnchanged(actual, expected)
        let calls = spy.calls
        XCTAssertEqual(calls, [.load(url)])
    }

    @MainActor
    func testDataAnalysisDelegatesExactlyOnceWithUnchangedDataAndResult() async throws {
        let expected = try resource()
        let spy = PipelineSpy(result: .success(expected))
        let client = FaceAwareImageClient(pipeline: spy)
        let data = Data([9, 8, 7, 6])

        let actual = try await client.analyze(data: data)

        assertUnchanged(actual, expected)
        let calls = spy.calls
        XCTAssertEqual(calls, [.data(data)])
    }

    @MainActor
    func testImageAnalysisDelegatesExactlyOnceWithSameImageAndResult() async throws {
        let expected = try resource()
        let spy = PipelineSpy(result: .success(expected))
        let client = FaceAwareImageClient(pipeline: spy)
        let input = try GeneratedImageFixture.makeImage(width: 32, height: 64)

        let actual = try await client.analyze(cgImage: input)

        assertUnchanged(actual, expected)
        let calls = spy.calls
        XCTAssertEqual(calls, [.image(ObjectIdentifier(input))])
    }

    @MainActor
    func testCacheControlsDelegateExactlyOnceToTheirMatchingOperations() async throws {
        let spy = PipelineSpy(result: .success(try resource()))
        let client = FaceAwareImageClient(pipeline: spy)
        let url = URL(string: "https://example.com/image.png?variant=3#original")!

        await client.clearMemoryCache()
        await client.clearDiskCache()
        await client.removeCachedResource(for: url)

        let calls = spy.calls
        XCTAssertEqual(calls, [.clearMemory, .clearDisk, .remove(url)])
    }

    @MainActor
    func testThrowingOperationsPreservePipelineErrorWithoutRetry() async throws {
        let spy = PipelineSpy(result: .failure(.analysisFailed(description: "sentinel")))
        let client = FaceAwareImageClient(pipeline: spy)
        let url = URL(string: "https://example.com/failure.png")!
        let data = Data([1, 3, 5])
        let image = try GeneratedImageFixture.makeImage(width: 8, height: 8)

        for operation in 0..<3 {
            do {
                switch operation {
                case 0: _ = try await client.load(url: url)
                case 1: _ = try await client.analyze(data: data)
                default: _ = try await client.analyze(cgImage: image)
                }
                XCTFail("Expected pipeline error")
            } catch let error as FaceAwareImageError {
                guard case let .analysisFailed(description) = error else {
                    XCTFail("Unexpected error: \(error)")
                    continue
                }
                XCTAssertEqual(description, "sentinel")
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
        let calls = spy.calls
        XCTAssertEqual(calls, [.load(url), .data(data), .image(ObjectIdentifier(image))])
    }
}

// The synchronous pipeline requirement needs synchronous recording. Only
// recordedCalls is mutable, and every access is protected by lock.
private nonisolated final class PipelineSpy: ImagePipelining, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case load(URL)
        case data(Data)
        case image(ObjectIdentifier)
        case clearMemory
        case clearDisk
        case remove(URL)
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    var calls: [Call] { lock.withLock { recordedCalls } }
    private let result: Result<FaceAwareImageResource, FaceAwareImageError>

    private func record(_ call: Call) {
        lock.withLock { recordedCalls.append(call) }
    }

    init(result: Result<FaceAwareImageResource, FaceAwareImageError>) {
        self.result = result
    }

    func load(url: URL) async throws -> FaceAwareImageResource {
        record(.load(url))
        return try result.get()
    }

    func analyze(data: Data) throws -> FaceAwareImageResource {
        record(.data(data))
        return try result.get()
    }

    func analyze(cgImage: CGImage) throws -> FaceAwareImageResource {
        record(.image(ObjectIdentifier(cgImage)))
        return try result.get()
    }

    func clearMemoryCache() { record(.clearMemory) }
    func clearDiskCache() async { record(.clearDisk) }
    func removeCachedResource(for url: URL) async { record(.remove(url)) }
}
