// swift-tools-version: 5.9
import PackageDescription

// Tools version 5.9 keeps the package readable by older toolchains; Swift 5
// language mode is the default here, which is what this code targets.
let package = Package(
    name: "CleanPDF",
    platforms: [.macOS(.v14)],
    targets: [
        // Thin C shim for the sandbox and process-accounting APIs that Swift
        // cannot import directly.
        .target(
            name: "CIsolation",
            path: "Sources/CIsolation"
        ),
        .executableTarget(
            name: "CleanPDF",
            dependencies: ["CIsolation"],
            path: "Sources/CleanPDF"
        ),
        .testTarget(
            name: "CleanPDFTests",
            dependencies: ["CleanPDF"],
            path: "tests/CleanPDFTests"
        ),
    ]
)
