import CoreGraphics

/// The result of analyzing an image for a focal point.
///
/// The analysis is produced by ``FaceAwareImageClient`` and describes both the point a
/// renderer should keep visible and the evidence that selected it.
public struct FaceAwareImageAnalysis: Equatable, Sendable {
    /// The normalized focal point to keep visible.
    ///
    /// The point uses SwiftUI's top-left origin convention, so `(0, 0)` is the image's
    /// top-left corner and `(1, 1)` is its bottom-right corner. Vision's lower-left
    /// normalized coordinates are converted internally before they reach this value.
    public let focalPoint: CGPoint

    /// The detector that produced ``focalPoint``.
    public let focusSource: FaceAwareFocusSource

    /// The number of faces Vision detected, before
    /// ``FaceAwareImageConfiguration/maximumWeightedFaceCount`` limits how many of them
    /// contribute to the focal point.
    ///
    /// A value of `0` is valid: it means no face was found and the framework fell back to
    /// saliency or to the image center.
    public let faceCount: Int

    /// The number of salient objects Vision detected.
    ///
    /// Saliency runs only when no face is found, so this is `0` whenever ``focusSource``
    /// is ``FaceAwareFocusSource/face``.
    public let salientObjectCount: Int

    /// Creates an analysis value.
    ///
    /// Consumers normally read analyses produced by ``FaceAwareImageClient``. This
    /// initializer exists for tools and tests that resolve a focal point themselves.
    /// - Parameters:
    ///   - focalPoint: The normalized focal point, using a top-left origin.
    ///   - focusSource: The detector that produced the focal point.
    ///   - faceCount: The number of detected faces.
    ///   - salientObjectCount: The number of detected salient objects.
    public init(
        focalPoint: CGPoint,
        focusSource: FaceAwareFocusSource,
        faceCount: Int,
        salientObjectCount: Int
    ) {
        self.focalPoint = focalPoint
        self.focusSource = focusSource
        self.faceCount = faceCount
        self.salientObjectCount = salientObjectCount
    }
}

/// The detector that produced an analysis focal point.
///
/// The framework tries these sources in order, so a case also tells you what evidence was
/// available: ``face`` means at least one face was found, ``salientObject`` means no face
/// was found but a salient object was, and ``imageCenter`` means neither detector
/// returned a region.
public enum FaceAwareFocusSource: String, Hashable, Sendable {
    /// The focal point is the area-weighted center of up to
    /// ``FaceAwareImageConfiguration/maximumWeightedFaceCount`` detected faces.
    case face

    /// No face was found, so the focal point is the center of the largest salient object.
    case salientObject

    /// Neither detector found a region, so the focal point is `(0.5, 0.5)`.
    case imageCenter
}
