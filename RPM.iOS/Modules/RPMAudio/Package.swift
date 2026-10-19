// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMAudio",
    // macOS is listed so the tests can run on a Mac without a phone. The levelling is
    // arithmetic and the queue is bookkeeping: both fail silently when wrong, and both can be
    // checked in seconds.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMAudio", targets: ["RPMAudio"])],
    dependencies: [
        .package(path: "../RPMKit"),
        .package(path: "../RPMLibrary"),
        // The player also plays radio stations, which are not tracks.
        .package(path: "../RPMRadio"),
        // Casting is a sink on this engine, not a separate player, so the player owns it.
        .package(path: "../RPMCast"),
    ],
    targets: [
        .target(
            name: "RPMAudio",
            dependencies: ["RPMKit", "RPMLibrary", "RPMRadio", "RPMCast"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RPMAudioTests",
            dependencies: ["RPMAudio", "RPMKit", "RPMLibrary", "RPMRadio", "RPMCast"],
            // Three seconds of a 440 Hz tone, encoded the way the store encodes it (AAC in an
            // MP4), so the decoder is tested against real bytes.
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
