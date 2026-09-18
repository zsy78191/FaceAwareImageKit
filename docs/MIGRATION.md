# Migration guide

## From in-repo framework to SwiftPM package

1. Replace the in-repo `FaceAwareImageKit.framework` dependency in your app target with the SwiftPM package (see `README.md`).
2. `import FaceAwareImageKit` is unchanged — the product name is the same as the framework name.
3. Construct a `FaceAwareImageClient` once and retain it (e.g. on an `@Observable` app state object). Do not allocate a client inside SwiftUI `body`.
4. Deployment target stays iOS 15.0. If your app targets an older OS you must drop FaceAwareImageKit.

## From 1.0.0 (future)

Reserved. The 1.x line preserves binary compatibility via `@frozen`-free public types and locked Swift tools version 5.9.