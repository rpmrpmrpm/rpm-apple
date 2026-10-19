import Foundation

/// Reading one of the phone's small state files. It keeps three cases apart: "there is no file",
/// "the file is there but could not be read now" and "the file was read but does not parse".
///
/// Ported from `RPM.Core/Files/StoreFile.cs`, which avoids this bug: a store that treated every
/// failure as "start empty" wrote the empty store over the file at the next change, so one failed
/// read could cost the listener everything the file held.
///
/// - A file that is not there is an empty store, and may be written.
/// - A file that could not be read is left alone, and is not written this session.
/// - A file that was read and does not parse is moved aside as `<name>.unreadable`, so it can be
///   looked at, and the store starts empty. If it cannot be moved it is not written over either.
public enum StoreFile {
    public struct Read<Value> {
        /// What the file held, or nil for any of the three ways of holding nothing.
        public let value: Value?

        /// False when the file is there and must not be written over this session.
        public let mayWrite: Bool
    }

    public static func load<Value>(_ file: URL, parse: (Data) throws -> Value) -> Read<Value> {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return Read(value: nil, mayWrite: true)
        }

        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            return Read(value: nil, mayWrite: false)
        }

        do {
            return Read(value: try parse(data), mayWrite: true)
        } catch {
            let aside = file.appendingPathExtension("unreadable")
            do {
                try? FileManager.default.removeItem(at: aside)
                try FileManager.default.moveItem(at: file, to: aside)
                return Read(value: nil, mayWrite: true)
            } catch {
                return Read(value: nil, mayWrite: false)
            }
        }
    }
}
