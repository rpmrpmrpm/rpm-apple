// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMStages",
    // macOS is included so the tests can run on a Mac: the analysis is arithmetic over a
    // window of samples, and it can be checked against a tone at a known frequency without
    // a phone, a speaker or a screen. The drawing cannot be checked this way, and it lives
    // in the app above this package.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMStages", targets: ["RPMStages"])],
    targets: [
        // **Optimised even in a debug build.**
        //
        // This package holds the arithmetic that three visualisers run on, and the plate
        // alone steps fifteen thousand grains through eight modes on every frame.
        // Unoptimised Swift needs about 28 ms for that, which is more than one frame, so
        // the picture runs too slowly in a debug build. The desktop and Android apps do not have
        // this problem: their C# is JIT-compiled with optimisation in every build
        // configuration.
        //
        // The code here is pure functions with tests, and is not stepped through in a
        // debugger, so optimising it costs nothing useful.
        .target(name: "RPMStages",
                swiftSettings: [.swiftLanguageMode(.v6),
                                .unsafeFlags(["-O"], .when(configuration: .debug))]),
        .testTarget(name: "RPMStagesTests", dependencies: ["RPMStages"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
