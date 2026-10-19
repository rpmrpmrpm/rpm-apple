// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMSession",
    // The signed-in account's library as the phone and the TV both show it: the wall, home,
    // the playlists, the shares, the marks, the play counts, the lyrics and the station search.
    // No views. macOS is listed so the tests run without a simulator.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMSession", targets: ["RPMSession"])],
    dependencies: [
        .package(path: "../RPMKit"),
        .package(path: "../RPMLibrary"),
        .package(path: "../RPMArt"),
        .package(path: "../RPMAudio"),
        .package(path: "../RPMRadio"),
    ],
    targets: [
        .target(
            name: "RPMSession",
            dependencies: ["RPMKit", "RPMLibrary", "RPMArt", "RPMAudio", "RPMRadio"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RPMSessionTests",
            dependencies: ["RPMSession", "RPMKit", "RPMLibrary", "RPMRadio"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
