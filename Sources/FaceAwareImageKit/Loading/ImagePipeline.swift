import CoreGraphics
import Foundation

actor ImagePipeline {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    struct InFlightEntry {
        let task: Task<FaceAwareImageResource, Error>
        var waiterIDs: Set<UUID>
        let generation: UInt64
        let id: UUID
        let httpScope: HTTPResponseCache.Scope?
        var continuations: [UUID: CheckedContinuation<FaceAwareImageResource, Error>]
    }

    private(set) var inFlight: [ResourceKey: InFlightEntry] = [:]
    private var invalidationGenerationByURL: [URL: UInt64] = [:]
    private let configuration: FaceAwareImageConfiguration
    private let decodedCache: DecodedImageCache
    private let httpCache: HTTPResponseCache?
    private let sessionConfiguration: URLSessionConfiguration
    private let transportOverride: Transport?
    private let cacheDecorator: (@Sendable (URLCache) -> URLCache)?
    private let analyzer: VisionAnalyzer
    private let beforeFinish: (@Sendable (FaceAwareImageResource) async -> Void)?
    // The directory handed to this pipeline's `URLCache`, when the pipeline owns its
    // HTTP cache. Fixed at construction; `ownedHTTPCacheDirectory()` exposes it to
    // tests, since actor state is not readable synchronously from outside the actor.
    private let httpCacheDirectory: URL?

    // Pipeline transactions retain their serialization across acquisition awaits.
    // Decoded-cache operations are synchronous and separately protected by a lock,
    // so memory clearing can also run safely without entering this actor.
    private var transactionActive = false
    private var transactionWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        configuration: FaceAwareImageConfiguration,
        session: URLSession? = nil,
        decodedCache: DecodedImageCache? = nil,
        analyzer: VisionAnalyzer = VisionAnalyzer(),
        transport: Transport? = nil,
        cacheDecorator: (@Sendable (URLCache) -> URLCache)? = nil,
        beforeFinish: (@Sendable (FaceAwareImageResource) async -> Void)? = nil,
        cacheRootDirectory: URL = HTTPCacheDirectory.defaultRoot
    ) {
        self.configuration = configuration
        self.decodedCache = decodedCache ?? DecodedImageCache(capacity: configuration.decodedMemoryCapacity)
        self.analyzer = analyzer
        self.beforeFinish = beforeFinish
        let resolvedConfiguration: URLSessionConfiguration
        if let session {
            resolvedConfiguration = session.configuration
            httpCacheDirectory = nil
        } else {
            // This pipeline owns the store. Its directory is unique to the instance, so
            // no other client and no host-app cache can reach these entries.
            let directory = HTTPCacheDirectory.create(under: cacheRootDirectory)
            httpCacheDirectory = directory
            resolvedConfiguration = URLSessionConfiguration.default
            resolvedConfiguration.urlCache = URLCache(
                memoryCapacity: configuration.httpMemoryCapacity,
                diskCapacity: configuration.httpDiskCapacity,
                directory: directory
            )
        }
        sessionConfiguration = resolvedConfiguration
        httpCache = resolvedConfiguration.urlCache.map(HTTPResponseCache.init)
        transportOverride = transport
        self.cacheDecorator = cacheDecorator
    }

    deinit {
        for entry in inFlight.values {
            entry.task.cancel()
            httpCache?.retire(entry.httpScope)
            for continuation in entry.continuations.values {
                continuation.resume(throwing: FaceAwareImageError.cancelled)
            }
        }
    }

    func load(url: URL) async throws -> FaceAwareImageResource {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            throw FaceAwareImageError.invalidURL
        }
        let key = ResourceKey(url: url, configuration: configuration)
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            await acquireTransaction()
            if Task.isCancelled {
                releaseTransaction()
                throw FaceAwareImageError.cancelled
            }
            let cached = decodedCache.value(for: key)
            if Task.isCancelled {
                releaseTransaction()
                throw FaceAwareImageError.cancelled
            }
            if let cached {
                releaseTransaction()
                return cached
            }
            return try await withCheckedThrowingContinuation { continuation in
                // Registration and lease release have no suspension point. If
                // cancellation happened during lookup, the checks above catch it;
                // otherwise the handler removes this registered ownership token.
                if var entry = inFlight[key] {
                    entry.waiterIDs.insert(waiterID)
                    entry.continuations[waiterID] = continuation
                    inFlight[key] = entry
                } else {
                    let generation = invalidationGenerationByURL[key.url, default: 0]
                    let id = UUID()
                    let request = Self.canonicalRequest(for: key.url)
                    let httpScope = httpCache?.scope(for: key.url)
                    let transport = makeTransport(scope: httpScope)
                    let task = Task { [weak self, transport, configuration, analyzer, beforeFinish] in
                        let result: Result<FaceAwareImageResource, Error>
                        do {
                            try Task.checkCancellation()
                            let (data, response) = try await transport(request)
                            try Task.checkCancellation()
                            guard let response = response as? HTTPURLResponse else {
                                throw FaceAwareImageError.network(description: "Expected an HTTP response.")
                            }
                            guard (200..<300).contains(response.statusCode) else {
                                throw FaceAwareImageError.unacceptableStatusCode(response.statusCode)
                            }
                            let resource = try Self.process(data: data, configuration: configuration, analyzer: analyzer)
                            try Task.checkCancellation()
                            result = .success(resource)
                        } catch {
                            result = .failure(Self.map(error))
                        }
                        if case let .success(resource) = result { await beforeFinish?(resource) }
                        await self?.finish(result, for: key, id: id, generation: generation)
                        return try result.get()
                    }
                    inFlight[key] = InFlightEntry(
                        task: task, waiterIDs: [waiterID], generation: generation, id: id, httpScope: httpScope,
                        continuations: [waiterID: continuation]
                    )
                }
                releaseTransaction()
            }
        } onCancel: {
            // A short actor hop bridges the synchronous cancellation callback.
            // The owned worker is explicitly cancelled when the last token leaves.
            Task { await self.cancelWaiter(waiterID, for: key) }
        }
    }

    func analyze(data: Data) throws -> FaceAwareImageResource {
        do {
            return try Self.process(data: data, configuration: configuration, analyzer: analyzer)
        } catch { throw Self.map(error) }
    }

    func analyze(cgImage: CGImage) throws -> FaceAwareImageResource {
        do {
            try Task.checkCancellation()
            let displayImage = try Self.downsample(cgImage, maxPixelSize: configuration.displayMaxPixelSize)
            let analysisImage = try Self.downsample(cgImage, maxPixelSize: configuration.analysisMaxPixelSize)
            let analysis = try analyzer.analyze(cgImage: analysisImage, configuration: configuration)
            try Task.checkCancellation()
            return FaceAwareImageResource(image: displayImage,
                                          pixelSize: CGSize(width: displayImage.width, height: displayImage.height),
                                          analysis: analysis)
        } catch { throw Self.map(error) }
    }

    nonisolated func clearMemoryCache() {
        decodedCache.removeAll()
    }

    /// The on-disk directory this pipeline's HTTP cache owns, or `nil` when the pipeline
    /// does not own one (an injected session or a transport seam). Internal test seam.
    func ownedHTTPCacheDirectory() -> URL? {
        httpCacheDirectory
    }

    func clearDiskCache() async {
        await acquireTransaction()
        httpCache?.removeAll()
        releaseTransaction()
    }

    func removeCachedResource(for url: URL) async {
        await acquireTransaction()
        defer { releaseTransaction() }
        let normalizedURL = ResourceKey.normalizedURL(url)
        invalidationGenerationByURL[normalizedURL, default: 0] &+= 1
        // Foundation's synchronous cache callbacks use this same cache lock.
        // Invalidation + eviction are indivisible with respect to actual stores.
        httpCache?.invalidate(normalizedURL)
        for key in inFlight.keys.filter({ $0.url == normalizedURL }) {
            guard let entry = inFlight.removeValue(forKey: key) else { continue }
            entry.task.cancel()
            for continuation in entry.continuations.values {
                continuation.resume(throwing: FaceAwareImageError.cancelled)
            }
        }
        decodedCache.removeAll(for: normalizedURL)
    }

    private func finish(_ result: Result<FaceAwareImageResource, Error>, for key: ResourceKey,
                        id: UUID, generation: UInt64) async {
        await acquireTransaction()
        defer { releaseTransaction() }
        guard let entry = inFlight[key], entry.id == id,
              entry.generation == generation,
              invalidationGenerationByURL[key.url, default: 0] == generation else { return }
        if case let .success(resource) = result {
            decodedCache.insert(resource, for: key)
        }
        inFlight.removeValue(forKey: key)
        for continuation in entry.continuations.values { continuation.resume(with: result) }
    }

    private func cancelWaiter(_ id: UUID, for key: ResourceKey) async {
        await acquireTransaction()
        defer { releaseTransaction() }
        guard var entry = inFlight[key], entry.waiterIDs.remove(id) != nil else { return }
        entry.continuations.removeValue(forKey: id)?.resume(throwing: FaceAwareImageError.cancelled)
        if entry.waiterIDs.isEmpty {
            entry.task.cancel()
            httpCache?.retire(entry.httpScope)
            inFlight.removeValue(forKey: key)
        } else {
            inFlight[key] = entry
        }
    }

    private func makeTransport(scope: HTTPResponseCache.Scope?) -> Transport {
        if let transportOverride { return transportOverride }
        let snapshot = sessionConfiguration.copy() as! URLSessionConfiguration
        if let httpCache, let scope {
            let cache = HTTPScopedURLCache(owner: httpCache, scope: scope)
            snapshot.urlCache = cacheDecorator?(cache) ?? cache
        }
        // A session's cache view is immutable and belongs to this work's epoch.
        // Retired callbacks cannot acquire a replacement session's cache rights.
        return { request in
            let session = URLSession(configuration: snapshot)
            defer { session.finishTasksAndInvalidate() }
            return try await session.data(for: request)
        }
    }

    private func acquireTransaction() async {
        if transactionActive {
            await withCheckedContinuation { transactionWaiters.append($0) }
        } else {
            transactionActive = true
        }
    }

    private func releaseTransaction() {
        if transactionWaiters.isEmpty {
            transactionActive = false
        } else {
            transactionWaiters.removeFirst().resume()
        }
    }

    private nonisolated static func canonicalRequest(for url: URL) -> URLRequest {
        URLRequest(url: ResourceKey.normalizedURL(url))
    }

    private nonisolated static func map(_ error: Error) -> FaceAwareImageError {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return .cancelled }
        if let error = error as? FaceAwareImageError { return error }
        return .network(description: error.localizedDescription)
    }

    private nonisolated static func process(data: Data, configuration: FaceAwareImageConfiguration,
                                            analyzer: VisionAnalyzer) throws -> FaceAwareImageResource {
        try Task.checkCancellation()
        let images = try ImageDecoder.decode(data: data, displayMaxPixelSize: configuration.displayMaxPixelSize,
                                             analysisMaxPixelSize: configuration.analysisMaxPixelSize)
        try Task.checkCancellation()
        let analysis = try analyzer.analyze(cgImage: images.analysis, configuration: configuration)
        try Task.checkCancellation()
        return FaceAwareImageResource(image: images.display,
                                      pixelSize: CGSize(width: images.display.width, height: images.display.height),
                                      analysis: analysis)
    }

    private nonisolated static func downsample(_ image: CGImage, maxPixelSize: Int) throws -> CGImage {
        let scale = min(1, CGFloat(maxPixelSize) / CGFloat(max(image.width, image.height)))
        if scale == 1 { return image }
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FaceAwareImageError.decodingFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw FaceAwareImageError.decodingFailed }
        return result
    }
}

