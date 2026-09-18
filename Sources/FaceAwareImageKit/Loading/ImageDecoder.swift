import CoreGraphics
import Foundation
import ImageIO

enum ImageDecoder {
    struct DecodedImages {
        let display: CGImage
        let analysis: CGImage
    }

    nonisolated static func decode(
        data: Data,
        displayMaxPixelSize: Int,
        analysisMaxPixelSize: Int
    ) throws -> DecodedImages {
        guard displayMaxPixelSize > 0, analysisMaxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let display = thumbnail(
                  from: source,
                  maxPixelSize: displayMaxPixelSize
              ),
              let analysis = thumbnail(
                  from: source,
                  maxPixelSize: analysisMaxPixelSize
              ) else {
            throw FaceAwareImageError.decodingFailed
        }

        return DecodedImages(display: display, analysis: analysis)
    }

    private nonisolated static func thumbnail(
        from source: CGImageSource,
        maxPixelSize: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
