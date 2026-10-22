import Foundation
import RPMKit
import os

/// A track's bytes, read from the network or from the phone's own disk, and passed to a
/// decoder.
///
/// **It uses a delegate and not `bytes(for:)`.** The async byte sequence gives one
/// `UInt8` at a time, and a four minute track at 320 kbit/s is about ten million of
/// them. That works, but it spends about a tenth of a second of CPU copying bytes into a
/// buffer that the system already had in one piece. `didReceive` gives whatever data
/// arrived, which is the form the decoder wants.
public final class TrackFeed: NSObject, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "audio")

    public enum Trouble: Error, Equatable {
        /// The store answered with an error instead of a track. An expired signature gives
        /// a 403, which looks the same.
        case refused(Int)
        case dropped
    }

    /// The decoded audio. It is available at once, so the engine can be given it before
    /// the first byte arrives. It answers nil until it has a header, and the engine
    /// expects that.
    public let pcm = StreamedPcm()

    private let gate = NSLock()

    /// The address being read. Kept so a seek can request it again from another byte.
    private var url: URL?

    /// The copy on this phone that is read instead of the network, when there is one. Set
    /// only by ``start(file:)``, so a feed uses one source for its whole life and a seek
    /// reads from the same place as the start.
    private var file: URL?

    /// The read of ``file`` that is running. It is an object and not a flag, for the same
    /// reason as ``task``: a seek starts a second read before the first one notices it
    /// was replaced, and only the object identity says which bytes belong to which read.
    private var reading: FileRead?

    /// Held by a read while it checks that it is still the current read and passes its piece
    /// on, and by a seek during the swap and the jump. Without it a seek can happen between
    /// those two steps, and a piece from the old position is parsed as the first piece of
    /// the new position.
    private let pouring = NSLock()

    /// Whether the bytes are a stored object or an encode in progress. Set when the read
    /// starts, because it belongs to the address and not to a seek.
    private var kind: StreamKind = .stored
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var failure: Trouble?

    /// How many bytes the current request has received. A buffering indicator can use it,
    /// and it shows whether a stall is in the network or in the decoder.
    public private(set) var received = 0

    /// The byte offset where the running request was asked to start.
    private var began = 0

    /// How far into the **file** the download has reached, in bytes.
    ///
    /// This is not the same as ``received``, which counts only this request's bytes. A
    /// request with a range starts part way into the file, and a count that started at zero
    /// would look like the download had gone backwards. Compare a byte offset against this
    /// value.
    public var reached: Int { gate.withLock { began + received } }

    /// Whether the store has sent everything it is going to send.
    public private(set) var complete = false

    public override init() { super.init() }

    /// **How a request asks for the part of the record it wants.**
    ///
    /// There are three ways, and the source of the bytes decides which one is allowed, not
    /// the caller. An object in the store can be addressed by byte, so a jump is a range
    /// request. A rendition that is encoded while it is sent has no bytes to take a range
    /// from, because they do not exist yet. For that a jump is a second, and the encoder,
    /// which holds the whole record, starts again from there.
    ///
    /// **The byte case carries its landing second**, because both describe the same
    /// position. The byte is what the store is asked for. The second is what everything
    /// after it measures against: where a join lands, and whether a stream that stopped had
    /// reached the end of the record. If the landing second were missing, every seek would
    /// make the record look as if it ended half way through.
    enum Resume: Equatable {
        case theTop
        case theByte(Int, landingAt: Double)
        case theSecond(Double)

        /// The address to request. For a range it is the same address. For a live seek it is
        /// the same address with the second added to its existing query. A signed URL
        /// already has a query, and removing it would remove the signature.
        func address(of url: URL) -> URL {
            guard case .theSecond(let seconds) = self,
                  var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return url }

            // Written with a decimal point whatever the phone's locale is, because the server
            // parses it with its own culture. "94,5" parsed as 945 would seek past the end
            // of the record.
            let said = String(format: "%g", max(0, seconds))

            parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "from", value: said)]

            return parts.url ?? url
        }

        /// The range header value. Only the byte case has one.
        var range: String? {
            guard case .theByte(let offset, _) = self, offset > 0 else { return nil }
            return "bytes=\(offset)-"
        }

        /// The second in the record where the next byte to arrive belongs. Nil for the top,
        /// where the decoder needs no information.
        var landsAt: Double? {
            switch self {
            case .theTop: nil
            case .theByte(let offset, let second): offset > 0 ? second : nil
            case .theSecond(let second): max(0, second)
            }
        }

        /// The byte offset in the object where the request begins. It is zero for anything
        /// that is not a byte range: the bytes of a live encode are counted from the first
        /// byte it produced.
        var began: Int {
            guard case .theByte(let offset, _) = self else { return 0 }
            return max(0, offset)
        }
    }

    /// Starts reading the record from the beginning. Returns as soon as the request is
    /// sent. The bytes arrive later, and the decoder is what callers wait for.
    ///
    /// **A stream read from the network only goes forwards**, so a seek needs a new
    /// request. That is ``moveTo(_:)``. Both go through ``open(_:_:)``, so the way a jump
    /// is requested always matches the kind of stream.
    ///
    /// - Parameter kind: whether these bytes are a stored object or an encode in progress.
    ///   Required, with no default: it decides what a seek does, and a wrong value makes
    ///   the position indicator move while the music does not.
    public func start(_ url: URL, kind: StreamKind) {
        gate.withLock { self.kind = kind }
        open(url, .theTop)
    }

    /// Starts reading a record that is on this phone. Nothing is signed or fetched, so it
    /// plays whatever the state of the network is.
    ///
    /// **The same decoder, fed in the same way.** The bytes go through ``StreamedPcm``
    /// exactly as the network's bytes do. A downloaded record and a streamed record differ
    /// only in where the bytes come from. The engine, the look-ahead, the seek and the
    /// ending are the same code.
    public func start(file: URL) {
        gate.withLock {
            self.kind = .stored
            self.file = file
        }
        read(file, .theTop)
    }

    private func open(_ url: URL, _ resume: Resume) {
        var request = URLRequest(url: resume.address(of: url))
        request.timeoutInterval = 20
        if let range = resume.range { request.setValue(range, forHTTPHeaderField: "Range") }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)

        // **The new request is set as current before the old one is cancelled. The order
        // matters.** A cancel is asynchronous: data that was already on the wire still
        // arrives afterwards, and until the swap those bytes look like the expected ones.
        // See ``stillPulling(_:)``.
        let (was, itsSession) = gate.withLock { () -> (URLSessionDataTask?, URLSession?) in
            let old = (self.task, self.session)

            self.url = url
            self.session = session
            self.task = task
            self.began = resume.began
            self.received = 0
            self.complete = false
            self.failure = nil

            return old
        }

        was?.cancel()
        itsSession?.invalidateAndCancel()

        // **The parser must be told about every jump, however it was requested.** It is told
        // here and not by the caller, because this is the one place that is after the old
        // request stopped counting and before the first byte of the new one. If it were told
        // earlier, the last bytes of the old request would be read as the first bytes of the
        // new one, and they decode to nothing.
        if let landsAt = resume.landsAt { pcm.expectAJump(landingAt: landsAt) }

        task.resume()
    }

    /// Why it stopped, if it stopped with an error. Nil while it is running and nil when it
    /// finished normally.
    public var trouble: Trouble? { gate.withLock { failure } }

    /// Asks the store for the same track from a different second.
    ///
    /// **This is a new request, because a stream cannot be rewound.** The decoder says
    /// which byte holds that second, the request carries a range, and the decoder is told
    /// to expect bytes from another place in the file. Returns the second it will actually
    /// land on, which is the start of a packet and not exactly the requested number. Returns
    /// nil for a stream that cannot be seeked.
    ///
    /// **An estimate is good enough here.** A seek that lands a fifth of a second from the
    /// requested position cannot be heard. For FLAC, `AudioFileStreamSeek` only gives an
    /// estimate: the same second gives byte 47420, 46620 and 46541 as more of the file
    /// arrives. An estimate is not exact enough to join two streams without a gap.
    public func moveTo(_ seconds: Double) -> Double? {
        let (url, file, kind) = gate.withLock { (self.url, self.file, self.kind) }

        // A copy on the phone is byte-addressable, the same as an object in the store.
        if let file {
            guard let landing = pcm.byteToHear(seconds) else { return nil }
            read(file, .theByte(Int(landing.byte), landingAt: landing.second))
            return landing.second
        }

        guard let url else { return nil }

        switch kind {
        case .live:
            // The parser is not asked for a byte, and it could not answer: it has only seen an
            // encode that started where the last request said, and only the encoder holds
            // the whole record. So the second goes to the encoder unchanged. The result is
            // exact and not an estimate, even for a second the download has not reached yet,
            // which a range read of a file that is still being written cannot do.
            let landing = max(0, seconds)
            open(url, .theSecond(landing))
            return landing

        case .stored:
            guard let landing = pcm.byteToHear(seconds) else { return nil }

            open(url, .theByte(Int(landing.byte), landingAt: landing.second))

            return landing.second
        }
    }

    public func stop() {
        let (task, session, reading) = gate.withLock { (self.task, self.session, self.reading) }

        task?.cancel()
        session?.invalidateAndCancel()

        // Like the task, the read stays as the current one. It notices it was put down and
        // tells the decoder before it exits.
        reading?.putDown()

        // **The task is kept.** It identifies which callbacks belong to the stream, and this
        // task's callbacks still belong to it: a request that was stopped is a stream that
        // ended, and the decoder is told so. The task stops being the current one only when
        // a new task replaces it.
        gate.withLock { self.session = nil }
    }

    /// Whether a callback belongs to the request being pulled now.
    ///
    /// **A cancel is asynchronous.** Data that was already on the wire when the seek was
    /// requested arrives after the ranged request has started. It is the start of the
    /// record, so if it reached the parser it would be bytes from the wrong place marked
    /// with the discontinuity that was meant for the range. Its *ending* is worse: `finish`
    /// on a stream that was just pointed somewhere else says the record is over. The pump
    /// then finds a source with no data and none coming, and the record is removed from the
    /// player a few seconds in.
    ///
    /// The answer comes from comparing the task and not from a flag, because the comparison
    /// is true whenever it is asked and does not depend on which dispatcher turn it runs in.
    private func stillPulling(_ task: URLSessionTask) -> Bool {
        gate.withLock { self.task === task }
    }

    deinit { stop() }

    // ── a copy on the phone ──

    /// How many bytes of a file are given to the decoder at a time. The pieces from the
    /// network are about this size, so the parser sees the same piece sizes for both.
    static let filePiece = 256 * 1024

    /// One pass over a file, from a byte offset to the end, or until it is put down.
    final class FileRead: @unchecked Sendable {
        private let lock = NSLock()
        private var down = false

        func putDown() { lock.withLock { down = true } }
        var isDown: Bool { lock.withLock { down } }
    }

    /// Reads a copy on the phone into the decoder, from where `resume` says.
    ///
    /// **First the swap, then the jump, then the read.** ``open(_:_:)`` uses the same order
    /// for the same reason: the old read may still be between two pieces, and until the
    /// swap its next piece looks like a piece of the new read.
    private func read(_ file: URL, _ resume: Resume) {
        let mine = FileRead()

        pouring.lock()
        let was = gate.withLock { () -> FileRead? in
            let old = self.reading
            self.reading = mine
            self.began = resume.began
            self.received = 0
            self.complete = false
            self.failure = nil
            return old
        }

        was?.putDown()

        if let landsAt = resume.landsAt { pcm.expectAJump(landingAt: landsAt) }
        pouring.unlock()

        let from = UInt64(resume.began)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.pour(file, from: from, as: mine)
        }
    }

    /// Whether a read is still the one this feed wants.
    private func stillReading(_ read: FileRead) -> Bool {
        gate.withLock { self.reading === read }
    }

    /// The read itself, on a worker queue. It ends the decoder's stream with whichever of the
    /// three endings happened, as the network delegate does.
    private func pour(_ file: URL, from: UInt64, as read: FileRead) {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            Self.log.error("the copy on the phone would not open: \(file.lastPathComponent, privacy: .public)")
            end(read, .theBytesStopped, failing: true)
            return
        }
        defer { try? handle.close() }

        do { try handle.seek(toOffset: from) }
        catch { end(read, .theBytesStopped, failing: true); return }

        while true {
            // Replaced by a seek: the new read now owns the decoder.
            guard stillReading(read) else { return }

            // Stopped while still this feed's current read: the stream ended.
            if read.isDown { end(read, .itWasPutDown, failing: false); return }

            let piece: Data
            do { piece = try handle.read(upToCount: Self.filePiece) ?? Data() }
            catch { end(read, .theBytesStopped, failing: true); return }

            if piece.isEmpty { end(read, .theFileRanOut, failing: false); return }

            let fed: Bool = pouring.withLock {
                guard stillReading(read) else { return false }
                gate.withLock { received += piece.count }

                do { try pcm.take(piece); return true }
                catch {
                    Self.log.error("the copy on the phone is unreadable after \(self.received) bytes")
                    gate.withLock { failure = .dropped }
                    pcm.finish(.theBytesWouldNotParse)
                    return false
                }
            }
            guard fed else { return }
        }
    }

    /// Ends the decoder's stream, **if this read still owns it**. It uses the same lock as
    /// the swap in a seek, so an old read that reaches the end of the file cannot mark the
    /// new read's stream as over.
    private func end(_ read: FileRead, _ why: Ending.Why, failing: Bool) {
        pouring.withLock {
            guard stillReading(read) else { return }
            gate.withLock {
                if failing { failure = .dropped }
                complete = !failing && why == .theFileRanOut
            }
            pcm.finish(why)
        }
    }
}

