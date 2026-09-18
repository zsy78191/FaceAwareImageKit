import CoreGraphics
import Foundation
import ImageIO

actor PresetThumbnailPipeline {
    static let shared = PresetThumbnailPipeline()

    private let session: URLSession
    private var memory: [URL: CGImage] = [:]
    private var order: [URL] = []
    private let countLimit = 24

    init() {
        let cache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)
    }

    func load(_ url: URL) async throws -> CGImage {
        if let cached = memory[url] {
            touch(url)
            return cached
        }

        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let image = try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 400
                  ] as CFDictionary) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }.value

        memory[url] = image
        touch(url)
        evictIfNeeded()
        return image
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }

    private func evictIfNeeded() {
        while order.count > countLimit {
            memory.removeValue(forKey: order.removeFirst())
        }
    }
}
