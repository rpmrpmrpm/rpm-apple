// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RPMKit",
    // The locale files in `Sources/RPMKit/Strings/<loc>.lproj` are generated from
    // `scripts/strings.json`, the same table the desktop app reads. English is the
    // fallback for any language the phone does not have.
    defaultLocalization: "en",
    // macOS is listed so the tests run without a simulator. The app does not ship for macOS.
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "RPMKit", targets: ["RPMKit"])],
    dependencies: [],
    targets: [
        .target(
            name: "RPMKit",
            // Generated, never hand-edited. See `Loc` and `scripts/gen_locales.py`. The licence
            // texts the About screen shows come from `scripts/gen_credits.py`.
            //
            // `Licenses` is copied, not processed. `.process` would flatten the folder into the
            // bundle root and remove the subfolder that `Credits.text(of:copyright:)` reads from.
            // `.txt` files need no processing anyway.
            resources: [.process("Strings"), .copy("Licenses")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RPMKitTests",
            dependencies: ["RPMKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
