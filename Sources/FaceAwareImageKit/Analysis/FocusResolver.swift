import CoreGraphics

enum FocusResolver {
    nonisolated static func resolve(
        faceRegions: [CGRect],
        salientRegions: [CGRect],
        maximumFaceCount: Int
    ) -> FaceAwareImageAnalysis {
        if maximumFaceCount > 0, !faceRegions.isEmpty {
            let weightedFaces = faceRegions
                .sorted(by: largerArea)
                .prefix(maximumFaceCount)

            return FaceAwareImageAnalysis(
                focalPoint: weightedCenter(of: Array(weightedFaces)),
                focusSource: .face,
                faceCount: faceRegions.count,
                salientObjectCount: salientRegions.count
            )
        }

        if let largestObject = salientRegions.max(by: { area(of: $0) < area(of: $1) }) {
            return FaceAwareImageAnalysis(
                focalPoint: convertedCenter(of: largestObject),
                focusSource: .salientObject,
                faceCount: faceRegions.count,
                salientObjectCount: salientRegions.count
            )
        }

        return FaceAwareImageAnalysis(
            focalPoint: CGPoint(x: 0.5, y: 0.5),
            focusSource: .imageCenter,
            faceCount: faceRegions.count,
            salientObjectCount: salientRegions.count
        )
    }

    private nonisolated static func weightedCenter(of regions: [CGRect]) -> CGPoint {
        let totalArea = regions.reduce(CGFloat.zero) { partial, region in
            partial + max(area(of: region), .leastNonzeroMagnitude)
        }

        return regions.reduce(CGPoint.zero) { partial, region in
            let weight = max(area(of: region), .leastNonzeroMagnitude) / totalArea
            let center = convertedCenter(of: region)
            return CGPoint(
                x: partial.x + center.x * weight,
                y: partial.y + center.y * weight
            )
        }
    }

    private nonisolated static func convertedCenter(of region: CGRect) -> CGPoint {
        CGPoint(x: region.midX, y: 1 - region.midY)
    }

    private nonisolated static func largerArea(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        area(of: lhs) > area(of: rhs)
    }

    private nonisolated static func area(of region: CGRect) -> CGFloat {
        region.width * region.height
    }
}
