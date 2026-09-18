import CoreGraphics
import XCTest
@testable import FaceAwareImageKit

@MainActor
final class VisionAnalyzerPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VisionRequestObservation.reset()
    }

    func testFacesPreventAnySaliencyRequest() throws {
        let runner = StubVisionRequestRunner(
            faceResult: .success([CGRect(x: 0.2, y: 0.6, width: 0.2, height: 0.2)]),
            salientResult: .failure(.saliencyRequestWasUnexpected)
        )
        let analyzer = VisionAnalyzer(requestRunner: runner)

        let analysis = try analyzer.analyze(
            cgImage: GeneratedImageFixture.makeImage(),
            configuration: FaceAwareImageConfiguration()
        )

        XCTAssertEqual(analysis.focusSource, .face)
        XCTAssertEqual(VisionRequestObservation.saliencyCallCount, 0)
    }

    func testEmptyFacesTriggerExactlyOneSaliencyRequest() throws {
        let runner = StubVisionRequestRunner(
            faceResult: .success([]),
            salientResult: .success([CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)])
        )
        let analyzer = VisionAnalyzer(requestRunner: runner)

        let analysis = try analyzer.analyze(
            cgImage: GeneratedImageFixture.makeImage(),
            configuration: FaceAwareImageConfiguration()
        )

        XCTAssertEqual(analysis.focusSource, .salientObject)
        XCTAssertEqual(VisionRequestObservation.saliencyCallCount, 1)
    }

    func testVisionFailureFallsBackToCenterWhenConfigured() throws {
        let analyzer = VisionAnalyzer(
            requestRunner: StubVisionRequestRunner(
                faceResult: .failure(.requestFailed),
                salientResult: .success([])
            )
        )
        let configuration = FaceAwareImageConfiguration(analysisFailurePolicy: .fallbackToCenter)

        let analysis = try analyzer.analyze(
            cgImage: GeneratedImageFixture.makeImage(),
            configuration: configuration
        )

        XCTAssertEqual(analysis.focusSource, .imageCenter)
        XCTAssertEqual(analysis.focalPoint, CGPoint(x: 0.5, y: 0.5))
    }

    func testVisionFailureThrowsAnalysisFailedWhenConfigured() throws {
        let analyzer = VisionAnalyzer(
            requestRunner: StubVisionRequestRunner(
                faceResult: .failure(.requestFailed),
                salientResult: .success([])
            )
        )
        let configuration = FaceAwareImageConfiguration(analysisFailurePolicy: .failRequest)

        XCTAssertThrowsError(
            try analyzer.analyze(
                cgImage: GeneratedImageFixture.makeImage(),
                configuration: configuration
            )
        ) { error in
            guard case FaceAwareImageError.analysisFailed = error else {
                return XCTFail("Expected analysisFailed, got \(error)")
            }
        }
    }
}

private struct StubVisionRequestRunner: VisionRequestRunning {
    let faceResult: Result<[CGRect], StubVisionError>
    let salientResult: Result<[CGRect], StubVisionError>

    nonisolated func faceRegions(in image: CGImage) throws -> [CGRect] {
        try faceResult.get()
    }

    nonisolated func salientRegions(in image: CGImage) throws -> [CGRect] {
        MainActor.assumeIsolated {
            VisionRequestObservation.recordSaliencyRequest()
        }
        return try salientResult.get()
    }
}

private enum StubVisionError: Error, Sendable {
    case requestFailed
    case saliencyRequestWasUnexpected
}

@MainActor
private enum VisionRequestObservation {
    private static var recordedSaliencyCallCount = 0

    static var saliencyCallCount: Int {
        recordedSaliencyCallCount
    }

    static func reset() {
        recordedSaliencyCallCount = 0
    }

    static func recordSaliencyRequest() {
        recordedSaliencyCallCount += 1
    }
}
