import Foundation
import CryptoKit
import RPMCast
import RPMKit
import os

/// Where a track's cover comes from when it has to be shown on a screen in another room.
///
/// **It is provided by whoever built the player and is not read here.** The player does
/// not handle pictures (that is what `Player.onTrackChanged` is for). A track from another
/// user's shelf, or from a playlist that goes beyond this account's own listing, has no
/// file on this phone to read a cover from. The desktop app asks in the same way for the
/// same reason; see `SinkArtwork`.
///
/// The result is a JPEG. Nil is a valid answer and means this track has no cover.
///
/// The cover is served at its original size, because the fetch is an ordinary HTTP request
/// and its size does not matter. Only the fallback, sent to a receiver that could not
/// fetch it, must fit in a message. ``CastCover`` decides that.
public typealias RoomCover = @Sendable (CloudTrack) async -> Data?

/// The current track as another room sees it.
///
/// **This must be sent explicitly, because nothing else sends it.** The media on a
/// receiver is one endless stream, and the tracks inside it change without the receiver
/// knowing. A track change therefore produces nothing on the media namespace, and the
/// receiver keeps showing the track the queue started on until it is told otherwise.
/// Without this message the title stays old and the cover never arrives.
///
/// The cover is sent as an **address**, served by ``CastServer`` and fetched by the
/// receiver that draws the screen. The stock Default Media Receiver can only use an
/// address, and RPM's own receiver reads the address first too. The bytes are sent over
/// the control channel only when the receiver answers that it could not fetch the address.
/// See ``askedAgain()``, and `CastSink.OnArtworkRefused` on the desktop, which works the
/// same way and is the only caller of its `SendArtworkAsync`.
///
/// **Do not send the bytes up front.** A CASTV2 message is not a file transfer. When a
/// message is over the frame limit, the far end does not reject it but resets the socket,
/// so the cast ends before any audio is played. See ``CastCover``.
///
/// ``saying`` is nil when the stock receiver is running, because it does not know this
/// namespace. The check for which receiver is in use is made once, here, and not at every
/// place that sends a message.
///
/// `RPM.Core/Audio/CastSink.TrackChanged` is the same act on the desktop.
@MainActor
final class RoomScreen {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    private let sink: CastSink
    private let cover: RoomCover

    /// RPM's own receiver, and **the transport it is running on, never `receiver-0`**. The
    /// device does not know a namespace that belongs to the application it hosts, and a
    /// message sent there is dropped silently. Nil for the stock receiver.
    private let saying: (link: CastLink, transport: String)?

    init(sink: CastSink, cover: @escaping RoomCover,
         ours: (link: CastLink, transport: String)?) {
        self.sink = sink
        self.cover = cover
        self.saying = ours
    }

    /// Counts which track the screen is being told about.
    ///
    /// **Reading a cover takes an unpredictable time.** Two track changes in a row start
    /// two reads, and if the first one finishes second it would give the server and the
    /// receiver the skipped track's cover. The cover would not match the title beside it,
    /// and would stay wrong until the track after next. The value is checked again after
    /// every wait, in the same way as `Player.generation`.
    private var turn = 0

    /// Says what is playing now, and shows its cover with it.
    ///
    /// **It returns before the picture has been read, on purpose.** Reading a cover can
    /// take a network round trip on a phone, and the title must not wait for it. The only
    /// thing awaited is the promise that a cover is coming, which must exist before the
    /// address is published.
    ///
    /// - Parameters:
    ///   - track: what is playing. Nil removes the title and the picture.
    ///   - trackAt: how far into the track the change happens. Zero for a track that
    ///     starts at its beginning, which is every track except the first one of a stream
    ///     opened by a seek.
    ///   - streamAt: the position in the stream, by the receiver's own clock. Zero when a
    ///     LOAD is about to follow, because a LOAD restarts that clock.
    /// - Returns: the address to publish in that LOAD, or nil when there is no LOAD to
    ///   publish it in.
    @discardableResult
    func showing(_ track: CloudTrack?, trackAt: Double = 0, streamAt: Double = 0,
                 loading: Bool = false) async -> String? {
        turn &+= 1
        let mine = turn

        guard let track else {
            await put(nil, named: nil, generation: mine)
            return nil
        }

        // **The promise is registered before any address is published.** A fetch that
        // arrives before the picture has been read must be held, not answered with "this
        // track has no cover".
        await sink.expectCover()

        let said = CastNowPlaying(
            title: track.title ?? "",
            artist: track.artist,
            album: track.album,
            seconds: track.duration > .zero ? track.duration.seconds : nil,
            trackAt: trackAt,
            streamAt: streamAt)

        guard loading else {
            // **Nothing is sent until the cover has been read, and then it is sent once.**
            //
            // Sending the title first would send a `meta` message with no cover in it. The
            // receiver reads that as "this track has no cover": it removes the old cover,
            // shows a black record and the app's default blue background, and the cover
            // fades in a moment later. That is two transitions for one track change, and
            // the first is a visible flash of the default screen.
            //
            // This matches `CastSink.TrackChanged` on the desktop: read the art, supply
            // it, build the URL and send exactly one message.
            Task { [cover] in await put(await cover(track), named: said, generation: mine) }
            return nil
        }

        // A LOAD follows, and **it must not wait for a picture**: playback should not wait
        // for a cover. So the address is published before anything has been read (the
        // server holds a fetch for it until the bytes arrive). It is the same address in
        // the LOAD and in this message, so the receiver fetches once.
        var loadingSaid = said
        let address = await sink.coverAddress(named: CastServer.name())?.absoluteString
        loadingSaid.artUrl = address

        await tell(loadingSaid, generation: mine)

        // No further message when the bytes arrive: the receiver already has the address
        // they are served at. A second message that names the same picture differently
        // would cause a second fetch and a second fade of the cover into itself.
        Task { [cover] in await put(await cover(track), named: nil, generation: mine) }

        return address
    }

