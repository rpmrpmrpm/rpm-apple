import Foundation

/// What to put on a speaker.
public struct CastMedia: Sendable, Equatable {
    /// Where the receiver fetches the media from. **The receiver fetches it itself.** So the address must be
    /// reachable from the speaker, not only from the phone. A URL that works in the app but not on the
    /// network is the usual cause of failure.
    public let url: String

    /// `audio/mpeg`, `audio/mp4`, or `audio/wav`. A receiver that cannot read the type refuses the load.
    /// It does not guess.
    public let contentType: String

    public var title: String = ""
    public var artist: String?
    public var album: String?
    public var artworkUrl: String?

    /// The length, when it is known. Nil means a live stream.
    public var seconds: Double?

    public init(url: String, contentType: String, title: String = "",
                artist: String? = nil, album: String? = nil,
                artworkUrl: String? = nil, seconds: Double? = nil) {
        self.url = url
        self.contentType = contentType
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkUrl = artworkUrl
        self.seconds = seconds
    }

    /// The LOAD payload, without its request number.
    var payload: String {
        var metadata: [String: Any] = [
            // 3 is MusicTrackMediaMetadata. A receiver with a screen draws the fields below from it.
            // A receiver without a screen uses the title for its status.
            "metadataType": 3,
            "title": title,
            "songName": title,
        ]
        if let artist { metadata["artist"] = artist }
        if let album { metadata["albumName"] = album }
        if let artworkUrl { metadata["images"] = [["url": artworkUrl]] }

        var media: [String: Any] = [
            // **Both fields, on purpose.** `contentId` is the field the protocol has always used.
            // `contentUrl` is the newer name. Receivers in use read one or the other.
            "contentId": url,
            "contentUrl": url,
            "contentType": contentType,
            // BUFFERED when the length is known, LIVE when it is not. A receiver needs a duration
            // before it shows a running time.
            "streamType": seconds != nil ? "BUFFERED" : "LIVE",
            "metadata": metadata,
        ]
        if let seconds { media["duration"] = seconds }

        let load: [String: Any] = ["type": "LOAD", "autoplay": true,
                                   "currentTime": 0, "media": media]

        guard let data = try? JSONSerialization.data(withJSONObject: load) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// What the receiver says it is doing with the media it was given.
public struct MediaStatus: Decodable, Sendable, Equatable {
    /// The session for this load. Every later command carries it. It changes with every LOAD.
    public let mediaSessionId: Int

    /// `IDLE`, `BUFFERING`, `PLAYING`, or `PAUSED`.
    public let playerState: String

    public let currentTime: Double?

    /// Why the receiver is idle, when it is: `FINISHED`, `CANCELLED`, `INTERRUPTED`, or `ERROR`.
    /// **`FINISHED` means the track ended. `ERROR` means the receiver could not fetch the track.** Both
    /// arrive with the same player state.
    ///
    /// No reason is a third case, and it is the easiest one to get wrong. The status that answers a LOAD is
    /// `IDLE` with no reason, because the receiver has taken the track and has not started it yet.
    public let idleReason: String?

    public var isPlaying: Bool { playerState == "PLAYING" }

    /// True while the receiver is fetching and has not started playing. This answers the question "why is
    /// nothing coming out yet".
    public var isBuffering: Bool { playerState == "BUFFERING" || playerState == "LOADING" }

    /// The receiver stopped because it could not play what it was given. A track that simply ended has the
    /// same player state, so the reason is checked as well.
    public var failed: Bool { playerState == "IDLE" && idleReason == "ERROR" }

    /// Taken, but not started yet. This is `IDLE` with no reason.
    public var accepted: Bool { playerState == "IDLE" && idleReason == nil }

    /// Reads a `MEDIA_STATUS` payload. The status is an array, because a receiver can hold several.
    /// In practice there is one.
    public static func of(_ payload: String) -> MediaStatus? {
        struct Envelope: Decodable { let status: [MediaStatus] }

        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data).status.first
    }
}

/// What the room says when it is asked where it has got to.
///
/// **There are three answers, and the third is why this is a type.** A receiver whose media session has ended
/// still answers `GET_STATUS`. It answers with an empty `status` array, because it has no media to describe.
/// If that were read as nil, it would look the same as a speaker that did not answer at all. The player would
/// then keep playing into a stream that nobody is fetching. Each of the three answers is its own case, so a
/// caller must handle each one by name.
public enum RoomReport: Sendable, Equatable {
    /// The room has media, and this is where it has got to.
    case holding(MediaStatus)

    /// The room answered, with nothing loaded. This happens after a stop at the speaker, and in the short gap
    /// between one stream ending and the next one starting.
    case nothingLoaded

    /// The room did not answer. The socket is down, or the speaker has gone.
    case noAnswer

    /// Whether the room answered that it is holding nothing.
    ///
    /// **This is a report, not a judgement on whether the report matters.** A receiver also holds nothing during
    /// a track change, because taking its stream away is the first step of a track change. What this means depends
    /// on what the player did a moment earlier. `RoomStream` decides that.
    public var isEmptyHanded: Bool { self == .nothingLoaded }
}

/// The media namespace: what is playing, and the keys that move it.
///
/// Every command here is sent to the **app's transport**, not to `receiver-0`. Every command carries the media
/// session that the LOAD returned.
extension CastLink {
    public enum Rejected: Error, Equatable {
        /// The receiver would not take the load. `LOAD_FAILED` usually points at the URL. The receiver either could
        /// not fetch it, or it could not read what came back.
        case load(String)

