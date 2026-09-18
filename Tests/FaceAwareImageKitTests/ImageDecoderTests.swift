import XCTest
@testable import FaceAwareImageKit

final class ImageDecoderTests: XCTestCase {
    func testBoundsDisplayAndAnalysisThumbnailsToTheirRequestedPixelSizes() throws {
        let data = try GeneratedImageFixture.makePNGData()

        let decoded = try ImageDecoder.decode(
            data: data,
            displayMaxPixelSize: 1_200,
            analysisMaxPixelSize: 600
        )

        XCTAssertEqual(max(decoded.display.width, decoded.display.height), 1_200)
        XCTAssertEqual(max(decoded.analysis.width, decoded.analysis.height), 600)
    }

    func testRejectsBytesThatDoNotContainAnImage() {
        XCTAssertThrowsError(
            try ImageDecoder.decode(
                data: Data("not an image".utf8),
                displayMaxPixelSize: 1_200,
                analysisMaxPixelSize: 600
            )
        ) { error in
            guard case FaceAwareImageError.decodingFailed = error else {
                return XCTFail("Expected decodingFailed, got \(error)")
            }
        }
    }
}