    /// Nothing is playing in this room.
    func nothing() async {
        turn &+= 1
        await put(nil, named: nil, generation: turn)
    }

    /// The last cover that was read, so a receiver that asks again can be answered
    /// without reading the cover twice.
    private var showing: Data?

    /// Called when the receiver could not load the cover from its address and asks for
    /// the picture itself.
    ///
    /// **This is the only place that sends a picture as bytes**, and only on request. The
    /// address is published before any cover has been read, so the receiver can fail for
    /// two reasons: it could not reach the phone, or it arrived before the picture
    /// existed. Both come here and both are answered with whatever has been read by now.
    /// That can be nothing, which is the message that removes the previous track's cover
    /// when the new track has none.
    func askedAgain() async {
        guard let saying else { return }

        // A picture that is too big to send counts as no cover. That is the correct answer
        // to "send me the one I could not fetch", because it cannot be sent.
        do { try await saying.link.show(showing.flatMap(CastCover.init(jpeg:)), on: saying.transport) }
        catch {
            Self.log.notice("the cover did not reach the room: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The last message sent to this room, so the same message is not sent twice.
    private var told: CastNowPlaying?

    /// Sends the title and other fields, when there is an RPM receiver to send them to and
    /// they differ from the last message.
    ///
    /// **A track can be announced by two paths at once.** A track change names its cover
    /// after the picture's contents. A LOAD for the same track (a feed that had to be
    /// reopened, or a seek) names the cover with a fresh address, because a LOAD publishes
    /// an address before any picture has been read. Both messages say the same thing about
    /// the same track and differ only in the name of the cover. The receiver compares
    /// addresses, and a different address causes a fetch, which fades the cover into
    /// itself in front of the viewer.
    ///
    /// So a message that changes only the name of a picture the room already has is not
    /// sent. **Every other message is sent**, including the same track at a different
    /// anchor, which is what a seek is.
    private func tell(_ said: CastNowPlaying, generation mine: Int) async {
        guard mine == turn, let saying else { return }

        if let told, told.artUrl != nil, said.sameRecord(as: told) { return }
        told = said

        do { try await saying.link.tell(said, on: saying.transport) }
        catch {
            Self.log.notice("""
                the room was not told what is playing: \(error.localizedDescription, privacy: .public)
                """)
        }
    }

    /// Puts a cover into the server, and sends the message **once** when there is something
    /// to send.
    private func put(_ jpeg: Data?, named said: CastNowPlaying?, generation mine: Int) async {
        // **A stale call sends nothing at all**, not even "no cover". Its track has been
        // replaced, and an empty answer for it would remove the new track's cover from the
        // screen.
        guard mine == turn else { return }

        await sink.nowShowing(jpeg)
        showing = jpeg

        // Nil is the LOAD path, which has already sent everything it will send: its
        // address was published in advance and the bytes are served at it.
        guard var said, mine == turn else { return }

        // The address names the picture and not the track, so all tracks of an album share
        // one address. The receiver keeps the cover it has and does not fade a picture into
        // itself on every track, and a different cover has a different address and is
        // loaded. The receiver's own `showArt` is the other end of this: it compares
        // addresses and does nothing when they match. `CastSink.KeyFor` does the same on
        // the desktop.
        if let jpeg, !jpeg.isEmpty {
            said.artUrl = await sink.coverAddress(named: Self.name(of: jpeg))?.absoluteString
        }

        // A track with no cover says so in the same message as its title. That removes the
        // previous track's cover when the new track has none.
        await tell(said, generation: mine)
    }

    /// Names a cover by its contents. This is not for security or strict uniqueness (two
    /// covers with the same name would only show one stale picture on a television), so
    /// eight bytes of the digest are enough. The desktop uses the same naming.
    private static func name(of jpeg: Data) -> String {
        SHA256.hash(data: jpeg).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
