import Foundation
import Testing
@testable import RPMCast

/// Browsing for real speakers on the network that this machine is on.
///
/// These tests are off by default, like every live test here. They need a house with a Chromecast in it. A test that fails on a
/// train is one that people learn to ignore. Run them with `RPM_TEST_CAST=1 swift test --filter LiveDiscovery`.
///
/// **An empty answer is not a failure of this code.** No network, no permission, and no speakers all look the same from here.
/// That is the reason `speakers(for:)` never throws. The test says which of these it saw, so the reader can tell.
@Suite("Real speakers", .enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_CAST"] == "1"))
struct LiveDiscoveryTests {

    @Test func speakersOnThisNetworkAnswer() async {
        let found = await CastDiscovery().speakers(for: .seconds(5))

        for speaker in found {
            print("  \(speaker.name) — \(speaker.model) at \(speaker.host):\(speaker.port)"
                  + (speaker.isGroup ? "  (group)" : ""))
        }

        #expect(!found.isEmpty, "nothing answered: no speakers, no network, or no Local Network permission")
    }

    /// A group and its host speaker must be two entries, not one. This would be invisible in a picker, so it is tested.
    @Test func everySpeakerFoundHasItsOwnIdentity() async {
        let found = await CastDiscovery().speakers(for: .seconds(5))
        guard !found.isEmpty else { return }

        #expect(Set(found.map(\.id)).count == found.count)
    }
}

/// Talking to a real speaker.
///
/// This is the first part of the module that cannot be checked by reasoning alone. A sender that a receiver has never answered
/// should not be shipped. It uses the same gate as the browse test above. The speaker it talks to is the first one that answers.
@Suite("A real speaker answers",
       .enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_CAST"] == "1"),
       .serialized)
struct LiveLinkTests {

    /// A single speaker, not a group. A group answers status differently, and this test checks the handshake.
    private func aSpeaker() async -> CastDevice? {
        await CastDiscovery().speakers(for: .seconds(5)).first { !$0.isGroup }
    }

    @Test func theHandshakeIsAnswered() async throws {
        guard let speaker = await aSpeaker() else {
            Issue.record("no speaker on this network to talk to")
            return
        }

        print("  talking to \(speaker.name) at \(speaker.host):\(speaker.port)")

        let link = CastLink(to: speaker)
        let heard = try await link.open()

        try await link.send(CastMessage(
            namespace: CastLink.receiverNamespace,
            payload: #"{"type":"GET_STATUS","requestId":1}"#))

        // The first message on the receiver namespace, or nothing within the wait.
        let answer = await withTaskGroup(of: CastMessage?.self) { group in
            group.addTask {
                for await message in heard where message.namespace == CastLink.receiverNamespace {
                    return message
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        await link.close()

        let status = try #require(answer, "the speaker said nothing in eight seconds")
        print("  it said: \(status.payload.prefix(200))")

        #expect(status.payload.contains("RECEIVER_STATUS"))
    }
}

/// Starting Google's own player on a real speaker, and then handing it back.
///
/// **The test stops the app afterwards and never changes the volume.** It runs in someone's kitchen. A speaker plays a sound
/// each time its level is set. A test that makes a noise in another room every time it runs is a test that gets switched off.
@Suite("A real speaker takes an app",
       .enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_CAST"] == "1"),
       .serialized)
struct LiveReceiverTests {

    /// **A group is tried first, and this is deliberate.** A speaker may be part of a stereo pair. Google answers LAUNCH
    /// on a stereo pair with NOT_ALLOWED, whatever is asked for. Choosing a single speaker is the mistake that `isGroup` exists
    /// to prevent.
    private func somewhereThatWillTakeIt() async -> CastDevice? {
        let speakers = await CastDiscovery().speakers(for: .seconds(5))
        return speakers.first { $0.isGroup } ?? speakers.first
    }

    @Test func theDefaultMediaReceiverStartsAndSaysWhereToTalkToIt() async throws {
        let speaker = try #require(await somewhereThatWillTakeIt(), "nothing on this network")

        print("  \(speaker.name) at \(speaker.host):\(speaker.port)")

        let link = CastLink(to: speaker)
        _ = try await link.open()

        do {
            let app = try await link.launch()
            print("  running \(app.displayName ?? app.appId), session \(app.sessionId), transport \(app.transportId)")

            #expect(app.appId == ReceiverStatus.defaultMediaReceiver)
            #expect(!app.transportId.isEmpty)
            #expect(app.transportId != CastMessage.receiver)
            #expect(app.speaksMedia, "an app that does not speak media will ignore a LOAD")

            // It is running now, so a second launch joins it rather than restarting it.
            let again = try await link.launch()
            #expect(again.sessionId == app.sessionId)

            try await link.stop(app.sessionId)
        } catch let refused as CastLink.Refused {
            Issue.record("\(refused)")
        }

        await link.close()
    }

    /// The room's volume moves, and then goes back.
    ///
    /// **This is the one test here that makes a sound in someone's house, and it has to.** A speaker plays a sound each time its
    /// level is set. Proving that the level can be set means hearing two of them. Every other test here leaves the volume alone.
    @Test func theRoomsVolumeCanBeSet() async throws {
        let speaker = try #require(await somewhereThatWillTakeIt())

        let link = CastLink(to: speaker)
        _ = try await link.open()

        let before = try await link.status()
        guard let was = before.volume?.level, before.volume?.canBeSet == true else {
            await link.close()
            Issue.record("\(speaker.name) does not own its own volume")
            return
        }

        let asked = was < 0.5 ? was + 0.1 : was - 0.1
        let moved = try await link.setVolume(asked)
        print("  \(speaker.name): \(was) → \(moved.volume?.level ?? -1)")

        #expect(abs((moved.volume?.level ?? 0) - asked) < 0.05)

        _ = try? await link.setVolume(was)
        await link.close()
    }
}

/// Sound, in somebody's kitchen.
///
/// This is the last part of the protocol that cannot be checked by reasoning alone. A LOAD either comes back PLAYING or it does
/// not. The test needs `RPM_TEST_CAST_URL` set to something that the **speaker** can fetch. That is not always something this Mac
/// can fetch. A URL on localhost passes every test here and reaches no receiver anywhere.
///
/// It leaves the room's volume where it was. See the suite above for why.
@Suite("A real speaker plays",
       .enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_CAST_URL"] != nil),
       .serialized)
struct LivePlaybackTests {

    @Test func itLoadsAndPlaysAndTakesTheKeys() async throws {
        let url = try #require(ProcessInfo.processInfo.environment["RPM_TEST_CAST_URL"])
        let speakers = await CastDiscovery().speakers(for: .seconds(5))
        let speaker = try #require(speakers.first { $0.isGroup } ?? speakers.first)

        print("  \(speaker.name) ← \(url)")

        let link = CastLink(to: speaker)
        _ = try await link.open()

        let app = try await link.launch()

        let media = CastMedia(url: url, contentType: "audio/wav",
                              title: "RPM test tone", artist: "RPM", seconds: 3)

        let loaded = try await link.load(media, on: app.transportId)
        print("  \(loaded.playerState), session \(loaded.mediaSessionId)")

        // **IDLE with no reason is the normal first answer.** The receiver has taken the track and has not started it.
        // Treating it as a failure would reject good loads. A load that it cannot fetch returns ERROR.
        #expect(!loaded.failed, "the receiver could not fetch it")
        #expect(loaded.mediaSessionId > 0)

        // Give it a moment to start playing, and then read it back.
        try await Task.sleep(for: .seconds(2))
        let playing = try await link.mediaStatus(on: app.transportId)
        print("  now \(playing?.playerState ?? "nothing"), at \(playing?.currentTime ?? -1)s")

        #expect(playing?.playerState == "PLAYING" || playing?.idleReason == "FINISHED",
                "it never started")

        if let session = playing?.mediaSessionId, playing?.isPlaying == true {
            try await link.pause(session: session, on: app.transportId)
            try await link.seek(to: 1, session: session, on: app.transportId)
            try await link.stopMedia(session: session, on: app.transportId)
        }

        try await link.stop(app.sessionId)
        await link.close()
    }
}