        /// **A later LOAD replaced this one before the receiver started it.** Two skips inside one second produce
        /// this. The receiver answers the first with `LOAD_CANCELLED`, and it plays the second.
        ///
        /// This is not a refusal, and the two answers mean opposite things. A refusal must bring the sound back to
        /// the phone. A superseded load must do nothing, because the room is about to play the newer track. Treating
        /// it as a refusal would stop the music on every double press.
        case superseded

        case unreadable
    }

    /// Hands a track to the receiver.
    ///
    /// **The result does not say whether the track is playing.** On a Nest Audio, the status that answers a LOAD is
    /// `IDLE`. It becomes `PLAYING` a second or so later, once the receiver has fetched enough to start. So `IDLE`
    /// here is the normal case. Reading it as a failure would reject every load.
    ///
    /// This returns the media session, which every later command uses. Whether the track is playing is answered by
    /// a later status. A URL that the receiver cannot fetch shows up there as `IDLE` with an `idleReason` of `ERROR`,
    /// not as a refusal here.
    @discardableResult
    public func load(_ media: CastMedia, on transport: String) async throws -> MediaStatus {
        let answer = try await ask(media.payload, namespace: Self.mediaNamespace,
                                   of: transport, within: .seconds(20))

        switch Self.reading(answer.payload) {
        case .superseded: throw Rejected.superseded
        case .refused(let why): throw Rejected.load(why)
        case .taken: break
        }

        guard let status = MediaStatus.of(answer.payload) else { throw Rejected.unreadable }
        return status
    }

    /// What a receiver's answer to a LOAD means.
    ///
    /// **The two replies must not be treated alike.** A receiver sends `LOAD_CANCELLED` for a load that it dropped
    /// because a newer one arrived. It sends `LOAD_FAILED` for a load that it could not do. Treating both as one
    /// refusal would stop the playback just as the newer track is starting. So the decision is a function of the
    /// reply text.
    static func reading(_ payload: String) -> Taken {
        // **Cancelled is checked before refused.** A receiver that says a load was overtaken is not refusing anything.
        if payload.contains("LOAD_CANCELLED") { return .superseded }

        if payload.contains("LOAD_FAILED") {
            return .refused(Self.reason(in: payload) ?? "the speaker would not take it")
        }

        return .taken
    }

    /// The three answers that a LOAD can receive.
    enum Taken: Sendable, Equatable {
        /// The receiver has the track. This does not mean it is playing it. See ``load(_:on:)``.
        case taken

        /// A later LOAD reached the receiver first, so it dropped this one.
        case superseded

        /// The receiver will not play it.
        case refused(String)
    }

    public func play(session: Int, on transport: String) async throws {
        _ = try await ask(#"{"type":"PLAY","mediaSessionId":\#(session)}"#,
                          namespace: Self.mediaNamespace, of: transport)
    }

    public func pause(session: Int, on transport: String) async throws {
        _ = try await ask(#"{"type":"PAUSE","mediaSessionId":\#(session)}"#,
                          namespace: Self.mediaNamespace, of: transport)
    }

    public func seek(to seconds: Double, session: Int, on transport: String) async throws {
        _ = try await ask(#"{"type":"SEEK","mediaSessionId":\#(session),"currentTime":\#(seconds)}"#,
                          namespace: Self.mediaNamespace, of: transport)
    }

    /// Removes the media from the receiver, without stopping the app.
    public func stopMedia(session: Int, on transport: String) async throws {
        _ = try await ask(#"{"type":"STOP","mediaSessionId":\#(session)}"#,
                          namespace: Self.mediaNamespace, of: transport)
    }

    /// Asks what the receiver is doing now.
    public func mediaStatus(on transport: String) async throws -> MediaStatus? {
        let answer = try await ask(#"{"type":"GET_STATUS"}"#,
                                   namespace: Self.mediaNamespace, of: transport)
        return MediaStatus.of(answer.payload)
    }

    /// Where the room is. **This includes the answer that it holds nothing.**
    ///
    /// See ``RoomReport``. `mediaStatus(on:)` answers the same question with a nil, and that nil can mean two
    /// different things. One of those meanings is a stopped receiver, and callers can miss it. `mediaStatus(on:)`
    /// is kept for callers that only need the position.
    public func whereItIs(on transport: String) async -> RoomReport {
        guard let answer = try? await ask(#"{"type":"GET_STATUS"}"#,
                                          namespace: Self.mediaNamespace, of: transport)
        else { return .noAnswer }

        if let status = MediaStatus.of(answer.payload) { return .holding(status) }

        // The receiver answered. An empty MEDIA_STATUS list means the receiver has no media. Any other message on
        // this namespace is not an answer to the question.
        return answer.payload.contains(#""MEDIA_STATUS""#) ? .nothingLoaded : .noAnswer
    }
}
