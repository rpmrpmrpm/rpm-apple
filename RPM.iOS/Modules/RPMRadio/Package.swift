// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMRadio",
    // macOS is here so the rules can be tested without a simulator. The other
    // packages below the UI do the same. Nothing in this one needs a phone: the
    // directory is HTTP and everything else is arithmetic over names.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMRadio", targets: ["RPMRadio"])],
    // The only route out of the app for this package. The directory is a third-party
    // service over HTTP. On a failure it tries every mirror in turn, so on a dead
    // network the radio tab spins for minutes. See `RPMKit/Net/Gated`.
    dependencies: [.package(path: "../RPMKit")],
    targets: [
        .target(name: "RPMRadio", dependencies: ["RPMKit"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "RPMRadioTests", dependencies: ["RPMRadio", "RPMKit"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
