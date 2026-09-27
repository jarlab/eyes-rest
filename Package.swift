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
        // OS signals: idle time, sleep/lock notifications, camera/mic in-use, sounds.
        .target(
            name: "EyeRestSystem",
            dependencies: ["EyeRestCore"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("IOKit"),
            ]
        ),
        // Windows and SwiftUI views: break overlay, heads-up, settings.
        .target(name: "EyeRestUI", dependencies: ["EyeRestCore"]),
        // The menu-bar app that wires everything together.
        .executableTarget(name: "EyeRest", dependencies: ["EyeRestCore", "EyeRestSystem", "EyeRestUI"]),
        .testTarget(name: "EyeRestCoreTests", dependencies: ["EyeRestCore"]),
    ]
)
