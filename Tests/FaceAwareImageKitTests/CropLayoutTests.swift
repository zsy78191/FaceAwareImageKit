import CoreGraphics
import XCTest
@testable import FaceAwareImageKit

final class CropLayoutTests: XCTestCase {
    func testSquareImageAndContainerNeedNoCrop() {
        let layout = CropLayout(
            imageSize: CGSize(width: 400, height: 400),
            containerSize: CGSize(width: 200, height: 200),
            focalPoint: CGPoint(x: 0.5, y: 0.5)
        )

        XCTAssertEqual(layout.renderedSize, CGSize(width: 200, height: 200))
        XCTAssertEqual(layout.offset, .zero)
    }

    func testPortraitImageFillsLandscapeContainer() {
        let layout = CropLayout(
            imageSize: CGSize(width: 400, height: 800),
            containerSize: CGSize(width: 400, height: 200),
            focalPoint: CGPoint(x: 0.5, y: 0.2)
        )

        XCTAssertEqual(layout.renderedSize.width, 400, accuracy: 0.001)
        XCTAssertEqual(layout.renderedSize.height, 800, accuracy: 0.001)

        let overflow = layout.renderedSize.height - 200
        XCTAssertEqual(layout.offset.y, -60, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.offset.y, -overflow)
        XCTAssertLessThanOrEqual(layout.offset.y, 0)
    }

    func testLandscapeImageFillsPortraitContainer() {
        let layout = CropLayout(
            imageSize: CGSize(width: 800, height: 400),
            containerSize: CGSize(width: 200, height: 400),
            focalPoint: CGPoint(x: 0.2, y: 0.5)
        )

        XCTAssertEqual(layout.renderedSize.width, 800, accuracy: 0.001)
        XCTAssertEqual(layout.renderedSize.height, 400, accuracy: 0.001)

        let overflow = layout.renderedSize.width - 200
        XCTAssertEqual(layout.offset.x, -60, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.offset.x, -overflow)
        XCTAssertLessThanOrEqual(layout.offset.x, 0)
    }

    func testFocalPointsAtEveryEdgeStayWithinLegalOffsets() {
        let imageSize = CGSize(width: 1200, height: 800)
        let containerSize = CGSize(width: 400, height: 400)
        let renderedSize = CGSize(width: 600, height: 400)
        let overflow = CGSize(width: 200, height: 0)

        for focalPoint in [
            CGPoint(x: 0.0, y: 0.5),
            CGPoint(x: 1.0, y: 0.5),
            CGPoint(x: 0.5, y: 0.0),
            CGPoint(x: 0.5, y: 1.0)
        ] {
            let layout = CropLayout(
                imageSize: imageSize,
                containerSize: containerSize,
                focalPoint: focalPoint
            )

            XCTAssertGreaterThanOrEqual(layout.renderedSize.width, containerSize.width)
            XCTAssertGreaterThanOrEqual(layout.renderedSize.height, containerSize.height)
            XCTAssertEqual(layout.renderedSize.width, renderedSize.width, accuracy: 0.001)
            XCTAssertEqual(layout.renderedSize.height, renderedSize.height, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(layout.offset.x, -overflow.width)
            XCTAssertLessThanOrEqual(layout.offset.x, 0)
            XCTAssertGreaterThanOrEqual(layout.offset.y, -overflow.height)
            XCTAssertLessThanOrEqual(layout.offset.y, 0)
        }
    }

    func testVerticallyOverflowingLayoutClampsTopAndBottomFocalPoints() {
        let imageSize = CGSize(width: 400, height: 800)
        let containerSize = CGSize(width: 400, height: 200)
        let topLayout = CropLayout(
            imageSize: imageSize,
            containerSize: containerSize,
            focalPoint: CGPoint(x: 0.5, y: 0.0)
        )
        let bottomLayout = CropLayout(
            imageSize: imageSize,
            containerSize: containerSize,
            focalPoint: CGPoint(x: 0.5, y: 1.0)
        )
        let overflowHeight = bottomLayout.renderedSize.height - containerSize.height

        XCTAssertEqual(topLayout.offset.y, 0, accuracy: 0.001)
        XCTAssertEqual(bottomLayout.offset.y, -overflowHeight, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(topLayout.offset.y, -overflowHeight)
        XCTAssertLessThanOrEqual(topLayout.offset.y, 0)
        XCTAssertGreaterThanOrEqual(bottomLayout.offset.y, -overflowHeight)
        XCTAssertLessThanOrEqual(bottomLayout.offset.y, 0)
    }

    func testWideContainerClipsWithoutEscapingOverflow() {
        let imageSize = CGSize(width: 1200, height: 800)
        let containerSize = CGSize(width: 390, height: 60)
        let layout = CropLayout(
            imageSize: imageSize,
            containerSize: containerSize,
            focalPoint: CGPoint(x: 0.85, y: 0.15)
        )

        let scale = max(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let expectedRenderedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let overflow = CGSize(
            width: expectedRenderedSize.width - containerSize.width,
            height: expectedRenderedSize.height - containerSize.height
        )

        XCTAssertGreaterThanOrEqual(layout.renderedSize.width, containerSize.width)
        XCTAssertGreaterThanOrEqual(layout.renderedSize.height, containerSize.height)
        XCTAssertGreaterThanOrEqual(layout.offset.x, -overflow.width)
        XCTAssertLessThanOrEqual(layout.offset.x, 0)
        XCTAssertGreaterThanOrEqual(layout.offset.y, -overflow.height)
        XCTAssertLessThanOrEqual(layout.offset.y, 0)
    }

    func testZeroContainerProducesZeroOffset() {
        let layout = CropLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: .zero,
            focalPoint: CGPoint(x: 0.25, y: 0.75)
        )

        XCTAssertEqual(layout.offset, .zero)
    }
}
