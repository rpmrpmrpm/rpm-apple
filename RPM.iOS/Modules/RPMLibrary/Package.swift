// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMLibrary",
    // macOS is listed for the same reason as in RPMKit: the code here is logic that a
    // screenshot cannot check, and it can be tested in seconds because it builds
    // without a simulator.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMLibrary", targets: ["RPMLibrary"])],
    dependencies: [.package(path: "../RPMKit")],
    targets: [
        .target(
            name: "RPMLibrary",
            dependencies: ["RPMKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RPMLibraryTests",
            dependencies: ["RPMLibrary", "RPMKit"],
            // Two seconds of a tone, E-AC-3 in an MPEG-4 file, so the check of a downloaded
            // original is tested against real bytes.
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
