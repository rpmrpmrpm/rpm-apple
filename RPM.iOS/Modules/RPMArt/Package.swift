// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMArt",
    // macOS is listed too. ImageIO and CoreGraphics are the same frameworks on macOS and on
    // iOS, so decoding, downscaling and caching can be tested in seconds on a Mac, without a
    // simulator or a phone.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMArt", targets: ["RPMArt"])],
    dependencies: [
        .package(path: "../RPMKit"),
        .package(path: "../RPMLibrary"),
        .package(path: "../RPMDesign"),
    ],
    targets: [
        .target(
            name: "RPMArt",
            dependencies: ["RPMKit", "RPMLibrary", "RPMDesign"],
            // The generated playlist photographs, written by scripts/gen_playlist_photos_phone.py.
            // They are copied, not processed, so the folder keeps its name in the bundle and
            // `PlaylistPhotos` can find it.
            resources: [.copy("PlaylistPhotos")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RPMArtTests",
            dependencies: ["RPMArt", "RPMKit", "RPMLibrary", "RPMDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
