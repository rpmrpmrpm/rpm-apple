import Foundation
import Testing
@testable import RPMKit

/// The three ways a small state file can hold nothing, kept apart. See `StoreFile`.
struct StoreFileTests {
    private func file() -> URL {
        URL.temporaryDirectory.appending(path: "store-\(UUID().uuidString).json")
    }

    @Test func noFileIsAnEmptyStoreThatMayBeWritten() {
        let read = StoreFile.load(file()) { String(decoding: $0, as: UTF8.self) }

        #expect(read.value == nil)
        #expect(read.mayWrite)
    }

    @Test func aFileThatParsesIsRead() throws {
        let at = file()
        defer { try? FileManager.default.removeItem(at: at) }
        try Data("[1,2]".utf8).write(to: at)

        let read = StoreFile.load(at) { try JSONDecoder().decode([Int].self, from: $0) }

        #expect(read.value == [1, 2])
        #expect(read.mayWrite)
    }

    /// Moved aside so it can be looked at, and the store may start again.
    @Test func aFileThatDoesNotParseIsMovedAside() throws {
        let at = file()
        let aside = at.appendingPathExtension("unreadable")
        defer {
            try? FileManager.default.removeItem(at: at)
            try? FileManager.default.removeItem(at: aside)
        }
        try Data("{ not json".utf8).write(to: at)

        let read = StoreFile.load(at) { try JSONDecoder().decode([Int].self, from: $0) }

        #expect(read.value == nil)
        #expect(read.mayWrite)
        #expect(!FileManager.default.fileExists(atPath: at.path))
        #expect(FileManager.default.fileExists(atPath: aside.path))
    }

    /// There, and could not be read this time: not written over.
    @Test func aFileThatCouldNotBeReadMayNotBeWritten() throws {
        let at = file()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: at.path)
            try? FileManager.default.removeItem(at: at)
        }
        try Data("[1]".utf8).write(to: at)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: at.path)

        let read = StoreFile.load(at) { try JSONDecoder().decode([Int].self, from: $0) }

        #expect(read.value == nil)
        #expect(!read.mayWrite)
    }
}
