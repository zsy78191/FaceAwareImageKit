import CoreGraphics
import Foundation
import XCTest
@testable import FaceAwareImageKit

nonisolated final class AsyncImageStateTests: XCTestCase {
    private let firstURL = URL(string: "https://example.com/first.png")!
    private let secondURL = URL(string: "https://example.com/second.png")!

    @MainActor
    func testInitialPhaseIsEmpty() {
        let model = AsyncImageModel(client: GatedImageLoader())

        assertEmpty(model.phase)
    }

    @MainActor
    func testSuccessfulLoadEmitsSuccess() async throws {
        let expected = try makeResource()
        let loader = GatedImageLoader()
        let model = AsyncImageModel(client: loader)
        var lastReported: FaceAwareImagePhase = .empty
        model.onPhaseChange = { lastReported = $0 }

        let load = startLoad(model, url: firstURL)
        await loader.waitUntilRequested(firstURL)
        await loader.resume(firstURL, with: .success(expected))
        await load.value

        guard case let .success(actual) = model.phase else {
            return XCTFail("Expected .success, got \(model.phase)")
        }
        XCTAssertTrue(actual.image === expected.image)
        XCTAssertEqual(actual.pixelSize, expected.pixelSize)
        XCTAssertEqual(actual.analysis, expected.analysis)

        // The view observes the model only through this callback.
        guard case let .success(reported) = lastReported else {
            return XCTFail("Expected a reported .success, got \(lastReported)")
        }
        XCTAssertTrue(reported.image === expected.image)
    }

    @MainActor
    func testFailedLoadEmitsFailure() async throws {
        let loader = GatedImageLoader()
        let model = AsyncImageModel(client: loader)

        let load = startLoad(model, url: firstURL)
        await loader.waitUntilRequested(firstURL)
        await loader.resume(firstURL, with: .failure(.decodingFailed))
        await load.value

        guard case .failure(.decodingFailed) = model.phase else {
            return XCTFail("Expected .failure(.decodingFailed), got \(model.phase)")
        }
    }

    @MainActor
    func testChangingURLCancelsPriorLoadAndIgnoresItsLateCompletion() async throws {
        let stale = try makeResource()
        let current = try makeResource()
        let loader = GatedImageLoader()
        let model = AsyncImageModel(client: loader)

        let firstLoad = startLoad(model, url: firstURL)
        await loader.waitUntilRequested(firstURL)

        let secondLoad = startLoad(model, url: secondURL)
        await loader.waitUntilRequested(secondURL)

        await loader.resume(secondURL, with: .success(current))
        await secondLoad.value
        guard case let .success(replaced) = model.phase, replaced.image === current.image else {
            return XCTFail("Expected the replacement's .success, got \(model.phase)")
        }

        // The obsolete request succeeds only after its replacement already finished.
        await loader.resume(firstURL, with: .success(stale))
        await firstLoad.value

        let cancelled = await loader.cancelledURLs
        XCTAssertEqual(cancelled, [firstURL])
        guard case let .success(finalPhase) = model.phase, finalPhase.image === current.image else {
            return XCTFail("A late completion replaced the current phase: \(model.phase)")
        }
    }

    @MainActor
    func testNilURLReturnsToEmptyWithoutStartingARequest() async throws {
        let stale = try makeResource()
        let loader = GatedImageLoader()
        let model = AsyncImageModel(client: loader)

        let firstLoad = startLoad(model, url: firstURL)
        await loader.waitUntilRequested(firstURL)

        await model.load(url: nil)
        assertEmpty(model.phase)

        await loader.resume(firstURL, with: .success(stale))
        await firstLoad.value

        let requested = await loader.requestedURLs
        XCTAssertEqual(requested, [firstURL])
        let cancelled = await loader.cancelledURLs
        XCTAssertEqual(cancelled, [firstURL])
        assertEmpty(model.phase)
    }

    @MainActor
    func testStartingANewURLClearsThePreviousPhaseWhileLoading() async throws {
        let previous = try makeResource()
        let next = try makeResource()
        let loader = GatedImageLoader()
        let model = AsyncImageModel(client: loader)

        let firstLoad = startLoad(model, url: firstURL)
        await loader.waitUntilRequested(firstURL)
        await loader.resume(firstURL, with: .success(previous))
        await firstLoad.value
        guard case .success = model.phase else {
            return XCTFail("Expected the first load to succeed, got \(model.phase)")
        }

        let secondLoad = startLoad(model, url: secondURL)
        await waitUntil { if case .empty = model.phase { return true } else { return false } }
        await loader.waitUntilRequested(secondURL)
        await loader.resume(secondURL, with: .success(next))
        await secondLoad.value

        guard case let .success(actual) = model.phase, actual.image === next.image else {
            return XCTFail("Expected the replacement's .success, got \(model.phase)")
        }
    }

    /// A disappearing view cancels `.task(id: url)`, and that cancellation must reach
    /// the loader so the pipeline can drop its waiter token.
    @MainActor
    func testCancellingTheAwaitingCallerCancelsTheLoad() async throws {
        let stale = try makeResource()
        let loader = GatedImageLoader()
        let model = AsyncImageModel(client: loader)
        var reportedPhaseCount = 0
        model.onPhaseChange = { _ in reportedPhaseCount += 1 }

        let caller = startLoad(model, url: firstURL)
        await loader.waitUntilRequested(firstURL)

        caller.cancel()
        await loader.resume(firstURL, with: .success(stale))
        await caller.value

        let cancelled = await loader.cancelledURLs
        XCTAssertEqual(cancelled, [firstURL], "Cancelling the caller must cancel the load at its source")
        assertEmpty(model.phase)
        XCTAssertEqual(reportedPhaseCount, 1, "A cancelled load must publish nothing after the initial .empty")
    }

    // MARK: - The view path stores no callback in its model

    /// The production view mirrors the model through `AsyncImagePhaseMirror` instead of
    /// assigning `onPhaseChange`, so the model must never hold a view-capturing closure.
    @MainActor
    func testViewPathLeavesTheModelWithoutAStoredPhaseCallback() async throws {
        let expected = try makeResource()
        let loader = GatedImageLoader()
        let mirror = AsyncImagePhaseMirror(client: loader)

        mirror.begin()
        assertEmpty(mirror.phase)

        let load = Task { await mirror.load(url: firstURL) }
        await loader.waitUntilRequested(firstURL)
        assertEmpty(mirror.phase)
        XCTAssertNil(mirror._model.onPhaseChange, "The view path must not store a phase callback")

        await loader.resume(firstURL, with: .success(expected))
        await load.value

        guard case let .success(actual) = mirror.phase else {
            return XCTFail("Expected .success, got \(mirror.phase)")
        }
        XCTAssertTrue(actual.image === expected.image)
        XCTAssertNil(mirror._model.onPhaseChange, "The view path must not store a phase callback")
    }

    @MainActor
    func testViewPathMirrorsAFailurePhaseAndNilURL() async throws {
        let loader = GatedImageLoader()
        let mirror = AsyncImagePhaseMirror(client: loader)
        mirror.begin()

        let load = Task { await mirror.load(url: firstURL) }
        await loader.waitUntilRequested(firstURL)
        await loader.resume(firstURL, with: .failure(.decodingFailed))
        await load.value
        guard case .failure(.decodingFailed) = mirror.phase else {
            return XCTFail("Expected .failure(.decodingFailed), got \(mirror.phase)")
        }

        await mirror.load(url: nil)
        assertEmpty(mirror.phase)
    }

    /// A superseded task can resume after its cancellation; it must mirror whatever
    /// phase the model now holds rather than republishing the phase it started from.
    @MainActor
    func testSupersededViewPathTaskMirrorsTheCurrentPhase() async throws {
        let stale = try makeResource()
        let current = try makeResource()
        let loader = GatedImageLoader()
        let mirror = AsyncImagePhaseMirror(client: loader)
        mirror.begin()

        let firstLoad = Task { await mirror.load(url: firstURL) }
        await loader.waitUntilRequested(firstURL)
        let secondLoad = Task { await mirror.load(url: secondURL) }
        await loader.waitUntilRequested(secondURL)
        await loader.resume(secondURL, with: .success(current))
        await secondLoad.value
        guard case let .success(replaced) = mirror.phase, replaced.image === current.image else {
            return XCTFail("Expected the replacement's .success, got \(mirror.phase)")
        }

        await loader.resume(firstURL, with: .success(stale))
        await firstLoad.value

        guard case let .success(final) = mirror.phase, final.image === current.image else {
            return XCTFail("A superseded task republished a stale phase: \(mirror.phase)")
        }
    }

    /// The cycle the fix removes was `model → closure → view → @State storage → model`.
    /// The view path holds the model only from its own `@State`, so the mirror's model
    /// is released when the mirror is.
    @MainActor
    func testViewPathModelIsReleasedWithItsMirror() {
        weak var weakModel: AsyncImageModel?
        var observed = false
        autoreleasepool {
            let mirror = AsyncImagePhaseMirror(client: GatedImageLoader())
            weakModel = mirror._model
            observed = weakModel != nil
        }

        guard observed else {
            return XCTFail("The weak reference was not set; the test cannot observe release")
        }
        XCTAssertNil(weakModel, "A model that stores no view-capturing closure must not outlive its mirror")
    }

    @MainActor
    private func makeResource() throws -> FaceAwareImageResource {
        FaceAwareImageResource(
            image: try GeneratedImageFixture.makeImage(width: 16, height: 8),
            pixelSize: CGSize(width: 16, height: 8),
            analysis: FaceAwareImageAnalysis(
                focalPoint: CGPoint(x: 0.25, y: 0.75),
                focusSource: .face,
                faceCount: 1,
                salientObjectCount: 0
            )
        )
    }

    /// Drives the model the way `FaceAwareAsyncImageContent` does from `.task(id: url)`:
    /// the load is awaited by a task that the caller can cancel.
    @MainActor
    private func startLoad(_ model: AsyncImageModel, url: URL?) -> Task<Void, Never> {
        Task { await model.load(url: url) }
    }

    @MainActor
    private func assertEmpty(
        _ phase: FaceAwareImagePhase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .empty = phase else {
            XCTFail("Expected .empty, got \(phase)", file: file, line: line)
            return
        }
    }

    /// Yields the main actor until `condition` holds, so the assertion does not depend
    /// on a sleep.
    @MainActor
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was never satisfied", file: file, line: line)
    }
}

/// A loader that suspends inside `load(url:)` until the test resumes it. The test can
/// therefore observe cancellation and late completions without timing assumptions.
private actor GatedImageLoader: FaceAwareImageLoading {
    private var continuations: [URL: CheckedContinuation<FaceAwareImageResource, Error>] = [:]
    private var requestWaiters: [URL: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var requestedURLs: [URL] = []
    private(set) var cancelledURLs: [URL] = []

    func load(url: URL) async throws -> FaceAwareImageResource {
        requestedURLs.append(url)
        for waiter in requestWaiters.removeValue(forKey: url) ?? [] {
            waiter.resume()
        }

        let resource = try await withCheckedThrowingContinuation { continuation in
            continuations[url] = continuation
        }

        if Task.isCancelled {
            cancelledURLs.append(url)
        }
        return resource
    }

    func resume(_ url: URL, with result: Result<FaceAwareImageResource, FaceAwareImageError>) {
        continuations.removeValue(forKey: url)?.resume(with: result)
    }

    func waitUntilRequested(_ url: URL) async {
        guard !requestedURLs.contains(url) else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[url, default: []].append(continuation)
        }
    }
}
