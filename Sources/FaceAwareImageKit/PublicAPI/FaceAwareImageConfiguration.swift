/// The decode, analysis, and cache settings a ``FaceAwareImageClient`` uses for its lifetime.
///
/// The initializer validates every value. A nonpositive pixel size or a negative capacity
/// triggers a documented precondition failure during development rather than undefined
/// cache behavior.
///
/// Resource identity — the key that decides whether a request is a cache hit — contains
/// ``displayMaxPixelSize``, ``analysisMaxPixelSize``, ``maximumWeightedFaceCount``, and
/// ``analysisFailurePolicy``. The three capacity settings are storage policy only and are
/// excluded from resource identity.
public struct FaceAwareImageConfiguration: Hashable, Sendable {
    /// The configuration a client uses when it is created without one.
    ///
    /// It is equivalent to `FaceAwareImageConfiguration()`: a 1600-pixel display bound,
    /// a 768-pixel analysis bound, three weighted faces, a 64 MB decoded cache, a 32 MB
    /// memory HTTP cache, a 200 MB disk HTTP cache, and
    /// ``FaceAwareAnalysisFailurePolicy/fallbackToCenter``.
    public static let `default` = Self()

    /// The maximum pixel dimension of the decoded image a consumer renders.
    ///
    /// Defaults to `1600`. It participates in resource identity. Must be positive.
    public var displayMaxPixelSize: Int

    /// The maximum pixel dimension of the separate thumbnail Vision analyzes.
    ///
    /// Defaults to `768`. It participates in resource identity. Vision never analyzes the
    /// unbounded network image, so this value bounds both analysis cost and the precision
    /// of the resolved focal point. Must be positive.
    public var analysisMaxPixelSize: Int

    /// The maximum number of faces that contribute to the focal point.
    ///
    /// Defaults to `3`. It participates in resource identity. Faces are sorted by area and
    /// the largest ones within this limit form an area-weighted center. Must be positive.
    public var maximumWeightedFaceCount: Int

    /// The byte cost limit of the decoded image cache, in bytes.
    ///
    /// Defaults to 64 MB. Cost is charged as `bytesPerRow * height`, and the cache evicts
    /// least-recently-used resources once the limit is exceeded. This setting is storage
    /// policy and does not participate in resource identity. Must be nonnegative; `0`
    /// disables decoded caching.
    public var decodedMemoryCapacity: Int

    /// The in-memory capacity of the client's `URLCache`, in bytes.
    ///
    /// Defaults to 32 MB. The cache still obeys server cache headers. This setting is
    /// storage policy and does not participate in resource identity. Must be nonnegative.
    public var httpMemoryCapacity: Int

    /// The on-disk capacity of the client's `URLCache`, in bytes.
    ///
    /// Defaults to 200 MB. The cache still obeys server cache headers. This setting is
    /// storage policy and does not participate in resource identity. Must be nonnegative.
    public var httpDiskCapacity: Int

    /// The behavior to use when Vision analysis fails.
    ///
    /// Defaults to ``FaceAwareAnalysisFailurePolicy/fallbackToCenter``. It participates in
    /// resource identity.
    public var analysisFailurePolicy: FaceAwareAnalysisFailurePolicy

    /// Creates a validated configuration.
    ///
    /// Every parameter has the documented default, so you can override only what differs.
    ///
    /// - Parameters:
    ///   - displayMaxPixelSize: The maximum decoded display dimension in pixels. Defaults
    ///     to `1600`. Precondition: must be positive.
    ///   - analysisMaxPixelSize: The maximum analysis thumbnail dimension in pixels.
    ///     Defaults to `768`. Precondition: must be positive.
    ///   - maximumWeightedFaceCount: The maximum number of faces that contribute to the
    ///     focal point. Defaults to `3`. Precondition: must be positive.
    ///   - decodedMemoryCapacity: The decoded image cache cost limit in bytes. Defaults to
    ///     64 MB. Precondition: must be nonnegative.
    ///   - httpMemoryCapacity: The HTTP memory cache capacity in bytes. Defaults to 32 MB.
    ///     Precondition: must be nonnegative.
    ///   - httpDiskCapacity: The HTTP disk cache capacity in bytes. Defaults to 200 MB.
    ///     Precondition: must be nonnegative.
    ///   - analysisFailurePolicy: The behavior when Vision analysis fails. Defaults to
    ///     ``FaceAwareAnalysisFailurePolicy/fallbackToCenter``.
    public init(
        displayMaxPixelSize: Int = 1600,
        analysisMaxPixelSize: Int = 768,
        maximumWeightedFaceCount: Int = 3,
        decodedMemoryCapacity: Int = 64 * 1024 * 1024,
        httpMemoryCapacity: Int = 32 * 1024 * 1024,
        httpDiskCapacity: Int = 200 * 1024 * 1024,
        analysisFailurePolicy: FaceAwareAnalysisFailurePolicy = .fallbackToCenter
    ) {
        precondition(displayMaxPixelSize > 0, "displayMaxPixelSize must be positive")
        precondition(analysisMaxPixelSize > 0, "analysisMaxPixelSize must be positive")
        precondition(maximumWeightedFaceCount > 0, "maximumWeightedFaceCount must be positive")
        precondition(decodedMemoryCapacity >= 0, "decodedMemoryCapacity must be nonnegative")
        precondition(httpMemoryCapacity >= 0, "httpMemoryCapacity must be nonnegative")
        precondition(httpDiskCapacity >= 0, "httpDiskCapacity must be nonnegative")

        self.displayMaxPixelSize = displayMaxPixelSize
        self.analysisMaxPixelSize = analysisMaxPixelSize
        self.maximumWeightedFaceCount = maximumWeightedFaceCount
        self.decodedMemoryCapacity = decodedMemoryCapacity
        self.httpMemoryCapacity = httpMemoryCapacity
        self.httpDiskCapacity = httpDiskCapacity
        self.analysisFailurePolicy = analysisFailurePolicy
    }
}

/// The behavior to use when Vision analysis fails.
public enum FaceAwareAnalysisFailurePolicy: Hashable, Sendable {
    /// Keep the image and use the `(0.5, 0.5)` image center as the focal point.
    ///
    /// This is the default. The request succeeds and reports
    /// ``FaceAwareFocusSource/imageCenter`` as its focus source, so imagery stays visible
    /// even when Vision is unavailable or fails.
    case fallbackToCenter

    /// Fail the whole request instead of rendering a different crop.
    ///
    /// The request throws ``FaceAwareImageError/analysisFailed(description:)``. Choose
    /// this when a wrong crop is worse than no image.
    case failRequest
}
