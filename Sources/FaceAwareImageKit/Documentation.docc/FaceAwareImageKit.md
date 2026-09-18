# ``FaceAwareImageKit``

Load, cache, analyze, and render remote images with automatic face-aware or
salient-object focal-point cropping.

## Overview

`FaceAwareImageKit` is an iOS dynamic framework that owns the complete remote-image
pipeline: downloading over `URLSession`, HTTP and decoded-image caching, ImageIO
downsampling, Vision analysis, focal-point selection, and aspect-fill cropping.

It offers two levels of use:

- `FaceAwareAsyncImage` and `FaceAwareAsyncImageContent` render a URL directly, with
  automatic aspect-fill cropping around the detected subject.
- `FaceAwareImageClient` exposes the loading and analysis work so you can build your
  own UI from the resulting `FaceAwareImageResource`.

Vision, networking, decoding, cache storage, and crop mathematics stay internal. The
public surface is exactly the set of types documented here.

## Requirements

| Requirement | Minimum |
| --- | --- |
| Framework version | 1.0.0 |
| iOS / iPadOS | 15.0 |
| Swift | 5.9 |
| Xcode | 15.0 |
| XcodeGen | 2.46.0 |

The Swift and Xcode minimums above are the cost of **building the framework from
source**: the project declares `SWIFT_VERSION = 5.0` and targets iOS 15, so any Swift
5.9 / Xcode 15 toolchain can compile it. They are not a floor for **consuming the
prebuilt binary** — this checkout's framework was emitted by a newer compiler
(Swift 6.3.3, Xcode 26), and what a consumer needs for that binary is module stability.

The framework uses only system frameworks — SwiftUI, UIKit, Vision, ImageIO,
CoreGraphics, and Foundation — and has no third-party dependencies. Version 1.0
supports iOS and iPadOS only; macOS, tvOS, watchOS, and visionOS are not supported.

The framework is a dynamic library built with module stability
(`BUILD_LIBRARY_FOR_DISTRIBUTION = YES`), so a consumer compiled with a compatible
later Swift compiler can import it without recompiling the framework.

## Add the framework to a target

Declare the framework in `project.yml` with the settings the release requires, and
let each consumer link it:

```yaml
targets:
  FaceAwareImageKit:
    type: framework
    platform: iOS
    deploymentTarget: "15.0"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.hanxianfeng.FaceAwareImageKit
        PRODUCT_NAME: FaceAwareImageKit
        DEFINES_MODULE: YES
        MACH_O_TYPE: mh_dylib
        BUILD_LIBRARY_FOR_DISTRIBUTION: YES
        SKIP_INSTALL: YES
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.0"
        SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated

  YourApp:
    type: application
    platform: iOS
    dependencies:
      - target: FaceAwareImageKit
        link: true
        embed: true
```

`SWIFT_VERSION` and `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated` are not optional: a
project that sets a global `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` (as this one does)
would otherwise build a MainActor-isolated framework whose public API no longer matches
the shipped interface.

An application target must both link and embed the framework. Test targets link the
framework but do not embed a second copy; the test host supplies the built framework.
Then import the module normally:

```swift
import FaceAwareImageKit
```

## Render a remote image

`FaceAwareAsyncImage` is the one-line path. It starts loading when it appears,
re-renders when its URL changes, cancels obsolete work, and renders a `ProgressView`
while loading and a neutral placeholder on failure.

```swift
import SwiftUI
import FaceAwareImageKit

struct RemoteImageView: View {
    let url: URL?

    var body: some View {
        FaceAwareAsyncImage(url: url)
            .frame(width: 320, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

`FaceAwareImage` always behaves like aspect fill and clips content to its bounds. Size
it with ordinary frame or aspect-ratio modifiers. Changing its size only recalculates
crop geometry: resizing never downloads, decodes, or analyzes again.

## Render custom phases

Use `FaceAwareAsyncImageContent` when you need your own placeholder, progress, or
error presentation. The content builder receives every `FaceAwareImagePhase` value.

```swift
import SwiftUI
import FaceAwareImageKit

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
```

`FaceAwareImagePhase` is a non-frozen public enum. External consumers must include an
`@unknown default` branch so a future case never breaks their build.

## Use a retained custom client

`FaceAwareAsyncImage` and `FaceAwareAsyncImageContent` default to
`FaceAwareImageClient.shared`, which uses `FaceAwareImageConfiguration.default`.

Create a client once — in a feature object, dependency container, or `@StateObject` —
and pass it to every related view. A client owns its HTTP cache, decoded-image cache,
and in-flight work, so sharing one instance is what lets a list's rows reuse cache
entries and deduplicate simultaneous requests.

> Important: Never construct a client from a configuration inside `body`. Doing so
> creates a new, empty cache and a new `URLSession` on every evaluation and silently
> discards the configuration you intended to use.

```swift
import SwiftUI
import FaceAwareImageKit

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
```

## Create a client and analyze data

`FaceAwareImageClient` is an actor, so its loading and cache-control calls are `async`.
Use `load(url:)` for a remote image, or the analysis overloads for image data you
already have. All three return a `FaceAwareImageResource` with the decoded image, its
pixel size, and the resolved analysis. The one exception is ``clearMemoryCache()``,
which is synchronous but actor-isolated — see "Control the caches" below.

```swift
import CoreGraphics
import Foundation
import FaceAwareImageKit

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
```

Read the result to build your own UI:

```swift
import CoreGraphics
import Foundation
import FaceAwareImageKit

