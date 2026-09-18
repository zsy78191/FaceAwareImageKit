import Foundation
import SwiftUI

/// A URL-driven view that loads, analyzes, and renders an image with automatic
/// focal-point aware aspect fill.
///
/// The view starts loading when it appears, reloads when `url` changes, and cancels
/// obsolete work when it disappears or the URL changes. It renders a `ProgressView` while
/// loading, a ``FaceAwareImage`` on success, and a neutral placeholder on failure. Use
/// ``FaceAwareAsyncImageContent`` to supply custom content for every phase.
///
/// The view is aspect filled and clipped to its bounds, so give it a size with ordinary
/// frame modifiers. Resizing only recalculates crop geometry.
public struct FaceAwareAsyncImage: View {
    private let url: URL?
    private let client: FaceAwareImageClient

    /// Creates a view that loads `url`.
    ///
    /// - Parameters:
    ///   - url: The remote image URL, or `nil` to show the placeholder. Changing it
    ///     cancels the previous load.
    ///   - client: The client that loads and caches the image. Defaults to
    ///     ``FaceAwareImageClient/shared``. Create a custom client once and pass it here
    ///     rather than constructing one during `body` evaluation.
    public init(url: URL?, client: FaceAwareImageClient = .shared) {
        self.url = url
        self.client = client
    }

    /// The default phase rendering.
    public var body: some View {
        FaceAwareAsyncImageContent(url: url, client: client) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case let .success(resource):
                FaceAwareImage(resource: resource)
            case .failure:
                Color.gray.opacity(0.2)
            }
        }
    }
}

/// A URL-driven view that hands each loading phase to a caller-supplied builder.
///
/// Use this view when the default placeholder and error rendering are not enough: the
/// builder receives every ``FaceAwareImagePhase`` value, so you can render your own
/// progress, success, and failure content.
///
/// The view retains the client it is given and never creates one, so client lifetime,
/// cache ownership, and in-flight deduplication stay under the caller's control.
public struct FaceAwareAsyncImageContent<Content: View>: View {
    private let url: URL?
    private let client: FaceAwareImageClient
    private let content: (FaceAwareImagePhase) -> Content

    @State private var phase: FaceAwareImagePhase = .empty
    @State private var mirror: AsyncImagePhaseMirror?

    /// Creates a view that loads `url` and renders each phase with `content`.
    ///
    /// - Parameters:
    ///   - url: The remote image URL, or `nil` to show the empty phase. Changing it
    ///     cancels the previous load.
    ///   - client: The client that loads and caches the image. Defaults to
    ///     ``FaceAwareImageClient/shared``. Create a custom client once and pass it here
    ///     rather than constructing one during `body` evaluation.
    ///   - content: A builder that maps each ``FaceAwareImagePhase`` to a view.
    public init(
        url: URL?,
        client: FaceAwareImageClient = .shared,
        @ViewBuilder content: @escaping (FaceAwareImagePhase) -> Content
    ) {
        self.url = url
        self.client = client
        self.content = content
    }

    /// The caller-supplied content for the current phase.
    ///
    /// The attached task starts a load when the view appears or `url` changes, and its
    /// cancellation when the view disappears releases the load.
    public var body: some View {
        content(phase)
            .task(id: url) {
                // The view mirrors the model instead of registering a stored callback:
                // a callback owned by the model would capture this view, and therefore
                // the `@State` storage that owns the model, for the process lifetime.
                let session = self.mirror ?? AsyncImagePhaseMirror(client: client)
                self.mirror = session
                session.begin()
                self.phase = session.phase
                await session.load(url: url)
                // Read the model's *current* phase: a superseded task that resumes
                // after cancellation must mirror the live value, never a stale one.
                self.phase = session.phase
            }
    }
}

/// Mirrors an ``AsyncImageModel`` into a view's `@State` without storing a
/// view-capturing callback in the model.
///
/// It is the whole of the async view's state handling, so a test can drive it with the
/// same sequencing `.task(id: url)` uses: empty before the await, the model's current
/// phase after it.
@MainActor
internal final class AsyncImagePhaseMirror {
    /// The phase the view should render.
    private(set) var phase: FaceAwareImagePhase = .empty

    /// The model the view drives. Internal so tests can assert the view path stores no
    /// callback; the underscore marks it as a test seam rather than API.
    let _model: AsyncImageModel

    init(client: any FaceAwareImageLoading) {
        _model = AsyncImageModel(client: client)
    }

    /// The phase a load starts from. The model clears its own phase at the same point,
    /// so the view never shows a previous load's result while the new one runs.
    func begin() {
        phase = .empty
    }

    /// Loads `url` and leaves the view mirroring whatever phase the model now holds.
    func load(url: URL?) async {
        await _model.load(url: url)
        phase = _model.phase
    }
}

/// The client seam the async views load through.
internal protocol FaceAwareImageLoading: Sendable {
    func load(url: URL) async throws -> FaceAwareImageResource
}

extension FaceAwareImageClient: FaceAwareImageLoading {}

/// Owns the request state of a ``FaceAwareAsyncImageContent``.
///
/// The model is created, driven, and observed on the main actor: the view mirrors
/// ``phase`` through ``AsyncImagePhaseMirror`` and awaits ``load(url:)`` from
/// `.task(id: url)`.
@MainActor
internal final class AsyncImageModel {
    private(set) var phase: FaceAwareImagePhase = .empty

    /// Reports every phase change on the main actor.
    ///
    /// The production view no longer assigns it — it reads ``phase`` after the await
    /// instead, so the model never stores a view-capturing closure. Kept as the
    /// internal seam the model tests drive.
    var onPhaseChange: (@MainActor (FaceAwareImagePhase) -> Void)?

    private let client: any FaceAwareImageLoading
    private var loadTask: Task<Void, Never>?

    init(client: any FaceAwareImageLoading) {
        self.client = client
    }

    /// Loads `url` and suspends until that work finishes.
    ///
    /// The model owns the in-flight task, so a URL change or a `nil` URL cancels the
    /// prior load. Cancellation of the awaiting caller — SwiftUI cancelling
    /// `.task(id: url)` when its view disappears or its id changes — is forwarded to
    /// that owned task, which is what releases the pipeline's waiter token.
    func load(url: URL?) async {
        loadTask?.cancel()
        loadTask = nil
        publish(.empty)
        guard let url else { return }
        let task = Task { [weak self] in
            await self?.loadResource(at: url)
            return ()
        }
        loadTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func loadResource(at url: URL) async {
        do {
            let resource = try await client.load(url: url)
            // A superseded load must not publish, even if the loader ignores cancellation.
            guard !Task.isCancelled else { return }
            publish(.success(resource))
        } catch {
            guard !Task.isCancelled else { return }
            publish(.failure((error as? FaceAwareImageError) ?? .network(description: error.localizedDescription)))
        }
    }

    private func publish(_ newPhase: FaceAwareImagePhase) {
        phase = newPhase
        onPhaseChange?(newPhase)
    }
}
