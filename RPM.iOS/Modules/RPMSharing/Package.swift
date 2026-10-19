// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMSharing",
    // The client side of the home-network sharing protocol (desktop code: `RPM.Core/Sharing`).
    // It finds the computers that share, pairs with one, signs a session, reads its catalogue and
    // merges it into the cloud's tracks. It only reads and never serves. macOS is listed so the
    // encodings can be tested without a simulator.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMSharing", targets: ["RPMSharing"])],
    dependencies: [.package(path: "../RPMKit")],
    targets: [
        .target(name: "RPMSharing", dependencies: ["RPMKit"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "RPMSharingTests", dependencies: ["RPMSharing", "RPMKit"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
