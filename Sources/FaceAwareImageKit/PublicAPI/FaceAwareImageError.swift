import Foundation

/// A stable, framework-owned failure from a loading or analysis request.
///
/// Foundation and Vision errors are converted internally, so public API never exposes an
/// implementation-specific error type. Every request failure is one of these cases, and
/// `localizedDescription` is provided for presentation.
public enum FaceAwareImageError: Error, LocalizedError, Sendable {
    /// The URL cannot be loaded.
    ///
    /// Only HTTP and HTTPS URLs are supported; a file URL or a URL without a supported
    /// scheme produces this case without touching the network.
    case invalidURL

    /// The server responded with a status code the framework does not accept.
    ///
    /// - Parameter statusCode: The HTTP status code the server returned.
    case unacceptableStatusCode(Int)

    /// The transfer failed for a reason other than an unacceptable status code.
    ///
    /// - Parameter description: A human-readable description of the underlying failure.
    case network(description: String)

    /// The response body could not be decoded as an image.
    case decodingFailed

    /// Vision analysis failed and the configuration requested
    /// ``FaceAwareAnalysisFailurePolicy/failRequest``.
    ///
    /// With the default ``FaceAwareAnalysisFailurePolicy/fallbackToCenter`` policy, a
    /// failed analysis does not produce this error; the request succeeds with
    /// ``FaceAwareFocusSource/imageCenter`` instead.
    ///
    /// - Parameter description: A human-readable description of the underlying failure.
    case analysisFailed(description: String)

    /// The request was cancelled before it produced a resource.
    ///
    /// This is expected behavior. It usually means the requesting view disappeared or its
    /// URL changed, and it should not be presented to the user as an error.
    case cancelled

    /// A localized description of the failure, suitable for display.
    ///
    /// Provided by conforming to `LocalizedError`.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The image URL is invalid."
        case let .unacceptableStatusCode(statusCode):
            "The server returned an unacceptable status code: \(statusCode)."
        case let .network(description):
            "The network request failed: \(description)"
        case .decodingFailed:
            "The image data could not be decoded."
        case let .analysisFailed(description):
            "Image analysis failed: \(description)"
        case .cancelled:
            "The image request was cancelled."
        }
    }
}
