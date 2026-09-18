import CoreGraphics
import Foundation

/// A retained, configured client for image loading, analysis, and cache ownership.
///
/// A client owns one configured pipeline: its `URLSession` and HTTP cache, its decoded
/// image cache, and its table of in-flight requests. Requests for the same resource key
/// share a single in-flight task, so passing one client to many views is what lets them
/// reuse cache entries and deduplicate simultaneous work.
///
/// Create a client once for a feature and pass it to every related view. The default
/// ``shared`` client uses ``FaceAwareImageConfiguration/default`` and backs
/// ``FaceAwareAsyncImage`` and ``FaceAwareAsyncImageContent`` when no client is supplied.
///
/// > Important: Never create a client from a configuration inside a view's `body`.
/// > Each new client has an empty cache, so a view that constructs one per evaluation
/// > discards both the cache and the configuration it intended to use.
public actor FaceAwareImageClient {
    /// The process-wide client that uses ``FaceAwareImageConfiguration/default``.
    ///
    /// The default ``FaceAwareAsyncImage`` and ``FaceAwareAsyncImageContent`` views load
    /// through this instance. Use it when the default limits and analysis behavior are
    /// appropriate; create and retain a separate client when they are not.
    public static let shared = FaceAwareImageClient(configuration: .default)

    private let pipeline: any ImagePipelining

    /// Creates a client that owns a pipeline configured by `configuration`.
    ///
    /// The configuration is captured for the lifetime of the client. Retain the client
    /// for as long as its cache should stay warm.
    /// - Parameter configuration: The loading, analysis, and cache settings to use.
    ///   Defaults to ``FaceAwareImageConfiguration/default``.
    public init(configuration: FaceAwareImageConfiguration = .default) {
        pipeline = ImagePipeline(configuration: configuration)
    }

    internal init(pipeline: any ImagePipelining) {
        self.pipeline = pipeline
    }

    /// Loads, decodes, analyzes, and caches the image at `url`.
    ///
    /// A cached resource is returned without network, decode, or Vision work. Concurrent
    /// calls for the same resource key share one in-flight task. Cancelling the awaiting
    /// caller stops only that caller's wait while other consumers remain; the underlying
    /// work is cancelled once no consumer is left.
    ///
    /// - Parameter url: The remote image URL. Only HTTP and HTTPS URLs can be loaded.
    /// - Returns: The decoded image, its pixel size, and its resolved analysis.
    /// - Throws: ``FaceAwareImageError`` with ``FaceAwareImageError/invalidURL``,
    ///   ``FaceAwareImageError/unacceptableStatusCode(_:)``,
    ///   ``FaceAwareImageError/network(description:)``,
    ///   ``FaceAwareImageError/decodingFailed``, or
    ///   ``FaceAwareImageError/analysisFailed(description:)``. A cancelled request throws
    ///   ``FaceAwareImageError/cancelled``.
    public func load(url: URL) async throws -> FaceAwareImageResource {
        try await pipeline.load(url: url)
    }

    /// Decodes and analyzes image data the caller already has.
    ///
    /// The result is not persisted: the caches are keyed by URL, so caller-supplied data
    /// has no cache identity. Retain the returned resource, or implement your own
    /// identity-based caching.
    ///
    /// - Parameter data: The encoded image data, such as the contents of a PNG or JPEG file.
    /// - Returns: The decoded image, its pixel size, and its resolved analysis.
    /// - Throws: ``FaceAwareImageError/decodingFailed`` when the data is not a decodable
    ///   image, or ``FaceAwareImageError/analysisFailed(description:)`` when the
    ///   configuration uses ``FaceAwareAnalysisFailurePolicy/failRequest`` and Vision fails.
    public func analyze(data: Data) async throws -> FaceAwareImageResource {
        try await pipeline.analyze(data: data)
    }

    /// Downsamples and analyzes an image the caller already has.
    ///
    /// The decoded output is bounded by ``FaceAwareImageConfiguration/displayMaxPixelSize``
    /// just as a loaded image is, and the result is not persisted.
    ///
    /// - Parameter cgImage: The image to decode and analyze.
    /// - Returns: The decoded image, its pixel size, and its resolved analysis.
    /// - Throws: ``FaceAwareImageError/decodingFailed`` when the image cannot be decoded,
    ///   or ``FaceAwareImageError/analysisFailed(description:)`` when the configuration
    ///   uses ``FaceAwareAnalysisFailurePolicy/failRequest`` and Vision fails.
    public func analyze(cgImage: CGImage) async throws -> FaceAwareImageResource {
        try await pipeline.analyze(cgImage: cgImage)
    }

    /// Clears the client's decoded image resources.
    ///
    /// This method is deliberately **not** `async`. Decoded resources are released
    /// synchronously, and they are gone when this call returns. HTTP cache entries are
    /// untouched; use ``clearDiskCache()`` for those.
    ///
    /// The framework also clears decoded resources automatically when the system posts a
    /// memory warning.
    public func clearMemoryCache() {
        pipeline.clearMemoryCache()
    }

    /// Clears the client's HTTP response cache, including its memory entries.
    ///
    /// This method is `async` because clearing the underlying `URLCache` suspends disk
    /// work. Decoded image resources are untouched; use ``clearMemoryCache()`` for those.
    public func clearDiskCache() async {
        await pipeline.clearDiskCache()
    }

    /// Removes every cached resource for `url` and cancels matching in-flight work.
    ///
    /// Removal is URL-wide, not key-exact: it evicts **all configuration variants** owned
    /// by this client whose normalized URL matches, regardless of which
    /// ``FaceAwareImageConfiguration`` values produced them. It also cancels and
    /// invalidates every matching in-flight task before removing cached values, and each
    /// task carries a per-URL invalidation generation, so a task that races with the
    /// removal cannot write its result back afterward.
    ///
    /// The client's HTTP cached response is removed for every normalized `URLRequest`
    /// variant the framework creates for that URL. Request variants created outside the
    /// framework are not promised, because Foundation cannot enumerate every semantically
    /// equivalent cached request.
    ///
    /// - Parameter url: The image URL whose cached resources and in-flight work to remove.
    public func removeCachedResource(for url: URL) async {
        await pipeline.removeCachedResource(for: url)
    }
}

internal protocol ImagePipelining: Sendable {
    func load(url: URL) async throws -> FaceAwareImageResource
    func analyze(data: Data) async throws -> FaceAwareImageResource
    func analyze(cgImage: CGImage) async throws -> FaceAwareImageResource
    func clearMemoryCache()
    func clearDiskCache() async
    func removeCachedResource(for url: URL) async
}

extension ImagePipeline: ImagePipelining {}
