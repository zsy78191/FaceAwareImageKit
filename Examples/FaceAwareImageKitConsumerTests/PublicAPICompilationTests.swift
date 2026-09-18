import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
import FaceAwareImageKit

nonisolated final class PublicAPICompilationTests: XCTestCase {
    func testMemoryClearHasSynchronousActorIsolatedSignature() async {
        let client = FaceAwareImageClient(configuration: .init(httpDiskCapacity: 0))
        await clearSynchronously(client)
    }

    private func clearSynchronously(_ client: isolated FaceAwareImageClient) {
        let clear: () -> Void = client.clearMemoryCache
        clear()
    }

    func testSharedAndDefaultClientsArePublicActors() {
        func requireActor<T: Actor & Sendable>(_ actor: T) {}
        requireActor(FaceAwareImageClient.shared)
        XCTAssertTrue(FaceAwareImageClient.shared === FaceAwareImageClient.shared)
        XCTAssertFalse(FaceAwareImageClient() === FaceAwareImageClient.shared)
    }

    func testInvalidDataThrowsPublicDecodingError() async {
        let client = FaceAwareImageClient(configuration: .default)
        do {
            _ = try await client.analyze(data: Data([0, 1, 2]))
            XCTFail("Invalid image data must fail")
        } catch let error as FaceAwareImageError {
            switch error {
            case .decodingFailed: break
            default: XCTFail("Unexpected public error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLoadAndCacheControlsArePublic() async {
        let client = FaceAwareImageClient(configuration: .init(httpDiskCapacity: 0))
        let url = URL(fileURLWithPath: "/unsupported.png")
        do {
            _ = try await client.load(url: url)
            XCTFail("Non-HTTP URLs must fail without a network request")
        } catch let error as FaceAwareImageError {
            switch error {
            case .invalidURL: break
            default: XCTFail("Unexpected public error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        await client.clearMemoryCache()
        await client.clearDiskCache()
        await client.removeCachedResource(for: url)
    }

    func testBothAnalysisOverloadsHonorCustomConfiguration() async throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let image = try XCTUnwrap(context.makeImage())
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            encoded, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let client = FaceAwareImageClient(configuration: .init(displayMaxPixelSize: 16))
        let fromImage: FaceAwareImageResource = try await client.analyze(cgImage: image)
        let fromData: FaceAwareImageResource = try await client.analyze(data: encoded as Data)
        for resource in [fromImage, fromData] {
            XCTAssertEqual(resource.pixelSize, CGSize(width: 16, height: 8))
            XCTAssertEqual(resource.image.width, 16)
            XCTAssertEqual(resource.image.height, 8)
        }
    }

    // SwiftUI's `View` protocol is main-actor isolated, so consumers build views there.
    // The phase enum is public and non-frozen, so external consumers need @unknown default.
    @MainActor
    func testSwiftUIComponentsCompileForExternalConsumers() {
        let client = FaceAwareImageClient(configuration: .default)
        _ = FaceAwareAsyncImage(url: URL(string: "https://example.com/image.jpg"), client: client)
        _ = FaceAwareAsyncImageContent(url: nil, client: client) { phase in
            switch phase {
            case .empty: Color.gray
            case .success(let resource): FaceAwareImage(resource: resource)
            case .failure: Color.red
            @unknown default: Color.red
            }
        }
    }

    // MARK: - DocC guide examples
    //
    // Every code listing in `FaceAwareImageKit/Documentation.docc/FaceAwareImageKit.md`
    // appears below as an ordinary-import consumer test. Examples that stop compiling
    // fail this target instead of misleading a reader.

    @MainActor
    func testDocCGuideRendersRemoteImageWithDefaultClient() {
        func makeRemoteImageView(url: URL?) -> some View {
            FaceAwareAsyncImage(url: url)
                .frame(width: 320, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        _ = makeRemoteImageView(url: URL(string: "https://example.com/image.jpg"))
    }

    @MainActor
    func testDocCGuideRendersCustomPhases() {
        struct PhaseRenderingView: View {
            let url: URL?

            var body: some View {
                FaceAwareAsyncImageContent(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case let .success(resource):
                        FaceAwareImage(resource: resource)
                    case let .failure(error):
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                            Text(error.localizedDescription)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                    @unknown default:
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: 320, height: 200)
            }
        }

        _ = PhaseRenderingView(url: URL(string: "https://example.com/image.jpg"))
    }

    @MainActor
    func testDocCGuideRetainsOneCustomClientForListRows() {
        @MainActor
        final class FeedImageProvider {
            let client = FaceAwareImageClient(
                configuration: FaceAwareImageConfiguration(
                    displayMaxPixelSize: 1200,
                    analysisMaxPixelSize: 640,
                    maximumWeightedFaceCount: 2,
                    decodedMemoryCapacity: 32 * 1024 * 1024,
                    httpMemoryCapacity: 16 * 1024 * 1024,
                    httpDiskCapacity: 100 * 1024 * 1024,
                    analysisFailurePolicy: .fallbackToCenter
                )
            )
        }

        struct FeedRow: View {
            let url: URL?
            let provider: FeedImageProvider

            var body: some View {
                FaceAwareAsyncImage(url: url, client: provider.client)
                    .frame(height: 180)
            }
        }

        let provider = FeedImageProvider()
        _ = FeedRow(url: URL(string: "https://example.com/image.jpg"), provider: provider)
    }

    func testDocCGuideLoadsAndAnalyzesThroughCustomClients() async throws {
        func resource(for url: URL) async throws -> FaceAwareImageResource {
            let client = FaceAwareImageClient()
            return try await client.load(url: url)
        }

        func analyzeImageData(_ data: Data) async throws -> FaceAwareImageResource {
            let client = FaceAwareImageClient(configuration: .default)
            return try await client.analyze(data: data)
        }

        func analyzeImage(_ image: CGImage) async throws -> FaceAwareImageResource {
            let client = FaceAwareImageClient(configuration: .default)
            return try await client.analyze(cgImage: image)
        }

        // Compilation is the contract; a non-HTTP URL cannot reach the network.
        _ = resource
        _ = analyzeImageData
        _ = analyzeImage
    }

    func testDocCGuideReadsEveryResourceComponent() async throws {
        func inspect(_ data: Data) async throws {
            let resource = try await FaceAwareImageClient.shared.analyze(data: data)
            let focalPoint: CGPoint = resource.analysis.focalPoint
            let source: FaceAwareFocusSource = resource.analysis.focusSource
            let size: CGSize = resource.pixelSize
            let image: CGImage = resource.image
            print(focalPoint, source, size, image)
        }

        _ = inspect
    }

    func testDocCGuideSwitchesOnFocusSource() {
        func describe(_ resource: FaceAwareImageResource) -> String {
            switch resource.analysis.focusSource {
            case .face:
                return "Centered on \(resource.analysis.faceCount) face(s)"
            case .salientObject:
                return "Centered on the largest of \(resource.analysis.salientObjectCount) object(s)"
            case .imageCenter:
                return "No subject detected; centered the image"
            @unknown default:
                return "Unknown focus source"
            }
        }

        _ = describe
    }

    func testDocCGuideConfiguresCapacityAndAnalysisPolicy() {
        let configuration = FaceAwareImageConfiguration(
            displayMaxPixelSize: 1600,
            analysisMaxPixelSize: 768,
            maximumWeightedFaceCount: 3,
            decodedMemoryCapacity: 64 * 1024 * 1024,
            httpMemoryCapacity: 32 * 1024 * 1024,
            httpDiskCapacity: 200 * 1024 * 1024,
            analysisFailurePolicy: .fallbackToCenter
        )
        let client = FaceAwareImageClient(configuration: configuration)
        XCTAssertTrue(client !== FaceAwareImageClient.shared)
        XCTAssertEqual(configuration.analysisFailurePolicy, .fallbackToCenter)
        XCTAssertNotEqual(configuration.analysisFailurePolicy, .failRequest)
    }

    func testDocCGuideControlsEachCacheLayer() async {
        let client = FaceAwareImageClient(configuration: .init(httpDiskCapacity: 0))
        let url = URL(string: "https://example.com/image.jpg")!
        await clearEachCacheLayer(client, url: url)
    }

    func testDocCGuideHandlesEveryPublicError() async {
        func loadShowingErrors(
            url: URL,
            client: FaceAwareImageClient,
            showMessage: (String) -> Void,
            use: (FaceAwareImageResource) -> Void
        ) async {
            do {
                let resource = try await client.load(url: url)
                use(resource)
            } catch let error as FaceAwareImageError {
                switch error {
                case .invalidURL:
                    showMessage("That image URL is not valid.")
                case let .unacceptableStatusCode(statusCode):
                    showMessage("The server responded with status \(statusCode).")
                case let .network(description):
                    showMessage("Network problem: \(description)")
                case .decodingFailed:
                    showMessage("The image data could not be decoded.")
                case let .analysisFailed(description):
                    showMessage("Analysis failed: \(description)")
                case .cancelled:
                    break // Expected while scrolling or when a view disappears.
                @unknown default:
                    showMessage(error.localizedDescription)
                }
            } catch {
                showMessage(error.localizedDescription)
            }
        }

        // A non-HTTP URL fails with `.invalidURL` without touching the network.
        var messages: [String] = []
        await loadShowingErrors(
            url: URL(fileURLWithPath: "/unsupported.png"),
            client: FaceAwareImageClient(configuration: .init(httpDiskCapacity: 0)),
            showMessage: { messages.append($0) },
            use: { _ in XCTFail("A non-HTTP URL must not load") }
        )
        XCTAssertEqual(messages, ["That image URL is not valid."])
    }

    func testPublicValueAPIIsAccessible() {
        let configuration = FaceAwareImageConfiguration(
            displayMaxPixelSize: 1200,
            analysisMaxPixelSize: 640,
            maximumWeightedFaceCount: 2,
            decodedMemoryCapacity: 16 * 1024 * 1024,
            httpMemoryCapacity: 8 * 1024 * 1024,
            httpDiskCapacity: 64 * 1024 * 1024,
            analysisFailurePolicy: .failRequest
        )
        XCTAssertEqual(configuration.displayMaxPixelSize, 1200)

        let analysis = FaceAwareImageAnalysis(
            focalPoint: CGPoint(x: 0.4, y: 0.3),
            focusSource: .face,
            faceCount: 2,
            salientObjectCount: 0
        )
        XCTAssertEqual(analysis.focusSource, .face)
    }
}

// MARK: - DocC guide helpers
//
// File-scope, exactly as the guide's cache listing shows them: a free function has no
// `self` to send into the client's isolation, so it compiles without a strict-concurrency
// diagnostic. `clearMemoryCache()` is deliberately synchronous, so it runs from inside the
// actor while the two clearing methods are awaited.
func clearEachCacheLayer(_ client: isolated FaceAwareImageClient, url: URL) async {
    // Synchronous: decoded resources are gone when this returns.
    client.clearMemoryCache()

    // Asynchronous: removes this client's HTTP response cache, memory and disk.
    await client.clearDiskCache()

    // URL-wide within this client: removes every cached variant and cancels matching work.
    await client.removeCachedResource(for: url)
}
