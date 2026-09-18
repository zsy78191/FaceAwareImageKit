import XCTest
@testable import FaceAwareImageKit

final class ConfigurationTests: XCTestCase {
    func testDefaultConfigurationMatchesDocumentedLimits() {
        let value = FaceAwareImageConfiguration.default
        XCTAssertEqual(value.displayMaxPixelSize, 1600)
        XCTAssertEqual(value.analysisMaxPixelSize, 768)
        XCTAssertEqual(value.maximumWeightedFaceCount, 3)
        XCTAssertEqual(value.decodedMemoryCapacity, 64 * 1024 * 1024)
        XCTAssertEqual(value.httpMemoryCapacity, 32 * 1024 * 1024)
        XCTAssertEqual(value.httpDiskCapacity, 200 * 1024 * 1024)
        XCTAssertEqual(value.analysisFailurePolicy, .fallbackToCenter)
    }
}
