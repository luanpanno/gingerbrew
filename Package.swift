// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Gingerbrew",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Gingerbrew", targets: ["Gingerbrew"]),
    ],
    targets: [
        // Homebrew CLI wrapper, JSON parsing, search index. No UI code.
        .target(name: "GingerbrewCore"),
        // The SwiftUI menu bar app.
        .executableTarget(name: "Gingerbrew", dependencies: ["GingerbrewCore"]),
        .testTarget(name: "GingerbrewCoreTests", dependencies: ["GingerbrewCore"]),
    ]
)
