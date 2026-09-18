import CoreGraphics

/// A decoded image together with the analysis that says where its subject is.
///
/// Resources are produced by ``FaceAwareImageClient`` and are the input to
/// ``FaceAwareImage``. The framework constructs them; consumers read them. Keeping the
/// value opaque is what lets a resource be inserted into the cache only after decoding
/// and analysis have both completed.
public struct FaceAwareImageResource: Sendable {
    /// The decoded image, already downsampled to
    /// ``FaceAwareImageConfiguration/displayMaxPixelSize``.
    public let image: CGImage

    /// The pixel dimensions of ``image``.
    ///
    /// Use it to compute aspect ratios or to size custom UI. It is the size of the decoded
    /// image, not of the original network response.
    public let pixelSize: CGSize

    /// The analysis that selected the focal point for this image.
    public let analysis: FaceAwareImageAnalysis

    internal init(image: CGImage, pixelSize: CGSize, analysis: FaceAwareImageAnalysis) {
        self.image = image
        self.pixelSize = pixelSize
        self.analysis = analysis
    }
}