func inspect(_ data: Data) async throws {
    let resource = try await FaceAwareImageClient.shared.analyze(data: data)
    let focalPoint: CGPoint = resource.analysis.focalPoint
    let source: FaceAwareFocusSource = resource.analysis.focusSource
    let size: CGSize = resource.pixelSize
    let image: CGImage = resource.image
    print(focalPoint, source, size, image)
}
```

Analysis of caller-supplied `Data` or `CGImage` is not persisted. The HTTP and decoded
caches are keyed by URL, so an arbitrary image has no cache identity. Keep the returned
resource, or implement your own identity-based caching.

## Understand the focus source

`FaceAwareImageAnalysis.focalPoint` is normalized to `0...1` with a top-left origin,
matching SwiftUI's coordinate convention. Vision's lower-left normalized coordinates
are converted internally.

The framework resolves the focal point in this order:

1. If face rectangles exist, take up to `maximumWeightedFaceCount` of the largest by
   area and compute their area-weighted center. `focusSource` is `.face`.
2. Otherwise run objectness-based saliency. If regions exist, use the center of the
   largest one. `focusSource` is `.salientObject`.
3. Otherwise use `(0.5, 0.5)`. `focusSource` is `.imageCenter`.

```swift
func describeFocus(_ resource: FaceAwareImageResource) -> String {
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
```

A result with no faces is valid and expected — it is a successful analysis, not an
error. Face detection success skips saliency entirely.

## Configure behavior and cache sizes

`FaceAwareImageConfiguration` controls decode size, analysis size, and cache capacity.
Its initializer validates every value with `precondition`, which is active in both debug
and release builds: a nonpositive `displayMaxPixelSize`, `analysisMaxPixelSize`, or
`maximumWeightedFaceCount`, or a negative capacity, traps instead of producing undefined
cache behavior.

- `displayMaxPixelSize` (default 1600) bounds the decoded display image.
- `analysisMaxPixelSize` (default 768) bounds the separate Vision analysis thumbnail.
  Vision never analyzes the unbounded network image.
- `maximumWeightedFaceCount` (default 3) caps how many faces contribute to the focal
  point. It must be positive; `0` has no meaning because some face must contribute.
- `decodedMemoryCapacity` (default 64 MB) is the byte cost limit of the decoded-image
  cache, charged as `bytesPerRow * height`.
- `httpMemoryCapacity` (default 32 MB) and `httpDiskCapacity` (default 200 MB) size the
  `URLCache`, which still obeys server cache headers.
- `analysisFailurePolicy` decides what happens when Vision fails.

```swift
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
```

Resource identity — the key that decides whether a request is a cache hit — contains
the normalized URL, `displayMaxPixelSize`, `analysisMaxPixelSize`,
`maximumWeightedFaceCount`, and `analysisFailurePolicy`. Capacity settings are storage
policy only and do **not** participate in identity, so two clients that differ only in
capacity share the same resource keys.

A memory warning clears the client's decoded resources automatically.

## Control the caches

```swift
func clearEachCacheLayer(_ client: isolated FaceAwareImageClient, url: URL) async {
    // Synchronous: decoded resources are gone when this returns.
    client.clearMemoryCache()

    // Asynchronous: removes this client's HTTP response cache, memory and disk.
    await client.clearDiskCache()

    // URL-wide within this client: removes every cached variant and cancels matching work.
    await client.removeCachedResource(for: url)
}
```

```swift
let client = FaceAwareImageClient(configuration: .init(httpDiskCapacity: 0))
let url = URL(string: "https://example.com/image.jpg")!
await clearEachCacheLayer(client, url: url)
```

`clearMemoryCache()` is deliberately not `async`. It clears decoded resources
synchronously, and they are gone when the call returns. It is still actor-isolated, so a
caller outside the client must `await` it (which is why the example above does), and
that `await` is the only suspension: the work itself does not suspend and is complete
before the method returns, but a caller cannot treat the `await` expression as a
same-statement synchronous release the way the helper's body does. Code already inside
the client's isolation calls it as a plain synchronous call.

`clearDiskCache()` is asynchronous because it clears the client's own `URLCache`, whose
disk operations are suspended work. Each client owns a directory of its own under the
app's caches directory, so clearing or removing one client's entries never reaches
another client's cache or the host app's `URLCache.shared`. The framework sweeps
directories left behind by earlier launches each time it creates one, so the tree does
not grow without bound.

`removeCachedResource(for:)` is URL-wide, not key-exact. It removes every decoded
resource whose normalized URL matches, regardless of which configuration variant
produced it, and it cancels and invalidates matching in-flight work before removing
cached values. A task that races with the removal carries an invalidation generation,
so it cannot write its result back afterward. It also removes the HTTP cached response
for every normalized `URLRequest` variant the framework creates for that URL; it does
not promise removal of request variants created outside the framework, because
Foundation cannot enumerate every semantically equivalent cached request. Because
removal cancels matching in-flight work, a consumer waiting on that URL fails with
``FaceAwareImageError/cancelled`` — the phase contract for removal is the same as for a
view that scrolled away, not a failure to render.

Cache-hit provenance is intentionally not public. Foundation does not reliably expose
whether a response came from memory, disk, revalidation, or the network, so the
framework does not promise a value it cannot consistently determine.

## Handle errors

Every failure surfaces as a `FaceAwareImageError`. Foundation and Vision errors are
converted internally, so public API never depends on an implementation-specific error
type.

```swift
import Foundation
import FaceAwareImageKit

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
```

A `.cancelled` failure usually means the requesting view disappeared or changed URL.
Cancellation is expected behavior, not a defect, and it should not be presented as an
error to the user.

`FaceAwareAnalysisFailurePolicy` decides what a Vision failure means:

- `.fallbackToCenter` — the request still succeeds and reports `.imageCenter` as its
  focus source. This is the default and keeps images visible on devices where Vision
  is unavailable or fails.
- `.failRequest` — the request throws `.analysisFailed(description:)` instead. Choose
  this when a wrong crop is worse than no image.

## Concurrency and cancellation

`FaceAwareImageClient` is an actor, and its in-flight-task ownership and cache-control
entry points are actor-isolated. Decoded-resource storage is a separate matter: it is
lock-guarded inside the framework, so it is safe to mutate synchronously — which is what
``clearMemoryCache()`` does from its `nonisolated` implementation, and what a memory
warning triggers from the posting thread.

- Requests for the same resource key share one in-flight task.
- Changing the URL of a view cancels that view's wait immediately, and a `nil` URL
  cancels it too.
- Cancellation of a shared task's consumers is reference-counted: while another
  consumer still waits, the underlying work continues; when the last consumer stops
  waiting, the shared work is cancelled.
- A superseded load never publishes a stale result.

Because the client is an actor, safe sharing across tasks follows from the type; you
can hold one client in a `@MainActor` model and hand it to views freely.

## Performance guidance for scrolling lists

- Create one client for a screen or feed and pass it down. Per-row clients give every
  row its own cache and its own in-flight table.
- Give the view a fixed size before the image loads. Rows that change height on load
  cause the list to re-layout and stutter. A fixed frame keeps crop recalculation
  cheap and prevents layout thrash.
- Rely on the views' cancellation. SwiftUI cancels a row's task when it scrolls away,
  which stops obsolete downloads.
- Lower `displayMaxPixelSize` for thumbnails. A full-size decode costs memory and time
  that a small cell cannot show; a separate client for thumbnail size is appropriate,
  and its distinct configuration produces distinct resource keys.
- Prefer `.fallbackToCenter` for decorative imagery and `.failRequest` only where a
  confidently cropped image is required.
- Use `clearMemoryCache()` in response to memory pressure or a background transition
  when you want decoded pixels released immediately. The framework already clears
  decoded resources on a memory warning.

## Topics

### Essentials

- ``FaceAwareImageClient``
- ``FaceAwareImageConfiguration``

### Displaying images

- ``FaceAwareImage``
- ``FaceAwareAsyncImage``
- ``FaceAwareAsyncImageContent``
- ``FaceAwareImagePhase``

### Working with results

- ``FaceAwareImageResource``
- ``FaceAwareImageAnalysis``
- ``FaceAwareFocusSource``

### Handling failures

- ``FaceAwareImageError``
- ``FaceAwareAnalysisFailurePolicy``
