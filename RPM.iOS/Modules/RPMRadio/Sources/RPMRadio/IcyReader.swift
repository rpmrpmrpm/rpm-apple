import Foundation

/// Takes the metadata out of a SHOUTcast or Icecast stream.
///
/// Ported from `RPM.Core/Radio/IcyStream.cs`, but **turned inside out**. The C# version is a
/// `Stream` that pulls data. A `URLSession` hands over whatever arrived, in whatever sizes, so
/// this reader is fed chunks instead. A chunk boundary can fall anywhere, even inside the length
/// byte or inside the text. So the state must carry over from one chunk to the next. That is the
/// main difference from the C# version, and the main difficulty.
///
/// A station that is asked for metadata (`Icy-MetaData: 1`) answers with an `icy-metaint` header.
/// After that the audio and the metadata are interleaved. Every `metaint` bytes of audio are
/// followed by one length byte. That length, times sixteen, is the number of bytes of text. The
/// text is usually `StreamTitle='Artist - Title';`. It is often unchanged, and it is often empty
/// (length zero). **A decoder given the raw stream would try to decode that text as audio.** So
/// this reader removes the text, passes the audio on unchanged, and reports each new title as it
/// goes past.
public struct IcyReader: Sendable {
    /// The bytes of audio between metadata blocks, from the `icy-metaint` response header. It is
    /// zero for a station without metadata. Then this reader passes all data through unchanged.
    private let every: Int

    private enum Reading: Sendable {
        /// Counting down the audio before the next block.
        case audio(Int)

        /// The one byte that gives the length of the block.
        case length

        /// The text itself. This many bytes are still to come.
        case text(Int)
    }

    private var reading: Reading
    private var text: [UInt8] = []

    /// The last title the station sent. An unchanged title is not reported twice. Some stations
    /// re-send the same block.
    public private(set) var title: String?

    public init(every metaInt: Int) {
        every = max(0, metaInt)
        reading = every > 0 ? .audio(every) : .audio(.max)
    }

    /// Takes one chunk as it arrived, and returns the audio that was in it.
    ///
    /// `said` is called for each **new** title in the chunk, in order.
    public mutating func take(_ data: Data, said: (String) -> Void) -> Data {
        guard every > 0 else { return data }
        guard !data.isEmpty else { return Data() }

        var audio = Data()
        audio.reserveCapacity(data.count)

        var at = data.startIndex

        while at < data.endIndex {
            switch reading {
            case .audio(let left):
                // **Never read past the next block.** The boundary is counted in bytes of
                // audio. Reading one byte too far puts every later block out of step, and the
                // text then reaches the decoder.
                let taking = min(left, data.endIndex - at)
                audio.append(data[at..<(at + taking)])
                at += taking

                reading = left == taking ? .length : .audio(left - taking)

            case .length:
                let length = Int(data[at])
                at += 1

                // Zero is the common case. Stations send new text only when it changes, and an
                // empty block costs one byte.
                reading = length == 0 ? .audio(every) : .text(length * 16)
                text.removeAll(keepingCapacity: true)

            case .text(let left):
                let taking = min(left, data.endIndex - at)
                text.append(contentsOf: data[at..<(at + taking)])
                at += taking

                guard left == taking else {
                    reading = .text(left - taking)
                    continue
                }

                if let heard = Self.titleIn(text), heard != title {
                    title = heard
                    said(heard)
                }

                reading = .audio(every)
            }
        }

        return audio
    }

    /// Reads the title from a metadata block: `StreamTitle='...';StreamUrl='...';`, padded with
    /// nulls to a multiple of sixteen.
    ///
    /// **Titles can contain apostrophes.** So the value ends at the first `';`, not at the first
    /// quote. Some stations leave out the `';`. For those the value ends at the end of the text.
    public static func titleIn(_ bytes: [UInt8]) -> String? {
        // Not every station sends UTF-8. A block that is not UTF-8 is read as Windows-1252, which
        // older servers use. That is Latin-1 with the curly quotes, the dashes and the euro sign
        // in the range 0x80 to 0x9F. Plain Latin-1 shows those bytes as invisible control
        // characters. Latin-1 is the last resort, for the five bytes that Windows-1252 leaves
        // undefined. The desktop app reads these blocks the same way, in
        // RPM.Core.Files.ForeignText.
        let block = String(bytes: bytes, encoding: .utf8)
                 ?? String(bytes: bytes, encoding: .windowsCP1252)
                 ?? String(bytes: bytes, encoding: .isoLatin1)
        guard let block else { return nil }

        let key = "StreamTitle='"
        guard let opens = block.range(of: key) else { return nil }

        let rest = block[opens.upperBound...]
        let closes = rest.range(of: "';")?.lowerBound
                  ?? rest.firstIndex(of: "\0")
                  ?? rest.endIndex

        let title = rest[rest.startIndex..<closes].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// The interleave interval that the station's response gives. It is zero when the response
    /// does not give one. That means the station was not asked for metadata, or does not send it.
    public static func metaInt(of response: URLResponse) -> Int {
        guard let http = response as? HTTPURLResponse else { return 0 }

        // Header names are case-insensitive, but stations spell them differently.
        let said = http.value(forHTTPHeaderField: "icy-metaint")
                ?? http.value(forHTTPHeaderField: "Icy-MetaInt")

        return Int(said ?? "") ?? 0
    }
}
