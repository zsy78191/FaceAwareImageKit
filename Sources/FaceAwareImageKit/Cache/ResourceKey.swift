import Foundation

struct ResourceKey: Hashable, Sendable {
    let url: URL
    private let displayMaxPixelSize: Int
    private let analysisMaxPixelSize: Int
    private let maximumWeightedFaceCount: Int
    private let analysisFailurePolicy: FaceAwareAnalysisFailurePolicy

    init(url: URL, configuration: FaceAwareImageConfiguration) {
        self.url = Self.normalizedURL(url)
        displayMaxPixelSize = configuration.displayMaxPixelSize
        analysisMaxPixelSize = configuration.analysisMaxPixelSize
        maximumWeightedFaceCount = configuration.maximumWeightedFaceCount
        analysisFailurePolicy = configuration.analysisFailurePolicy
    }

    static func normalizedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.fragment = nil
        return components.url ?? url
    }
}
