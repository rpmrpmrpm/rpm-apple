import Foundation
import Testing

/// A fake speaker left standing for a person or a simulator to cast to.
///
/// **Not a test.** Enabled only when `RPM_HOLD_SPEAKER` names a folder: it writes the port
/// to `port` there and every key the speaker hears, with the time and what it has fetched,
/// to `heard.log`, for as long as `RPM_HOLD_SPEAKER_SECONDS` says (default ten minutes).
/// The app reaches it through its debug-only `RPM_CAST_HOST`. Nothing makes a sound.
@Suite("A speaker to cast to")
struct HoldASpeaker {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RPM_HOLD_SPEAKER"] != nil))
    func standAndListen() async throws {
        let env = ProcessInfo.processInfo.environment
        let folder = URL(fileURLWithPath: try #require(env["RPM_HOLD_SPEAKER"]))
        let seconds = Double(env["RPM_HOLD_SPEAKER_SECONDS"] ?? "") ?? 600

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let log = folder.appendingPathComponent("heard.log")
        try Data().write(to: log)

        let speaker = FakeSpeaker()
        try await speaker.start(named: "fake")
        try "\(speaker.device.port)".write(to: folder.appendingPathComponent("port"),
                                            atomically: true, encoding: .utf8)

        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss.SSS"

        var said = 0
        var lastLine = ""
        let end = Date().addingTimeInterval(seconds)

        while Date() < end {
            let (heard, state, fetched, starved) = speaker.what {
                ($0.heard, $0.playerState, $0.fetched, $0.starved)
            }

            var lines: [String] = []
            for key in heard.dropFirst(said) { lines.append("\(clock.string(from: Date())) KEY \(key)") }
            said = heard.count

            let line = "state \(state) fetched \(fetched / 1024) KB starved \(starved)"
            if line != lastLine {
                lines.append("\(clock.string(from: Date())) \(line)")
                lastLine = line
            }

            if !lines.isEmpty, let handle = try? FileHandle(forWritingTo: log) {
                handle.seekToEndOfFile()
                handle.write((lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
                try? handle.close()
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        speaker.stop()
    }
}
