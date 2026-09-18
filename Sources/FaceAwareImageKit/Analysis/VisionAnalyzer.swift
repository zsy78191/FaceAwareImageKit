import CoreGraphics
import Vision

protocol VisionRequestRunning: Sendable {
    func faceRegions(in image: CGImage) throws -> [CGRect]
    func salientRegions(in image: CGImage) throws -> [CGRect]
}

struct VisionAnalyzer {
    private let requestRunner: any VisionRequestRunning

    init(requestRunner: any VisionRequestRunning = SystemVisionRequestRunner()) {
        self.requestRunner = requestRunner
    }

    nonisolated func analyze(
        cgImage: CGImage,
        configuration: FaceAwareImageConfiguration
    ) throws -> FaceAwareImageAnalysis {
        do {
            let faceRegions = try requestRunner.faceRegions(in: cgImage)
            let salientRegions: [CGRect]
            if faceRegions.isEmpty {
                salientRegions = try requestRunner.salientRegions(in: cgImage)
            } else {
                salientRegions = []
            }

            return FocusResolver.resolve(
                faceRegions: faceRegions,
                salientRegions: salientRegions,
                maximumFaceCount: configuration.maximumWeightedFaceCount
            )
        } catch {
            switch configuration.analysisFailurePolicy {
            case .fallbackToCenter:
                return FocusResolver.resolve(
                    faceRegions: [],
                    salientRegions: [],
                    maximumFaceCount: configuration.maximumWeightedFaceCount
                )
            case .failRequest:
                throw FaceAwareImageError.analysisFailed(description: error.localizedDescription)
            }
        }
    }
}

private struct SystemVisionRequestRunner: VisionRequestRunning {
    nonisolated func faceRegions(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).map(\.boundingBox)
    }

    nonisolated func salientRegions(in image: CGImage) throws -> [CGRect] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results?.first?.salientObjects?.map(\.boundingBox) ?? []
    }
}
