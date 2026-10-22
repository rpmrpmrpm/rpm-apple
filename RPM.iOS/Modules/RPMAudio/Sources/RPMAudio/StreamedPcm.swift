import Foundation
// The converter's input block is declared `@Sendable` and its buffers are not
// `Sendable`. The SDK describes it that way, but it runs the callback synchronously on
// the calling thread before `convert` returns. Nothing here escapes that call.
@preconcurrency import AVFAudio
import AudioToolbox
import os

/// A compressed byte stream, turned into PCM as the bytes arrive.
///
/// **This does what `AVAssetReader` cannot.** A reader needs an asset it can read by
/// range, and a track from the network is a socket that ends at some point. With a
/// reader, every cloud track would have to download completely before any sound came
/// out. `AudioFileStream` solves this, and radio stations need it too because they have
/// the same shape.
///
/// It is fed whatever the network delivers, in any chunk size, and it is asked for PCM
/// whenever PCM is needed. **Chunk boundaries are the risk**: a packet can be split
/// across two reads, and so can a header. A decoder that assumed otherwise would work on
/// a fast connection and stutter on a slow one. `AudioFileStream` handles this, which is
/// the main reason it is used.
public final class StreamedPcm: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "audio")

    public enum Trouble: Error, Equatable {
        /// The bytes are not a sound file this phone can open.
        case unreadable

        /// It opened and then said something that cannot be decoded.
        case undecodable
    }

    /// The output format: deinterleaved float, the format that everything after this type
    /// uses. A mixer, a tap and a cast sink all need the same thing.
    public static func pcm(rate: Double, channels: AVAudioChannelCount) -> AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)
    }

    /// **The one format the engine is wired at.**
    ///
    /// Every track is converted to this format and the engine is not rebuilt for each
    /// track. That is what lets one record follow another without a gap: buffers can only
    /// be scheduled onto a node in the format the node was connected with. Without it, a
    /// 48 kHz track after a 44.1 kHz track would need the graph to be rebuilt between
    /// them, which causes an audible gap.
    public static let engineFormat = AVAudioFormat(standardFormatWithSampleRate: 44100,
                                                   channels: 2)!

    /// **Everything below is used from two places**: the code that feeds bytes in, and the
    /// code that reads PCM out. They run on different threads by design, so one lock
    /// covers all the state. Separate atomics would each look correct but would not
    /// protect the state as a whole.
    private let gate = NSLock()

    private var parser: AudioFileStreamID?
    private var source: AVAudioFormat?

    /// Compressed packets to PCM **at the source's own rate**.
    ///
    /// **This is an `AudioConverterRef` and not an `AVAudioConverter`, because of one codec.**
    /// An `AudioStreamBasicDescription` says what a format is, but for several formats it
    /// does not contain enough to decode them. The rest is a blob (the magic cookie) that
    /// the container stores beside the audio. ALAC needs it: without it, every Apple
    /// Lossless file gives `kAudioCodecBadDataError` on its first packet and produces no
    /// frames.
    ///
    /// `AVAudioConverter` has a `magicCookie` property, but it accepts the assignment and
    /// reads back nil, and the decode still fails. The C converter accepts the same cookie
    /// and decodes the same file. So the decode uses the C API, and the resampler below
    /// (PCM to PCM, nothing to configure) uses `AVAudioConverter`.
    private var decoder: AudioConverterRef?

    /// Converts that PCM to the rate the engine is connected at, when the rates differ.
    ///
    /// **There are two converters and not one, because one cannot do both steps.** An
    /// `AVAudioConverter` from a compressed format to PCM at a *different* sample rate
    /// cannot be created: the initialiser returns nil and the track never plays. 48 kHz
    /// and 96 kHz records are common, so this case matters.
    private var resampler: AVAudioConverter?

    /// PCM at the sample rate of the record itself.
    private var native: AVAudioFormat?

    /// Data that the parser has delivered and that has not been decoded yet, oldest first.
    private var pending: [Parsed] = []

    /// A piece of the record, in the form the parser delivered it.
    ///
    /// **There are two forms, because the parser gives two.** A format whose packets have
    /// different sizes describes every packet, and each is kept with its description. A
    /// format whose packets all have the same size sends no descriptions. What arrives is
    /// then a run of packets, and it is kept as a run and not cut into packets. A frame of
    /// stereo PCM is four bytes, and one `Data` per four bytes would be about forty
    /// thousand allocations a second.
    ///
    /// **A run is not one packet, and treating it as one stops the decode.** If a run of
    /// eight thousand bytes is passed to the converter as a single packet, it answers
    /// `8192 bytes of input provided, but packet descriptions (0) only account for 0
    /// bytes`. The pump treats a stopped decode as a failed record and removes it from the
    /// player. Uncompressed records are passed as PCM and need no packets. The remaining
    /// case is a *compressed* format whose packets all have one size (u-law, A-law, AC-3),
    /// which needs this form to play.
    private enum Parsed {
        /// One packet, as the parser described it.
        case described(Data, AudioStreamPacketDescription)

        /// A run of packets, every one of them `size` bytes long.
        case run(Data, size: Int)
    }

    /// The stream has delivered everything it will deliver.
    private var ended = false

    /// The byte offset where the audio starts, after any data the container keeps before it.
    private var dataBegins: Int64 = 0

    /// The next bytes come from another place in the file. See ``expectAJump(landingAt:)``.
    private var jumped = false

    /// The format of the source, known once enough of the header has arrived. This is the
    /// **source's** format, which a sample-rate display shows. What ``read(upTo:)``
    /// returns is always ``engineFormat``.
    public var format: AVAudioFormat? { gate.withLock { source } }

    /// Whether the header has been read and packets are coming.
    public var ready: Bool { gate.withLock { decoder != nil } }

    /// How long the record is: **the music, without the encoder's padding**.
    ///
    /// The packet count in the container includes more than the music. AAC gives the
    /// decoder about two thousand frames of priming before the first note, and pads the
    /// last packet after the last note. For example, a three second clip has 2112 frames
    /// before and 756 frames after, which is 65 milliseconds. If they were counted, the
    /// clip would be 3.065 seconds long and every calculation based on it would be wrong
    /// by that amount. See ``howMuchIsPadding()``.
    ///
    /// Nil for a stream that does not give a duration (a station never does), and for a
    /// stream whose header has not arrived yet.
    public var duration: Double? { gate.withLock { musicSeconds() } }

    /// The same value as ``duration``, for code that already holds the lock.
    private func musicSeconds() -> Double? {
        guard let parser, let source else { return nil }

        var packets: UInt64 = 0
        var size = UInt32(MemoryLayout<UInt64>.size)

        guard AudioFileStreamGetProperty(
            parser, kAudioFileStreamProperty_AudioDataPacketCount, &size, &packets) == noErr,
              packets > 0
        else { return nil }

        let asbd = source.streamDescription.pointee
        guard asbd.mFramesPerPacket > 0, asbd.mSampleRate > 0 else { return nil }

        howMuchIsPadding()

        let frames = Double(packets) * Double(asbd.mFramesPerPacket) - Double(priming + trailing)
        return max(0, frames) / asbd.mSampleRate
    }

    // ── what the encoder wrote that is not music ──

    /// Frames of silence that the encoder put before the first note, at the source's own
    /// sample rate.
    private var priming: Int64 = 0

    /// Frames that the encoder added to the last packet after the last note.
    private var trailing: Int64 = 0

    /// Frames of priming that still have to be discarded from the start of this decode.
    private var primingLeft: Int64 = 0

    private var paddingKnown = false

    /// Reads the packet table's padding, once. **Called under the lock.**
    ///
    /// This is done lazily and not when the format is known, because an MP4 stores the
    /// values in its `moov` box, and a stream may not have reached it when the first
    /// packets arrive. The values are zero for formats without padding, which includes
    /// every uncompressed format.
    private func howMuchIsPadding() {
        guard !paddingKnown, let parser, source != nil else { return }

        var info = AudioFilePacketTableInfo()
        var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)

        guard AudioFileStreamGetProperty(
            parser, kAudioFileStreamProperty_PacketTableInfo, &size, &info) == noErr else { return }

        paddingKnown = true
        priming = Int64(max(0, info.mPrimingFrames))
        trailing = Int64(max(0, info.mRemainderFrames))

        // Only a decode that starts at the beginning of the record has priming before it.
        // A decode that started after a jump is already past it.
        primingLeft = made == 0 && begins == 0 ? priming : 0
    }

    /// The format this converts to. Everything the engine plays uses one format. See
    /// ``engineFormat``.
    private let output: AVAudioFormat

    public init(to output: AVAudioFormat = StreamedPcm.engineFormat) {
        self.output = output
    }

    deinit {
        if let parser { AudioFileStreamClose(parser) }
        if let decoder { AudioConverterDispose(decoder) }
    }

    /// Feeds bytes. Any size is accepted, including a chunk that splits a packet.
    public func take(_ data: Data) throws {
        guard !data.isEmpty else { return }

        let parser = try gate.withLock { try opened() }

        // The flag is set once, on the first bytes after a jump. Setting it on every chunk
        // would tell the parser that every read is a new position in the file.
        //
        // **It is not set at all for a format that cannot recover from a discontinuity.**
        // An uncompressed stream that is told about a discontinuity answers
        // `kAudioFileStreamError_DiscontinuityCantRecover` (`'dsc!'`) to that call and to
        // every call after it. The bytes after the jump then look like a stream that cannot
        // be parsed, the download is stopped, and the record cannot be played.
        //
        // The parser is right that there is nothing to recover: a compressed bitstream has
        // to find its next sync word after a jump, but a run of PCM frames does not,
        // because every byte is audio. The flag does nothing for these formats, and the
        // parser's refusal says so.
        let flags: AudioFileStreamParseFlags = gate.withLock {
            guard jumped else { return [] }
            jumped = false

            guard let source, Self.inPackets(source) else { return [] }
            return .discontinuity
        }

        let failed = data.withUnsafeBytes { bytes in
            AudioFileStreamParseBytes(parser, UInt32(data.count), bytes.baseAddress, flags)
        }
        guard failed == noErr else { throw Trouble.unreadable }
    }

    /// The stream is over, and **why**. Data that is still held can still be read.
    ///
    /// **The reason has no default.** Whatever ends a stream knows why it ended, so it must
    /// say so. Without the reason, the player would have to guess from the playback
    /// position, which cannot tell a record that stopped early from a record that is
    /// short. See ``Ending``.
    public func finish(_ why: Ending.Why) {
        gate.withLock {
            ended = true
            stated = why
        }
    }

    /// Whether everything that will arrive has been decoded.
    public var drained: Bool {
        gate.withLock { ended && pending.isEmpty }
    }

    /// Why it ended, and whether that was the end of the record.
    ///
    /// Only useful for a stream that is ``drained``. `ended` is set only by
    /// ``finish(_:)``, so a drained stream has always been given a reason. A stream that
    /// has not been given one is still running, and the value returned for it carries no
    /// information.
    public var ending: Ending {
        Ending(why: gate.withLock { stated } ?? .itWasPutDown, reachedItsEnd: reachedTheEnd)
    }

    /// The reason given to ``finish(_:)``.
    private var stated: Ending.Why?

    /// Where this stream begins in the record, in seconds. Zero from the start, and the
    /// landing second after a jump.
    ///
    /// **It is kept here and not by the caller**, because it is one part of the only
    /// calculation that shows whether a record is over: the length the file reports,
    /// compared with the position the decoder reached. A stream that was requested from the
    /// middle must add the part that was never sent.
    public private(set) var begins: Double = 0

    /// Whether the decoder reached the end of what the file says it holds.
    ///
    /// **It uses the file's own header, not the tags.** The duration in a tag is written by
    /// a tagging program and often differs from the recording. This property counts the
    /// packets that the container says it holds and compares them with the frames the
    /// converter made. They agree to within the priming samples when nothing is wrong, so
    /// the allowance is one second.
    ///
    /// A record encoded while it is sent has no duration in its header, so the length the
    /// encoder stated beside the stream is used instead. See ``statesItsLength(_:)``.
    ///
    /// A stream with neither (a station never says) is taken at its word, so a source that
    /// cannot be measured is not treated as broken. **Only when it ended normally.** A dropped
    /// connection is not the end of the record: read as the end, the queue would move on to the
    /// next song in the middle of this one, with no message and no second attempt.
    public var reachedTheEnd: Bool {
        guard let holds = duration ?? gate.withLock({ told }) else {
            return gate.withLock { stated } == .theFileRanOut
        }
        let got = gate.withLock { begins + Double(made) / output.sampleRate }

        return got >= holds - Self.shortfall
    }

    /// The record's length as the sender stated it. Nil unless ``statesItsLength(_:)`` was called.
    private var told: Double?

    /// The length of the whole record, in seconds, stated by whoever sends the bytes.
    ///
    /// **For a record encoded while it is sent.** It arrives as ADTS, which carries no length,
    /// and the encoder can end the stream cleanly when it fails part way. Without a length, that
    /// early end and the real end look the same. It is the whole record's length, also for a
    /// stream that began part way: ``begins`` is added to what was decoded before the two are
    /// compared. The length in the file's own header, when there is one, comes first.
    public func statesItsLength(_ seconds: Double) {
        gate.withLock { told = seconds }
    }

    /// How far, in seconds, a stream may stop before the length given in the header and
    /// still count as having reached the end.
    private static let shortfall: Double = 1

    /// How many frames have been returned so far, in the output format.
    ///
    /// **This is what was played, not what was requested.** That is why it is counted here
    /// and not calculated from a duration: the number of frames that three seconds of AAC
    /// decodes to depends on how the encoder used its priming samples. A caller that
    /// joins a second stream to this one discards this many frames from the start of the
    /// second stream, so that the join falls on the last frame the listener heard. See
    /// ``PcmEngine/joinBehind(_:id:at:)``.
    public var produced: AVAudioFramePosition { gate.withLock { made } }
    private var made: AVAudioFramePosition = 0

    /// Decodes up to `frames` of what has arrived.
    ///
    /// Returns nil while nothing has arrived yet. This is normal for a stream that is asked
    /// for sound before the network has caught up. It is not an error and it is not the
    /// end: only ``drained`` shows the end.
    public func read(upTo frames: AVAudioFrameCount = 8192) throws -> AVAudioPCMBuffer? {
        let (converter, native, resampler) = gate.withLock {
            (self.decoder, self.native, self.resampler)
        }

        guard let converter, let native else { return nil }
        guard gate.withLock({ !pending.isEmpty }) else { return nil }
        guard let out = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: frames)
        else { throw Trouble.undecodable }

        // **`frameLength` is the only way to say how much room there is.** An
        // `AVAudioPCMBuffer` builds its buffer list from `frameLength` every time the list
        // is requested. A new buffer has length zero, so the converter would get two buffers
        // of zero bytes and answer `paramErr`. Writing the sizes into the list does not
        // work either, because the next request for the list builds it again from the
        // length. So the length is set to the available room before the call, and to the
        // number of frames produced after it.
        out.frameLength = frames

        var got = frames

        let status = AudioConverterFillComplexBuffer(
            converter, Self.supplying, Unmanaged.passUnretained(self).toOpaque(),
            &got, out.mutableAudioBufferList, nil)

        // `nothingYet` is this file's own status for "the network is behind". It is not a
        // failure; see ``supply(_:_:_:)``. Everything the converter produced before it ran
        // out of input is counted in `got` and is kept.
        if status != noErr, status != Self.nothingYet {
            let what = Self.describe(native.streamDescription.pointee)
            Self.log.error("\(what, privacy: .public) would not decode: \(Self.name(status), privacy: .public)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        guard got > 0 else { return nil }
        out.frameLength = got

        guard let resampler else { return counted(withoutThePriming(out)) }
        return counted(withoutThePriming(try moved(out, through: resampler)))
    }

    /// Discards the frames that the encoder put before the first note.
    ///
    /// **A join between two streams is audible if this is wrong.** When one stream is
    /// joined to another, the position of the join is measured in what the first stream
    /// *played* (``produced``). If the priming were counted as played, the first stream
    /// would seem to be about 46 milliseconds further into the record than it really is.
    /// The second stream would then start 46 milliseconds too late, and that much music
    /// would be missing at the join.
    ///
    /// When both streams are decoded from the start, they carry the same priming and the
    /// two errors cancel. They do not cancel when the second stream starts in the middle
    /// of the file, because a decode that starts there has no priming. They also never
    /// cancel for an original in FLAC or WAV format, which has no priming.
    ///
    /// **The tail is not changed.** The remainder frames are the encoder's padding of the
    /// last packet. Cutting the end of a source short would leave the pump asking a stream
    /// that is not drained for audio that it will never return. 17 milliseconds of padding
    /// between two tracks is better than a record that waits for ever on its last packet.
    private func withoutThePriming(_ buffer: AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
        guard let buffer else { return nil }

        // Counted at the engine's rate and not the source's, because the buffer is already
        // converted to it. One frame is about 23 microseconds either way.
        let drop = gate.withLock { () -> AVAudioFrameCount in
            howMuchIsPadding()
            guard primingLeft > 0, let native = self.native else { return 0 }

            let here = Int64((Double(primingLeft) * output.sampleRate / native.sampleRate).rounded())
            let cut = min(here, Int64(buffer.frameLength))

            primingLeft -= Int64((Double(cut) * native.sampleRate / output.sampleRate).rounded())
            return AVAudioFrameCount(max(0, cut))
        }

        guard drop > 0 else { return buffer }
        guard drop < buffer.frameLength else { return nil }

        return buffer.past(drop)
    }

    /// Returned by the input block when the network is behind and the file is not over.
    ///
    /// **It is not `noErr` with no data**, because that is how this API is told that the
    /// stream has ended. If that were returned once because a chunk was late, the converter
    /// would refuse all later input, and the track would stop for good (for example after a
    /// short loss of signal in a tunnel). `FillComplexBuffer` returns an unrecognised
    /// status to its caller unchanged and does not change the converter, which is what is
    /// needed.
    private static let nothingYet: OSStatus = 0x6E6F_6474   // 'nodt'

    /// The C entry point. It captures nothing, because a C function pointer cannot capture.
    private static let supplying: AudioConverterComplexInputDataProc = {
        _, packets, data, descriptions, context in

        guard let context else { packets.pointee = 0; return noErr }

        return Unmanaged<StreamedPcm>.fromOpaque(context)
            .takeUnretainedValue().supply(packets, data, descriptions)
    }

    /// Gives the converter its next packets, and **keeps them until the converter asks
    /// again**: what is passed here is a pointer, and the converter reads it after this
    /// function returns.
    private func supply(_ packets: UnsafeMutablePointer<UInt32>,
                        _ data: UnsafeMutablePointer<AudioBufferList>,
                        _ descriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?)
    -> OSStatus {
        guard let handful = next(upTo: packets.pointee) else {
            packets.pointee = 0
            return drained ? noErr : Self.nothingYet
        }

        // The previous one is released here and not earlier, because the converter was still
        // reading it until now.
        gate.withLock { holding = handful }

        packets.pointee = handful.packets

        data.pointee.mNumberBuffers = 1
        data.pointee.mBuffers = AudioBuffer(mNumberChannels: handful.channels,
                                            mDataByteSize: UInt32(handful.bytes.count),
                                            mData: handful.bytes.baseAddress)

        descriptions?.pointee = handful.descriptions?.baseAddress

        return noErr
    }

    /// The input that the converter is reading now.
    private var holding: Handful?

    /// One block of input, in memory that stays valid after the call that passed it.
    ///
    /// It is a class so that replacing it frees the previous one, and so that the last one
    /// is freed when this stream is freed.
    private final class Handful {
        let bytes: UnsafeMutableRawBufferPointer
        let descriptions: UnsafeMutableBufferPointer<AudioStreamPacketDescription>?
        let packets: UInt32
        let channels: UInt32

        init(_ data: Data, packets: UInt32,
             describing list: [AudioStreamPacketDescription]?, channels: UInt32) {
            bytes = UnsafeMutableRawBufferPointer.allocate(byteCount: max(1, data.count),
                                                           alignment: 1)
            _ = data.copyBytes(to: bytes.bindMemory(to: UInt8.self))

            if let list, !list.isEmpty {
                let room = UnsafeMutableBufferPointer<AudioStreamPacketDescription>
                    .allocate(capacity: list.count)
                _ = room.initialize(fromContentsOf: list)
                descriptions = room
            } else {
                descriptions = nil
            }

            self.packets = packets
            self.channels = channels
        }

        deinit {
            bytes.deallocate()
            descriptions?.deallocate()
        }
    }

    private func counted(_ buffer: AVAudioPCMBuffer?) -> AVAudioPCMBuffer? {
        guard let buffer else { return nil }
        gate.withLock { made += AVAudioFramePosition(buffer.frameLength) }
        return buffer
    }

    /// Converts a decoded buffer to the engine's sample rate.
    ///
    /// This is a plain PCM to PCM conversion, and it is the second step of what a single
    /// converter cannot do. The output size is calculated from the two rates and rounded
    /// up. A buffer that is one frame too small loses a frame on every read, which over a
    /// whole record is audible as a wrong pitch.
    private func moved(_ decoded: AVAudioPCMBuffer,
                       through resampler: AVAudioConverter) throws -> AVAudioPCMBuffer? {
        let ratio = resampler.outputFormat.sampleRate / resampler.inputFormat.sampleRate
        let room = AVAudioFrameCount((Double(decoded.frameLength) * ratio).rounded(.up)) + 1

        guard let out = AVAudioPCMBuffer(pcmFormat: resampler.outputFormat, frameCapacity: room)
        else { throw Trouble.undecodable }

        // Unchecked because `convert` calls the block below on this thread and the block has
        // finished before `convert` returns, so no second thread can race with it.
        nonisolated(unsafe) var handed = false
        var failed: NSError?

        let status = resampler.convert(to: out, error: &failed) { _, standing in
            // **Once.** The resampler asks again for more input and there is none to
            // give it: this buffer is what there is, and saying `noDataNow` here is
            // what stops it waiting for a second one that is not coming.
            guard !handed else {
                standing.pointee = .noDataNow
                return nil
            }
            handed = true
            standing.pointee = .haveData
            return decoded
        }

        if let failed, status == .error { throw failed }
        return out.frameLength > 0 ? out : nil
    }

    /// The next input block for the converter, with no more data than was asked for.
    ///
    /// **Only the requested amount is returned, and the rest is kept for later.** A
    /// converter takes what fits in the buffer it is filling and drops the rest of what it
    /// was given. It does not ask for it again, so a run bigger than the output capacity
    /// would lose its end silently. Compressed formats rarely have this problem, because a
    /// packet is about a thousand frames and the output is eight thousand. A run is as
    /// large as the chunks from the network, and with 64 kilobyte chunks three frames in
    /// four were lost. The result is a record that plays four times too fast, and in a
    /// test a half-second file that decodes to an eighth of a second.
    private func next(upTo wanted: UInt32) -> Handful? {
        gate.withLock { () -> Handful? in
            guard let source, let first = pending.first else { return nil }

            let asbd = source.streamDescription.pointee
            let channels = max(1, asbd.mChannelsPerFrame)
            let describe = Self.needsDescriptions(asbd)

            switch first {
            case .described(let bytes, let was):
                pending.removeFirst()

                let one = AudioStreamPacketDescription(
                    mStartOffset: 0,
                    mVariableFramesInPacket: was.mVariableFramesInPacket,
                    mDataByteSize: UInt32(bytes.count))

                return Handful(bytes, packets: 1,
                               describing: describe ? [one] : nil, channels: channels)

            case .run(let bytes, let size):
                guard size > 0, wanted > 0 else { return nil }

                let packets = min(Int(wanted), bytes.count / size)
                guard packets > 0 else { return nil }

                let taken = bytes.prefix(packets * size)

                if taken.count < bytes.count {
                    pending[0] = .run(Data(bytes.dropFirst(taken.count)), size: size)
                } else {
                    pending.removeFirst()
                }

                let list = describe ? (0..<packets).map {
                    AudioStreamPacketDescription(mStartOffset: Int64($0 * size),
                                                 mVariableFramesInPacket: 0,
                                                 mDataByteSize: UInt32(size))
                } : nil

                return Handful(Data(taken), packets: UInt32(packets),
                               describing: list, channels: channels)
            }
        }
    }

    /// Whether the converter has to be told where each packet begins.
    ///
    /// **The answer depends on the shape of the format, not on a list of format names.** A
    /// list would put every format it does not know into the group that needs
    /// descriptions. What decides it is whether all packets have the same size. If the
    /// format gives the number of bytes and frames in a packet, the converter can step
    /// through the data on its own. If either value is zero, it cannot.
    ///
    /// If this is wrong, the converter repeatedly answers `8192 bytes of input provided,
    /// but packet descriptions (0) only account for 0 bytes`, and the record plays
    /// silence.
    private static func needsDescriptions(_ asbd: AudioStreamBasicDescription) -> Bool {
        asbd.mBytesPerPacket == 0 || asbd.mFramesPerPacket == 0
    }

    /// Whether a format's blocks are packets that must be resynchronised after a jump.
    ///
    /// **Three formats are passed as runs of frames**, and every byte of them is audio.
    /// They have no sync word to find after a discontinuity, so telling the parser about a
    /// discontinuity stops the record. See ``take(_:)``.
    private static func inPackets(_ source: AVAudioFormat) -> Bool {
        switch source.streamDescription.pointee.mFormatID {
        case kAudioFormatLinearPCM, kAudioFormatULaw, kAudioFormatALaw: return false
        default: return true
        }
    }

    /// Whether a run of this format's frames can be copied out in one piece.
    ///
    /// Interleaved, or one channel, which is the same for a memcpy. A deinterleaved source
    /// would need one copy per channel, and no container that is read here provides one.
    /// It is refused when the header arrives, so it is not silently passed on incomplete.
    private static func copyable(_ asbd: AudioStreamBasicDescription) -> Bool {
        asbd.mBytesPerFrame > 0
            && (asbd.mChannelsPerFrame == 1
                || asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0)
    }

    /// Shows a status code as its four characters, when it is a four character code.
    private static func name(_ status: OSStatus) -> String {
        let id = UInt32(bitPattern: status)
        let letters = [24, 16, 8, 0].map { UInt8((id >> $0) & 0xFF) }

        return letters.allSatisfy { (0x20...0x7E).contains($0) }
            ? "'\(String(decoding: letters, as: UTF8.self))'" : "\(status)"
    }

    // ── seeking ──

    /// Which byte to ask the store for, to hear `seconds`.
    ///
    /// **This is how a seek works on a stream read from the network.** The socket only goes
    /// forwards, so a seek is a new request with a range. The range is calculated here,
    /// because only the parser knows where a packet begins.
    ///
    /// It also gives the second that the seek will actually land on. This is not the
    /// requested second, because a packet is 1024 frames and the seek goes to the start of
    /// a packet.
    ///
    /// Nil before the header has been read, and for a stream whose packets cannot be found
    /// by time.
    public func byteToHear(_ seconds: Double) -> Landing? {
        gate.withLock {
            guard let parser, let source else { return nil }

            let asbd = source.streamDescription.pointee
            let perPacket = Double(max(1, asbd.mFramesPerPacket))
            let packet = Int64((max(0, seconds) * asbd.mSampleRate / perPacket).rounded(.down))

            var byte: Int64 = 0
            var flags = AudioFileStreamSeekFlags()

            guard AudioFileStreamSeek(parser, packet, &byte, &flags) == noErr, byte >= 0 else {
                return nil
            }

            // **The parser's byte is relative to the audio, not to the file.** The header
            // comes before the audio, so `dataBegins` is added. Without it the request would
            // start in the middle of an MP4's own metadata, and the track would not seek.
            howMuchIsPadding()

            let at = byte + dataBegins

            // **Music time, not container time.** Packet zero holds the priming, so a packet
            // index counts the frames that the decoder produces, not the frames that are
            // heard. Everything after this (the join, the position, the end-of-record check)
            // uses the music's own seconds. Returning container time would place the join
            // too far into the record by the length of the priming.
            let second = max(0, (Double(packet) * perPacket - Double(priming)) / asbd.mSampleRate)

            return flags.contains(.offsetIsEstimated)
                ? .near(byte: at, second: second)
                : .exactly(byte: at, second: second)
        }
    }

    /// Where to request data from the store, and **whether the parser knows the position or
    /// is estimating it**.
    ///
    /// These are one value, because the byte alone can be wrong without any sign.
    /// `AudioFileStreamSeek` returns a byte in both cases. It sets
    /// `kAudioFileStreamSeekFlag_OffsetIsEstimated` when it calculated the byte from an
    /// average and not from a table. For FLAC this is always the case: the same second gives
    /// byte 47420, 46620 and 46541 as more of the file arrives. **An estimate is good enough
    /// for a seek**, because a position a fifth of a second away cannot be heard. It is not
    /// good enough for joining two streams, where the number is the position at which the
    /// second stream will be joined. If the stream does not start at the second where it is
    /// joined, the audio jumps.
    ///
    /// So there are two cases, and a caller that joins streams must name the case it can
    /// use.
    public enum Landing: Sendable, Equatable {
        /// The parser found the packet. This byte begins exactly at `second`.
        case exactly(byte: Int64, second: Double)

        /// The parser calculated it from an average. This byte is near `second`, and how near
        /// cannot be known here.
        case near(byte: Int64, second: Double)

        public var byte: Int64 {
            switch self {
            case .exactly(let byte, _), .near(let byte, _): return byte
            }
        }

        public var second: Double {
            switch self {
            case .exactly(_, let second), .near(_, let second): return second
            }
        }
    }

    /// Discards everything held and prepares for bytes from **another place in the same
    /// file**, starting at `seconds`.
    ///
    /// The parser must be told. Otherwise it reads the first packet of the new range as the
    /// continuation of the last packet it saw, and produces a click or no output.
    ///
    /// - Parameter seconds: where in the record the next bytes begin. **No default**: it is
    ///   used to decide whether a stream that stopped had reached the end of the record.
    ///   Without it, every seek would look like a record that ended half way through. See
    ///   ``reachedTheEnd``.
    public func expectAJump(landingAt seconds: Double) {
        gate.withLock {
            pending.removeAll()
            ended = false
            stated = nil
            jumped = true
            begins = max(0, seconds)
            made = 0

            // A decode that starts in the middle of a file has no priming before it. The
            // encoder wrote the priming once, at the start.
            primingLeft = 0

            // **The decoder must be reset as well as the parser.** A converter keeps state from
            // the earlier packets. If it is given a packet from another place in the file, it
            // answers `bada` and stops. The parser flag alone is not enough. The failure looks
            // like a seek that ends the track silently: audio that was already scheduled
            // plays out, so the position keeps moving for a second afterwards.
            if let decoder { AudioConverterReset(decoder) }
            resampler?.reset()
        }
    }

    /// Where the channels of a multichannel record are meant to go.
    ///
    /// The parser is asked first, and **it often does not have the layout**. A FLAC file
    /// stores a layout only as a `WAVEFORMATEXTENSIBLE_CHANNEL_MASK` comment. This is an
    /// optional tag, and retagging can remove it. CoreAudio then reports nothing, even when
    /// it could work out the order. Many real library files do not have the tag.
    ///
    /// Nil for ordinary stereo, which needs no layout: one or two channels are unambiguous
    /// and `AVAudioFormat` builds them without help.
    private static func layout(of parser: AudioFileStreamID,
                               channels: UInt32) -> AVAudioChannelLayout? {
        stated(by: parser) ?? assumed(channels)
    }

    /// The data (the magic cookie) that a container stores beside the audio, for codecs
    /// whose stream description is not enough to decode them.
    ///
    /// Nil for codecs that need none, which is most of them.
    private static func cookie(of parser: AudioFileStreamID) -> Data? {
        var size: UInt32 = 0
        var writable: DarwinBoolean = false

        guard AudioFileStreamGetPropertyInfo(
            parser, kAudioFileStreamProperty_MagicCookieData, &size, &writable) == noErr,
              size > 0
        else { return nil }

        var bytes = [UInt8](repeating: 0, count: Int(size))

        guard AudioFileStreamGetProperty(
            parser, kAudioFileStreamProperty_MagicCookieData, &size, &bytes) == noErr
        else { return nil }

        return Data(bytes)
    }

    /// What the file itself says.
    private static func stated(by parser: AudioFileStreamID) -> AVAudioChannelLayout? {
        var size: UInt32 = 0
        var writable: DarwinBoolean = false

        guard AudioFileStreamGetPropertyInfo(
            parser, kAudioFileStreamProperty_ChannelLayout, &size, &writable) == noErr,
              size >= UInt32(MemoryLayout<AudioChannelLayout>.size)
        else { return nil }

        let room = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { room.deallocate() }

        guard AudioFileStreamGetProperty(
            parser, kAudioFileStreamProperty_ChannelLayout, &size, room) == noErr
        else { return nil }

        return AVAudioChannelLayout(layout: room.assumingMemoryBound(to: AudioChannelLayout.self))
    }

    /// The channel order for a file with this many channels, when the file does not give one.
    ///
    /// **This is FLAC's order, which the format fixes: it is not a guess.** The order is
    /// left, right, centre, LFE, then the surrounds. It is written as a bitmap because a
    /// bitmap is read from the lowest bit, and that gives the same sequence as the FLAC
    /// specification. The two cannot differ, which a hand-written list of labels could.
    ///
    /// Nil below three channels, which need no layout, and above eight, where there is no
    /// common convention.
    private static func assumed(_ channels: UInt32) -> AVAudioChannelLayout? {
        let front: AudioChannelBitmap = [.bit_Left, .bit_Right]
        let back: AudioChannelBitmap = [.bit_LeftSurround, .bit_RightSurround]
        let side: AudioChannelBitmap = [.bit_LeftSurroundDirect, .bit_RightSurroundDirect]

        let map: AudioChannelBitmap

        switch channels {
        case 3: map = front.union(.bit_Center)
        case 4: map = front.union(back)
        case 5: map = front.union([.bit_Center]).union(back)
        case 6: map = front.union([.bit_Center, .bit_LFEScreen]).union(back)
        case 7: map = front.union([.bit_Center, .bit_LFEScreen, .bit_CenterSurround]).union(side)
        case 8: map = front.union([.bit_Center, .bit_LFEScreen]).union(back).union(side)
        default: return nil
        }

        var made = AudioChannelLayout()
        made.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
        made.mChannelBitmap = map

        return AVAudioChannelLayout(layout: &made)
    }

    /// The first entry of the parser's format list, which is the richest decoding of the
    /// stream (HE-AAC v2, then HE-AAC, then AAC-LC). Nil when the parser has no list.
    private static func richest(of parser: AudioFileStreamID) -> AudioStreamBasicDescription? {
        var size: UInt32 = 0
        var writable: DarwinBoolean = false

        guard AudioFileStreamGetPropertyInfo(
            parser, kAudioFileStreamProperty_FormatList, &size, &writable) == noErr,
              size >= UInt32(MemoryLayout<AudioFormatListItem>.size)
        else { return nil }

        let count = Int(size) / MemoryLayout<AudioFormatListItem>.size
        var items = [AudioFormatListItem](repeating: AudioFormatListItem(), count: count)

        guard AudioFileStreamGetProperty(
            parser, kAudioFileStreamProperty_FormatList, &size, &items) == noErr
        else { return nil }

        return items.first?.mASBD
    }

    /// A stream description as text that a person can read.
    ///
    /// The format id is four characters stored as a number. Printed as a number it is
    /// not readable.
    private static func describe(_ asbd: AudioStreamBasicDescription) -> String {
        let id = asbd.mFormatID
        let letters = [24, 16, 8, 0].map { UInt8((id >> $0) & 0xFF) }
        let name = letters.allSatisfy { (0x20...0x7E).contains($0) }
            ? String(decoding: letters, as: UTF8.self) : "\(id)"

        return "\(name) \(Int(asbd.mSampleRate))Hz \(asbd.mChannelsPerFrame)ch "
             + "\(asbd.mBitsPerChannel)bit fpp=\(asbd.mFramesPerPacket) "
             + "bpp=\(asbd.mBytesPerPacket) flags=\(asbd.mFormatFlags)"
    }

    // ── the parser ──

    private func opened() throws -> AudioFileStreamID {
        if let parser { return parser }

        var made: AudioFileStreamID?
        let mine = Unmanaged.passUnretained(self).toOpaque()

        // File type 0 means "detect it": the store serves AAC in an MP4 and MP3 as
        // themselves, and a wrong hint is worse than no hint.
        let failed = AudioFileStreamOpen(mine, { held, _, property, _ in
            Unmanaged<StreamedPcm>.fromOpaque(held).takeUnretainedValue().learned(property)
        }, { held, _, count, bytes, descriptions in
            Unmanaged<StreamedPcm>.fromOpaque(held).takeUnretainedValue()
                .parsed(count: count, bytes: bytes, descriptions: descriptions)
        }, 0, &made)

        guard failed == noErr, let made else { throw Trouble.unreadable }

        parser = made
        return made
    }

    /// The parser found a property. The format is the only one that matters here, and it can
    /// be read only after the parser reports that it is ready to produce packets.
    private func learned(_ property: AudioFileStreamPropertyID) {
        guard property == kAudioFileStreamProperty_ReadyToProducePackets,
              let parser = gate.withLock({ self.parser })
        else { return }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: asbd))

        guard AudioFileStreamGetProperty(
            parser, kAudioFileStreamProperty_DataFormat, &size, &asbd) == noErr
        else { return }

        // HE-AAC reports only its AAC-LC base layer as the data format: half the sample
        // rate, no SBR (the top octave) and, for v2, mono. The format list has the full
        // format first. Most internet radio at 32 to 64 kbps is HE-AAC.
        if let richest = Self.richest(of: parser), richest.mFormatID != asbd.mFormatID {
            asbd = richest
        }

        // **The log message describes the whole format, and each failing step logs separately.**
        // A message with only the format id would show that something about `flac` failed,
        // but not which step.
        let said = Self.describe(asbd)

        // **The layout is required above two channels.** `AVAudioFormat` cannot build a
        // multichannel format without one and returns nil. Without it a 5.1 record cannot
        // be played, while stereo files of the same codec play correctly.
        let laidOut = Self.layout(of: parser, channels: asbd.mChannelsPerFrame)

        guard let source = laidOut.flatMap({ AVAudioFormat(streamDescription: &asbd, channelLayout: $0) })
                        ?? AVAudioFormat(streamDescription: &asbd)
        else {
            let had = laidOut.map { "layout \($0.layoutTag)" } ?? "no layout"
            Self.log.error("no format for \(said, privacy: .public) (\(had, privacy: .public))")
            return
        }

        // **A format that is passed frame by frame must allow a frame to be copied out.** It
        // is checked here, where a reason can be logged. Otherwise a builder would return nil
        // for every block, and the record would never play and never say why.
        guard Self.inPackets(source) || Self.copyable(asbd) else {
            Self.log.error("\(said, privacy: .public) is not laid out in a way this can read")
            return
        }

        // Decoded at the record's own channel count and layout. **Mixing down to stereo is the
        // resampler's job** (below), for the same reason as the rate change: one converter
        // cannot decode and also change the channel layout. A surround record must be mixed
        // down somewhere, because everything after this point is one stereo pipeline.
        let native = laidOut.flatMap {
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate,
                          interleaved: false, channelLayout: $0)
        } ?? Self.pcm(rate: asbd.mSampleRate,
                      channels: AVAudioChannelCount(max(1, asbd.mChannelsPerFrame)))

        guard let native else {
            Self.log.error("no PCM to match \(said, privacy: .public)")
            return
        }

        var input = asbd
        var decoded = native.streamDescription.pointee
        var built: AudioConverterRef?

        guard AudioConverterNew(&input, &decoded, &built) == noErr, let decoder = built else {
            Self.log.error("nothing here can decode \(said, privacy: .public)")
            return
        }

        // **The cookie is required: without it an original (lossless) record does not play.**
        // It is set for every format that has one, not only for ALAC by name. A codec that
        // needs a cookie has one, and codecs without one are not affected.
        if var cookie = Self.cookie(of: parser).map([UInt8].init) {
            let taken = AudioConverterSetProperty(
                decoder, kAudioConverterDecompressionMagicCookie,
                UInt32(cookie.count), &cookie)

            if taken != noErr {
                Self.log.error("\(said, privacy: .public) would not take its \(cookie.count) byte cookie: \(Self.name(taken), privacy: .public)")
            }
        }

        // Only created when the formats differ. It is then a plain PCM resample, which
        // `AVAudioConverter` handles well.
        var resampler: AVAudioConverter?

        if native.sampleRate != output.sampleRate || native.channelCount != output.channelCount {
            guard let made = AVAudioConverter(from: native, to: output) else {
                let wanted = "\(Int(self.output.sampleRate))Hz \(self.output.channelCount)ch"
                Self.log.error("cannot resample \(said, privacy: .public) to \(wanted, privacy: .public)")
                return
            }

            // **Mix down, do not cut.** By default a converter that gets more channels than the
            // output keeps the first two and drops the rest. On a surround record that
            // silently loses the centre channel, which on a live album carries the vocal.
            // The record plays and sounds nearly right, but the singer is missing.
            made.downmix = native.channelCount > output.channelCount

            resampler = made
        }

        var begins: Int64 = 0
        var wide = UInt32(MemoryLayout<Int64>.size)
        _ = AudioFileStreamGetProperty(parser, kAudioFileStreamProperty_DataOffset, &wide, &begins)

        gate.withLock {
            self.source = source
            self.native = native
            self.decoder = decoder
            self.resampler = resampler
            self.dataBegins = begins
        }
    }

    /// Packets arrived. They are copied and not referenced: **the buffer belongs to the
    /// parser and is invalid as soon as this returns**, and a decoder that read it later
    /// would read whatever the next chunk wrote there.
    private func parsed(count: UInt32,
                        bytes: UnsafeRawPointer,
                        descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        // **No descriptions is a valid case, not a failure.** A format whose packets all have
        // the same size has nothing to describe, and sends no descriptions. Every
        // uncompressed record does this. What arrives is one block of N packets, and it is
        // kept as one block and not cut into N. A frame of stereo PCM is four bytes, and one
        // `Data` per four bytes would be about forty thousand allocations a second.
        guard let descriptions else {
            let size = Int(gate.withLock { source?.streamDescription.pointee.mBytesPerPacket } ?? 0)
            let whole = size * Int(count)
            guard whole > 0 else { return }

            let block = Data(bytes: bytes, count: whole)
            gate.withLock { pending.append(.run(block, size: size)) }
            return
        }

        var arrived: [Parsed] = []
        arrived.reserveCapacity(Int(count))

        for at in 0..<Int(count) {
            let description = descriptions[at]
            let from = bytes.advanced(by: Int(description.mStartOffset))
            arrived.append(.described(Data(bytes: from, count: Int(description.mDataByteSize)),
                                      description))
        }

        gate.withLock { pending.append(contentsOf: arrived) }
    }
}
