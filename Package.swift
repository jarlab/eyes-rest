// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EyeRest",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EyeRest", targets: ["EyeRest"]),
    ],
    targets: [
        // Pure scheduling/settings logic. Foundation only, so it is unit-tested headlessly.
        .target(name: "EyeRestCore"),
        // Windows and SwiftUI views: the reminder card and Settings.
        .target(name: "EyeRestUI", dependencies: ["EyeRestCore"]),
        // The menu-bar app that wires everything together.
        .executableTarget(name: "EyeRest", dependencies: ["EyeRestCore", "EyeRestUI"]),
        .testTarget(name: "EyeRestCoreTests", dependencies: ["EyeRestCore"]),
    ]
)
