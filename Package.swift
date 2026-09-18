// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FaceAwareImageKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "FaceAwareImageKit",
            targets: ["FaceAwareImageKit"]
        ),
    ],
    targets: [
        .target(
            name: "FaceAwareImageKit",
            path: "Sources/FaceAwareImageKit",
            resources: [
                .process("Documentation.docc"),
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
        .testTarget(
            name: "FaceAwareImageKitTests",
            dependencies: ["FaceAwareImageKit"],
            path: "Tests/FaceAwareImageKitTests"
        ),
    ]
)
