// swift-tools-version: 5.9
import PackageDescription

// Tools version 5.9 (rather than 6.0) keeps the package buildable on older
// toolchains such as the Swift 5.10 shipped on GitHub's macOS runners.
// Swift 5 language mode is the default here, which is what this code targets.
let package = Package(
    name: "CleanPDF",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CleanPDF",
            path: "Sources/CleanPDF"
        )
    ]
)
