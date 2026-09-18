import Foundation
import XCTest

/// Guards the migration to `FaceAwareImageKit`: the Lab must consume the framework
/// instead of carrying its own copy of the Vision, focal-point, image-pipeline, or
/// crop-layout implementation.
///
/// This is an XCTest rather than a run-script build phase because the project sets
/// `ENABLE_USER_SCRIPT_SANDBOXING: YES`, which makes a shell verification phase
/// fragile.
final class MigrationGuardTests: XCTestCase {
    // The last four literals catch a re-copied implementation. The framework's own
    // types are named `FocusResolver` and `VisionAnalyzer`; a Lab file that copied
    // them out would carry the `FaceAware`-prefixed declaration names below.
    private static let forbiddenPatterns = [
        "import Vision",
        "VNDetectFace",
        "VNGenerateObjectness",
        "struct FaceAwareCropLayout",
        "actor FaceAwareImagePipeline",
        "enum FaceAwareFocusResolver",
        "FaceAwareVisionAnalyzer"
    ]

    func testLabSourcesContainNoCopiedFrameworkImplementation() throws {
        let labDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FaceAwareImageLab", isDirectory: true)

        var swiftFiles: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: labDirectory, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                swiftFiles.append(file)
            }
        }

        XCTAssertFalse(
            swiftFiles.isEmpty,
            "No Lab sources found under \(labDirectory.path); the guard cannot verify the migration."
        )

        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for pattern in Self.forbiddenPatterns {
                XCTAssertFalse(
                    contents.contains(pattern),
                    "\(file.lastPathComponent) still contains \"\(pattern)\"; the Lab must use FaceAwareImageKit instead."
                )
            }
        }
    }
}
