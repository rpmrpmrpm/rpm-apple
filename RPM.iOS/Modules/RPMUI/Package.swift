// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMUI",
    // iOS alone, unlike the packages below it. This one is views: there is no macOS
    // build to keep working, and pretending otherwise would only mean writing around
    // UIKit for a test target that could not tell us anything a screen can.
    platforms: [.iOS(.v17)],
    products: [.library(name: "RPMUI", targets: ["RPMUI"])],
    dependencies: [
        .package(path: "../RPMKit"),
        .package(path: "../RPMLibrary"),
        .package(path: "../RPMDesign"),
        .package(path: "../RPMArt"),
        .package(path: "../RPMAudio"),
        // The speaker picker names real devices.
        .package(path: "../RPMCast"),
        .package(path: "../RPMRadio"),
        // The stage's measurement: the spectrum, the bands, the palette and the run.
        .package(path: "../RPMStages"),
        // The standings the pages are drawn from, which the TV reads too.
        .package(path: "../RPMSession"),
        // The room, the record, the wait mark and the spectrum, which the TV draws too.
        .package(path: "../RPMSharedUI"),
    ],
    targets: [
        .target(
            name: "RPMUI",
            dependencies: ["RPMKit", "RPMLibrary", "RPMDesign", "RPMArt", "RPMAudio",
                           "RPMCast", "RPMRadio", "RPMStages", "RPMSession", "RPMSharedUI"],
            // The label is the same file the desktop paints, not a new drawing.
            // The record itself is in RPMSharedUI. The brand font is here for the two
            // glyphs the sign-in buttons show, and it is registered at runtime rather
            // than declared in a plist.
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
