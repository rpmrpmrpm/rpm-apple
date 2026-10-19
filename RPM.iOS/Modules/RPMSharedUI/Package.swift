// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMSharedUI",
    // Views that the iPhone and Apple TV apps draw the same way: the room behind the music, the
    // record and its pressing, the spinning-record wait mark, the spectrum and a station's logo
    // on its background. Each app lays out its own screens around them.
    platforms: [.iOS(.v17), .tvOS(.v17)],
    products: [.library(name: "RPMSharedUI", targets: ["RPMSharedUI"])],
    dependencies: [
        .package(path: "../RPMKit"),
        .package(path: "../RPMDesign"),
        .package(path: "../RPMArt"),
        .package(path: "../RPMAudio"),
        .package(path: "../RPMRadio"),
        .package(path: "../RPMStages"),
        .package(path: "../RPMLibrary"),
    ],
    targets: [
        .target(
            name: "RPMSharedUI",
            dependencies: ["RPMKit", "RPMDesign", "RPMArt", "RPMAudio", "RPMRadio", "RPMStages", "RPMLibrary"],
            // The record and the list frame use the same resource files as the desktop app.
            // Cabin Bold is the font the list frame is lettered in.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
