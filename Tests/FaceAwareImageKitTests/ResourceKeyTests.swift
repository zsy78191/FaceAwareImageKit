import Foundation
import XCTest
@testable import FaceAwareImageKit

final class ResourceKeyTests: XCTestCase {
    func testKeyChangesWhenURLChanges() {
        let configuration = FaceAwareImageConfiguration()

        XCTAssertNotEqual(
            ResourceKey(url: URL(string: "https://example.com/images/one.png")!, configuration: configuration),
            ResourceKey(url: URL(string: "https://example.com/images/two.png")!, configuration: configuration)
        )
    }

    func testKeyChangesForEachOutputAffectingConfigurationValue() {
        let url = URL(string: "https://example.com/images/portrait.png")!
        let baseline = ResourceKey(url: url, configuration: FaceAwareImageConfiguration())

        XCTAssertNotEqual(
            baseline,
            ResourceKey(url: url, configuration: FaceAwareImageConfiguration(displayMaxPixelSize: 1_599))
        )
        XCTAssertNotEqual(
            baseline,
            ResourceKey(url: url, configuration: FaceAwareImageConfiguration(analysisMaxPixelSize: 767))
        )
        XCTAssertNotEqual(
            baseline,
            ResourceKey(url: url, configuration: FaceAwareImageConfiguration(maximumWeightedFaceCount: 2))
        )
        XCTAssertNotEqual(
            baseline,
            ResourceKey(url: url, configuration: FaceAwareImageConfiguration(analysisFailurePolicy: .failRequest))
        )
    }

    func testKeyIgnoresCacheCapacityConfigurationValues() {
        let url = URL(string: "https://example.com/images/portrait.png")!

        XCTAssertEqual(
            ResourceKey(url: url, configuration: FaceAwareImageConfiguration()),
            ResourceKey(
                url: url,
                configuration: FaceAwareImageConfiguration(
                    decodedMemoryCapacity: 1,
                    httpMemoryCapacity: 2,
                    httpDiskCapacity: 3
                )
            )
        )
    }

    func testKeyRemovesURLFragmentAndPreservesQuery() {
        let configuration = FaceAwareImageConfiguration()
        let withFragment = ResourceKey(
            url: URL(string: "https://example.com/images/portrait.png?width=400&mode=crop#preview")!,
            configuration: configuration
        )
        let withoutFragment = ResourceKey(
            url: URL(string: "https://example.com/images/portrait.png?width=400&mode=crop")!,
            configuration: configuration
        )

        XCTAssertEqual(withFragment, withoutFragment)
        XCTAssertEqual(withFragment.url.absoluteString, "https://example.com/images/portrait.png?width=400&mode=crop")
    }
}
