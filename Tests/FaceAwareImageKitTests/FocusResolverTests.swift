import CoreGraphics
import XCTest
@testable import FaceAwareImageKit

final class FocusResolverTests: XCTestCase {
    func testUsesAreaWeightedTopThreeFaces() {
        let faces = [
            CGRect(x: 0.0, y: 0.6, width: 0.4, height: 0.4),
            CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2),
            CGRect(x: 0.5, y: 0.1, width: 0.1, height: 0.1),
            CGRect(x: 0.9, y: 0.0, width: 0.01, height: 0.01)
        ]

        let result = FocusResolver.resolve(faceRegions: faces, salientRegions: [], maximumFaceCount: 3)

        XCTAssertEqual(result.focusSource, .face)
        XCTAssertEqual(result.faceCount, 4)
        XCTAssertEqual(result.focalPoint.x, 0.331, accuracy: 0.001)
        XCTAssertEqual(result.focalPoint.y, 0.231, accuracy: 0.001)
    }

    func testUsesLargestSalientObjectWhenNoFaceExists() {
        let result = FocusResolver.resolve(
            faceRegions: [],
            salientRegions: [
                CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
                CGRect(x: 0.5, y: 0.2, width: 0.4, height: 0.3)
            ],
            maximumFaceCount: 3
        )

        XCTAssertEqual(result.focusSource, .salientObject)
        XCTAssertEqual(result.focalPoint, CGPoint(x: 0.7, y: 0.65))
        XCTAssertEqual(result.faceCount, 0)
        XCTAssertEqual(result.salientObjectCount, 2)
    }

    func testFallsBackToCenter() {
        let result = FocusResolver.resolve(faceRegions: [], salientRegions: [], maximumFaceCount: 3)

        XCTAssertEqual(result.focusSource, .imageCenter)
        XCTAssertEqual(result.focalPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(result.faceCount, 0)
        XCTAssertEqual(result.salientObjectCount, 0)
    }

    func testReportsAllDetectionsWhileWeightingOnlyConfiguredFacePrefix() {
        let result = FocusResolver.resolve(
            faceRegions: [
                CGRect(x: 0.0, y: 0.0, width: 0.8, height: 0.8),
                CGRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1)
            ],
            salientRegions: [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)],
            maximumFaceCount: 1
        )

        XCTAssertEqual(result.faceCount, 2)
        XCTAssertEqual(result.salientObjectCount, 1)
        XCTAssertEqual(result.focalPoint, CGPoint(x: 0.4, y: 0.6))
    }
}
