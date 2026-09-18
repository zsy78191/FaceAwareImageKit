# Changelog

All notable changes to FaceAwareImageKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-18

### Added
- Initial public release of `FaceAwareImageKit`.
- `FaceAwareImage` and `FaceAwareAsyncImage` SwiftUI views with aspect-fill focal-point aware cropping.
- `FaceAwareImageClient` actor with HTTP cache, decoded image cache, request deduplication, and generation-based cancellation.
- Vision-driven focal-point analysis with weighted faces, salient object fallback, and center fallback.
- Public configuration types: `FaceAwareImageConfiguration`, `FaceAwareImageAnalysis`, `FaceAwareImageResource`, `FaceAwareImageError`, `FaceAwareImagePhase`.
- DocC documentation bundle.
