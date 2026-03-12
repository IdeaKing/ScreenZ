// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenZ",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenZ",
            // SPM recursively finds all .swift files under Sources/
            path: "Sources",
            swiftSettings: [
                // Use Swift 5 concurrency model so CGEvent C-callback bridging
                // compiles without strict-concurrency errors.
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
