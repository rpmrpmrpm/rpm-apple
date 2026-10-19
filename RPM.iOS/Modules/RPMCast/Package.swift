// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMCast",
    // macOS is included so that the rules which decide what a speaker is can be tested
    // without a simulator. Browsing needs a network and a phone, so its test says so.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMCast", targets: ["RPMCast"])],
    targets: [
        .target(name: "RPMCast", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "RPMCastTests", dependencies: ["RPMCast"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
