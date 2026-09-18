/// The state of a focal-point aware asynchronous image request.
///
/// ``FaceAwareAsyncImageContent`` hands this value to its content builder, so a consumer
/// can render a placeholder, the analyzed image, or an error without managing the request.
///
/// The enum is not frozen, so external consumers must include an `@unknown default`
/// branch in an exhaustive switch.
public enum FaceAwareImagePhase {
    /// No image is available yet.
    ///
    /// This is the initial phase and the phase a view returns to when its URL changes or
    /// becomes `nil`.
    case empty

    /// The image loaded and analyzed successfully.
    ///
    /// - Parameter resource: The decoded image, its pixel size, and its resolved analysis.
    case success(FaceAwareImageResource)

    /// The image could not be produced.
    ///
    /// A ``FaceAwareImageError/cancelled`` failure is expected when a view disappears or
    /// its URL changes, and should not be presented as an error.
    ///
    /// - Parameter error: The framework error that stopped the request.
    case failure(FaceAwareImageError)
}
