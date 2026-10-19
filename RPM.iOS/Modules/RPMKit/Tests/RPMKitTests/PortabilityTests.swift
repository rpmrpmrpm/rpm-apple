import Testing
import Foundation
@testable import RPMKit

/// The one rule that keeps this package testable off a simulator, enforced by
/// reading the sources rather than by hoping. A UI import compiles perfectly
/// well on iOS and simply stops the macOS test build, which is a failure that
/// looks like a toolchain problem rather than like the mistake it is.
///
/// It reads import STATEMENTS rather than searching the text, because the
/// comments in this repo talk about the rule they are under: a comment in
/// RPMKit.swift that explains why the import is banned would match a text search.
@Test func sourcesImportNoUIFramework() throws {
    let banned: Set<String> = ["UIKit", "SwiftUI", "AppKit"]

    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // RPMKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // RPMKit
        .appendingPathComponent("Sources/RPMKit")

    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }

    #expect(!files.isEmpty, "no sources found, the path in this test is wrong")

    for file in files {
        for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { continue }

            let module = trimmed
                .dropFirst("import ".count)
                .trimmingCharacters(in: .whitespaces)
                .split(separator: ".").first.map(String.init) ?? ""

            #expect(
                !banned.contains(module),
                "\(file.lastPathComponent) imports \(module); RPMKit stays free of UI frameworks"
            )
        }
    }
}
