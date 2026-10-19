import Testing
import Foundation
@testable import RPMKit

/// The acknowledgements are the one screen where being wrong is a legal statement rather than a
/// visual fault, and nothing about being wrong shows up at runtime: a licence that did not ship
/// renders as a blank pane, a key that is not in the table renders as its own name, and both look
/// like an app that is merely a bit rough. These tests are what makes either of those loud.

@Test func everyLicenceAnEntryNamesExists() {
    for section in Credits.sections {
        for entry in section.entries {
            #expect(!entry.licenses.isEmpty,
                    "\(entry.name) is credited under no licence at all")

            for name in entry.licenses {
                #expect(Credits.licenses[name] != nil,
                        "\(entry.name) names the licence \(name), which is not in the map")
            }
        }
    }
}

@Test func everyLicenceTextShipped() {
    for (key, licence) in Credits.licenses {
        guard let file = licence.file else {
            // No text is only allowed for terms that are published rather than licensed, and those
            // have to point somewhere instead.
            #expect(licence.url != nil || anyEntryGivesTermsFor(key),
                    "\(key) ships no text and offers no address either")
            continue
        }

        // Credits.url, not Bundle.module: inside a test target that is the test's own bundle,
        // which has no licences in it and would fail this for the wrong reason.
        let url = Credits.url(of: file)

        #expect(url != nil, "\(key) names \(file), which is not in the bundle")

        if let url, let text = try? String(contentsOf: url, encoding: .utf8) {
            #expect(text.count > 200, "\(file) is too short to be a licence")
        }
    }
}

private func anyEntryGivesTermsFor(_ key: String) -> Bool {
    Credits.sections.contains { section in
        section.entries.contains { $0.licenses.contains(key) && $0.termsUrl != nil }
    }
}

@Test func everyStringKeyIsInTheTable() {
    for section in Credits.sections {
        // Loc answers a missing key with the key itself, which is exactly the shape of the bug
        // this is here to catch: a heading reading "Credits_Section_Lettering" on screen.
        #expect(Loc.get(section.title) != section.title,
                "\(section.title) is not in strings.json")

        if let note = section.note {
            #expect(Loc.get(note) != note, "\(note) is not in strings.json")
        }

        for entry in section.entries {
            if let use = entry.use {
                #expect(Loc.get(use) != use, "\(use) is not in strings.json")
            }
        }
    }
}

@Test func theScreenSaysNothingAboutWhatThePhoneDoesNotCarry() {
    // The desktop's list is not this list. ffmpeg, the ONNX models and SQLite are on the computer
    // and nowhere near the phone, and naming them here would be a false statement about what is on
    // the device. If a future edit to credits.json marks one of them "iphone", this is the alarm.
    let absent = ["FFmpeg", "ONNX Runtime", "SQLite", "OpenAL Soft", "Beat This!", "S-KEY",
                  "Uno Platform", "Skia", "TagLib#", "Velopack"]

    let named = Set(Credits.sections.flatMap { $0.entries.map(\.name) })

    for name in absent {
        #expect(!named.contains(name), "\(name) is credited on the phone, which does not ship it")
    }
}

@Test func theHoldersNameReplacesThePlaceholder() {
    let mit = """
    MIT License

    Copyright (c) <year> <copyright holders>

    Permission is hereby granted.
    """

    let filled = Credits.fill(mit, with: "Copyright (c) 2016 C.J. Hutto")

    #expect(filled.contains("Copyright (c) 2016 C.J. Hutto"))
    #expect(!filled.contains("<copyright holders>"))

    // The blank line under it survives; a licence whose first paragraph runs into its own title
    // reads as a rendering fault.
    #expect(filled.contains("Copyright (c) 2016 C.J. Hutto\n\nPermission"))
}

@Test func aPlaceholderWithNobodyToNameIsRemoved() {
    let mit = """
    MIT License

    Copyright (c) <year> <copyright holders>

    Permission is hereby granted.
    """

    for nobody in [nil, ""] as [String?] {
        let filled = Credits.fill(mit, with: nobody)

        #expect(!filled.contains("<"), "the placeholder was left standing")
        #expect(filled.contains("MIT License\n\nPermission"),
                "removing the line left the gap it was in")
    }
}

@Test func aLicenceWithRealHoldersIsLeftAlone() {
    // HarfBuzz lists its actual holders, and the Apache appendix shows how to apply the licence to
    // a work of your own. Neither is a placeholder, and writing over either would alter a licence.
    let harfbuzz = "Copyright © 2010-2022  Google, Inc.\nCopyright © 2019  Facebook, Inc."
    #expect(Credits.fill(harfbuzz, with: "Copyright (c) 2026 Someone Else") == harfbuzz)

    let apache = "   Copyright [yyyy] [name of copyright owner]\n\n   Licensed under..."
    #expect(Credits.fill(apache, with: "Copyright (c) 2026 Someone Else") == apache)
}

@Test func noEntryIsListedTwice() {
    var seen = Set<String>()

    for section in Credits.sections {
        for entry in section.entries {
            #expect(seen.insert(entry.id).inserted, "\(entry.id) is listed twice")
        }
    }
}
