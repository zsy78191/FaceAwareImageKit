import XCTest
@testable import FaceAwareImageLab

final class PresetImageCatalogTests: XCTestCase {
    func testCatalogContainsMultipleDetectionScenarios() {
        let categories = Set(PresetImageCatalog.all.map(\.category))

        XCTAssertTrue(categories.contains(.people))
        XCTAssertTrue(categories.contains(.animal))
        XCTAssertTrue(categories.contains(.object))
    }

    func testEveryPresetUsesASeparateSmallThumbnailURL() {
        for preset in PresetImageCatalog.all {
            XCTAssertNotEqual(preset.thumbnailURL, preset.imageURL)
            XCTAssertTrue(preset.thumbnailURL.absoluteString.contains("w=320"))
        }
    }
}
