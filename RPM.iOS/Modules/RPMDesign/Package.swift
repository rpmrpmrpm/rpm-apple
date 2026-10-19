// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMDesign",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMDesign", targets: ["RPMDesign"])],
    dependencies: [],
    targets: [
        .target(name: "RPMDesign", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "RPMDesignTests", dependencies: ["RPMDesign"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
