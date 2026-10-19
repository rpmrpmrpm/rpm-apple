import Foundation

/// What RPM's own receiver is told about the record. It is sent on the control channel, which
/// only RPM's receiver listens to.
///
/// **The media on the receiver is one endless stream, and the tracks inside it change without
/// the receiver knowing.** So a track change cannot be reported on the media namespace. A LOAD
/// would tell the receiver about the new track, but it would also cause a gap in the music at
/// every change. This message keeps the screen up to date instead.
///
/// The three numbers are the clock anchor. At stream second ``streamAt``, the record was
/// ``trackAt`` seconds in. The receiver counts forward from its own media clock, so the running
/// time on a television is correct without sending anything four times a second.
/// `RPM.Core/Audio/ICastReceiver.CastNowPlaying` holds the same record. Keep the two in step.
public struct CastNowPlaying: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?

    /// Where the receiver can fetch the cover. **This is sent before it is known whether there
    /// is a cover.** If the message waited for a picture to be read, a record with no picture
    /// would return a 404 and be drawn without a cover.
    ///
    /// It is sent even though the receiver usually gets the picture as bytes. The page is HTTPS,
    /// and this address is plain HTTP on the local network. A browser may refuse plain HTTP, but
    /// where it is allowed, this is the full-size image and it costs nothing extra.
    public var artUrl: String?

    /// How long the record is, when that is known.
    public var seconds: Double?

    /// How far into the record the changeover lands. Zero for a track that starts at its
    /// beginning. That is every track except the first one in a stream that was opened by a seek.
    public var trackAt: Double

    /// Where in the stream that is. The receiver holds an update that is ahead of where it is,
    /// and shows it when it gets there.
    public var streamAt: Double

    public init(title: String, artist: String? = nil, album: String? = nil,
                artUrl: String? = nil, seconds: Double? = nil,
                trackAt: Double = 0, streamAt: Double = 0) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artUrl = artUrl
        self.seconds = seconds
        self.trackAt = trackAt
        self.streamAt = streamAt
    }

    /// Whether two messages say the same thing about the same record at the same point. They may
    /// differ only in the name of the cover.
    ///
    /// **The address is not compared, on purpose.** Two routes can name one picture differently
    /// (see `RoomScreen.tell`). To a receiver, a new address means a new fetch, and a fetch is a
    /// visible change. The cover's name is not news about the record.
    public func sameRecord(as other: CastNowPlaying) -> Bool {
        title == other.title && artist == other.artist && album == other.album
            && seconds == other.seconds && trackAt == other.trackAt
            && streamAt == other.streamAt
    }

    /// The `meta` message, as the receiver reads it.
    var payload: String {
        var fields: [String: Any] = [
            "type": "meta",
            "title": title,
            "trackAt": trackAt,
            "streamAt": streamAt,
        ]
        if let artist { fields["artist"] = artist }
        if let album { fields["album"] = album }
        if let artUrl { fields["art"] = artUrl }
        if let seconds { fields["duration"] = seconds }

        guard let data = try? JSONSerialization.data(withJSONObject: fields) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A cover small enough to send as a message.
///
/// **A CASTV2 message is not a file transfer, and going over the limit is not an error that the
/// receiver reports.** The platform's frame limit is 64 KiB. If a message is larger, the far end
/// does not refuse it. It resets the socket. The cast then ends in the middle of a record, and
/// the only sign is a TCP reset.
///
/// So the limit is part of the type, not just a comment. ``CastLink/show(_:on:)`` takes one of
/// these and nothing else. Nothing can be sent without first passing the size check. The only
/// path that sends bytes now is the answer to a receiver that could not fetch the cover address.
/// That path is where a cover is largest, because the receiver has not been able to fetch it.
public struct CastCover: Sendable, Equatable {
    /// The largest cover in bytes, before base64 encoding.
    ///
    /// The frame limit is 64 KiB. Base64 adds a third to the size. The JSON and protobuf wrapping
    /// add a few hundred bytes more. 44,000 bytes leaves about 8 KB of margin. The receiver does
    /// not document this limit. It enforces it by closing the connection.
    public static let limit = 44_000

    public let jpeg: Data

    /// Returns nil when the picture is too large for a message.
    ///
    /// **nil does not mean "no cover".** Sending nil tells the receiver to remove the cover from the
    /// last record, so the two must not be confused. A caller with a picture that is too large
    /// should encode a smaller one and send that.
    public init?(jpeg: Data) {
        guard !jpeg.isEmpty, jpeg.count <= Self.limit else { return nil }
        self.jpeg = jpeg
    }

    /// The `data:` URI that the receiver draws straight into an `<img>`.
    var uri: String { "data:image/jpeg;base64," + jpeg.base64EncodedString() }
}

/// The channel that RPM's own receiver listens on, in the direction of the sender.
///
/// Nothing here is sent to `receiver-0`. **A device drops a message sent to a namespace it does
/// not know, and it does so without any reply.** So the transport id is a parameter with no
/// default. The compiler then asks for it at every call. A missing transport id fails silently.
/// See `CastControlChannel.SendMetadataAsync`.
extension CastLink {
    /// Tells the receiver what is playing now. The current playback is not changed.
    public func tell(_ playing: CastNowPlaying, on transport: String) async throws {
        try await send(CastMessage(destination: transport,
                                   namespace: Self.controlNamespace,
                                   payload: playing.payload))
    }

    /// Sends the cover as bytes, for a receiver that could not fetch it.
    ///
    /// **This is a reply, and it is never sent unasked.** The address goes out with the record, and
    /// the receiver fetches it. This is only the answer to a receiver that reports it could not. Sending
    /// the bytes up front resets the socket. See ``CastCover``.
    ///
    /// Nil is a valid answer, and it is sent. Skipping it would leave the previous record's cover on
    /// screen over a song that has no cover.
    ///
    /// ``CastCover`` has already checked the bytes against the frame limit. It is the only way to make one.
    public func show(_ cover: CastCover?, on transport: String) async throws {
        var fields: [String: Any] = ["type": "art"]
        if let cover { fields["data"] = cover.uri }

        guard let data = try? JSONSerialization.data(withJSONObject: fields) else { return }

        try await send(CastMessage(destination: transport,
                                   namespace: Self.controlNamespace,
                                   payload: String(decoding: data, as: UTF8.self)))
    }
}