// URLCache callbacks are synchronous and may outlive their URLSession task. A
// short lock protects the real storage operation, not merely permission to store
// later. Foundation still decides cacheability, freshness, and revalidation.
final class HTTPResponseCache: @unchecked Sendable {
    final class Scope: @unchecked Sendable {
        let url: URL
        let generation: UInt64
        let epoch: UUID
        // Accessed only while the owning HTTPResponseCache's lock is held.
        fileprivate var retired = false

        fileprivate init(url: URL, generation: UInt64, epoch: UUID) {
            self.url = url
            self.generation = generation
            self.epoch = epoch
        }
    }

    let backing: URLCache
    private let lock = NSLock()
    private var generations: [URL: UInt64] = [:]
    private var epoch = UUID()
    private var requestsByURL: [URL: Set<URLRequest>] = [:]

    init(backing: URLCache) { self.backing = backing }

    func scope(for url: URL) -> Scope {
        lock.withLock { Scope(url: url, generation: generations[url, default: 0], epoch: epoch) }
    }

    func retire(_ scope: Scope?) {
        lock.withLock { scope?.retired = true }
    }

    func access<T>(_ scope: Scope, requests: [URLRequest] = [], _ operation: () -> T) -> T? {
        lock.withLock {
            guard !scope.retired, scope.epoch == epoch,
                  scope.generation == generations[scope.url, default: 0] else { return nil }
            if !requests.isEmpty { requestsByURL[scope.url, default: []].formUnion(requests) }
            return operation()
        }
    }

