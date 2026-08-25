// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanPDF",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CleanPDF",
            path: "Sources/CleanPDF",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