extension TrackFeed: URLSessionDataDelegate {
    /// A computer on the home network presents a self-signed certificate made from its own key.
    /// ``PeerPins`` checks it against the key the computer advertised. Every other host gets
    /// the system's normal check, so the phone, which pins nothing, is not affected.
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let (disposition, credential) = PeerPins.shared.answer(challenge)
        completionHandler(disposition, credential)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard stillPulling(dataTask) else {
            completionHandler(.cancel)
            return
        }

        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        // 206 is the answer to a range request and is as valid as 200.
        guard (200...299).contains(http.statusCode) else {
            gate.withLock { failure = .refused(http.statusCode) }
            pcm.finish(.theStoreRefused(http.statusCode))
            completionHandler(.cancel)
            return
        }

        // A record encoded while it is sent has no length of its own, so the transcoder states
        // it in this header. Without it, a stream the encoder ended early looks like the end of
        // the record. `Double` reads a decimal point whatever the phone's locale is.
        if let said = http.value(forHTTPHeaderField: Self.lengthHeader),
           let seconds = Double(said), seconds > 0 {
            pcm.statesItsLength(seconds)
        }

        completionHandler(.allow)
    }

    /// The header a live encode states the whole record's length in, in seconds.
    static let lengthHeader = "X-RPM-Duration"

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive data: Data) {
        guard stillPulling(dataTask) else { return }

        gate.withLock { received += data.count }

        do { try pcm.take(data) }
        catch {
            // The bytes cannot be opened by this phone. More data will not help, so the
            // download stops instead of downloading the rest.
            Self.log.error("stream unreadable after \(self.received) bytes")
            gate.withLock { failure = .dropped }
            pcm.finish(.theBytesWouldNotParse)
            dataTask.cancel()
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didCompleteWithError error: (any Error)?) {
        guard stillPulling(task) else { return }

        // **A cancellation is not a fault.** It is the normal end of every track that was
        // skipped, and recording it as trouble would show an error every time the user
        // pressed next.
        let cancelled = (error as? URLError)?.code == .cancelled

        if error != nil, !cancelled {
            gate.withLock { failure = .dropped }
        }

        gate.withLock { complete = failure == nil }

        // Whatever arrived is still worth decoding, so the decoder is told that the stream is
        // over and the data is kept. **The decoder is also told which of the three endings
        // this is.** A socket that closed half way through a record must not look like a
        // record that finished, or the queue would move on to the next song.
        pcm.finish(cancelled ? .itWasPutDown : error == nil ? .theFileRanOut : .theBytesStopped)
    }
}