    func invalidate(_ url: URL) {
        lock.withLock {
            generations[url, default: 0] &+= 1
            var requests = requestsByURL.removeValue(forKey: url) ?? []
            requests.insert(URLRequest(url: url))
            for request in requests { backing.removeCachedResponse(for: request) }
        }
    }

    func removeAll() {
        lock.withLock {
            epoch = UUID()
            requestsByURL.removeAll()
            backing.removeAllCachedResponses()
        }
    }
}

private final class HTTPScopedURLCache: URLCache, @unchecked Sendable {
    private let owner: HTTPResponseCache
    private let scope: HTTPResponseCache.Scope

    init(owner: HTTPResponseCache, scope: HTTPResponseCache.Scope) {
        self.owner = owner
        self.scope = scope
        super.init(memoryCapacity: owner.backing.memoryCapacity, diskCapacity: owner.backing.diskCapacity, diskPath: nil)
    }

    override func storeCachedResponse(_ response: CachedURLResponse, for request: URLRequest) {
        owner.access(scope, requests: [request]) { owner.backing.storeCachedResponse(response, for: request) }
    }

    override func storeCachedResponse(_ response: CachedURLResponse, for task: URLSessionDataTask) {
        let requests = [task.originalRequest, task.currentRequest].compactMap { $0 }
        owner.access(scope, requests: requests) { owner.backing.storeCachedResponse(response, for: task) }
    }

    override func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        owner.access(scope) { owner.backing.cachedResponse(for: request) } ?? nil
    }

    override func getCachedResponse(for task: URLSessionDataTask,
                                    completionHandler: @escaping @Sendable (CachedURLResponse?) -> Void) {
        // Never call client code under the cache lock. Preserve Foundation's
        // task-based lookup and recheck the epoch after its asynchronous return.
        owner.backing.getCachedResponse(for: task) { [owner, scope] response in
            let current = owner.access(scope) { response } ?? nil
            completionHandler(current)
        }
    }

    override func removeCachedResponse(for request: URLRequest) {
        owner.access(scope) { owner.backing.removeCachedResponse(for: request) }
    }

    override func removeCachedResponse(for task: URLSessionDataTask) {
        owner.access(scope) { owner.backing.removeCachedResponse(for: task) }
    }
}
