import Foundation
import RPMRadio
import os

/// A station's bytes, read from the network and passed to a decoder.
///
/// **A station is a source like any other.** It goes through the same engine as a record, so
/// it can be cast, levelled and drawn like a record. Playing it with `AVQueuePlayer` would
/// give a second player with its own output, which cannot be cast, levelled or drawn and
/// does not go through anything else in the app.
///
/// It differs from ``TrackFeed`` in the metadata. When a station is asked for metadata, it
/// mixes the text into the audio bytes, so the bytes must be separated before the decoder
/// sees them. `IcyReader` does that.
public final class StationFeed: NSObject, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "audio")

    public enum Trouble: Error, Equatable {
        /// The server answered with an error status instead of a stream.
        case refused(Int)

        /// It opened and then stopped, or the bytes were not audio.
        case dropped
    }

    /// The decoded audio. It is available at once, so the engine can be given it before
    /// the first byte arrives.
    public let pcm = StreamedPcm()

    private let gate = NSLock()

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var failure: Trouble?

    /// Separates the text from the audio. It is replaced when the response arrives, with
    /// the interval at which the station inserts text.
    private var icy = IcyReader(every: 0)

    /// How many bytes of audio have been received. The text is not counted.
    public private(set) var received = 0

    /// Called when the station announces a track, on the thread the bytes arrived on.
    /// **Not de-duplicated here**: `IcyReader` reports only when the title changes.
    public var announced: (@Sendable (String) -> Void)?

    /// Called when the station stops answering. This is how the end of a station that has
    /// gone off the air shows.
    public var stopped: (@Sendable (Trouble) -> Void)?

    public override init() { super.init() }

    /// Starts pulling.
    ///
    /// **No range and no offset**: a station has no beginning to measure an offset from,
    /// so there is no `moveTo` here.
    public func start(_ url: URL) {
        stop()

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        // This header turns the titles on. A station without metadata ignores it and answers
        // without `icy-metaint`, which is read as zero.
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")

        // Some Icecast servers answer differently, or not at all, without a User-Agent.
        request.setValue("RPM/1.0", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)

        gate.withLock {
            self.session = session
            self.task = task
            self.received = 0
            self.failure = nil
            self.icy = IcyReader(every: 0)
        }

        task.resume()
    }

    /// Why it stopped, if it stopped with an error.
    public var trouble: Trouble? { gate.withLock { failure } }

    /// The title the station last announced.
    public var title: String? { gate.withLock { icy.title } }

    public func stop() {
        let (task, session) = gate.withLock { (self.task, self.session) }

        task?.cancel()
        session?.invalidateAndCancel()

        gate.withLock {
            self.task = nil
            self.session = nil
        }
    }

    deinit { stop() }
}

extension StationFeed: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            gate.withLock { failure = .refused(http.statusCode) }
            pcm.finish(.theStoreRefused(http.statusCode))
            completionHandler(.cancel)

            let said = Trouble.refused(http.statusCode)
            stopped?(said)
            return
        }

        let every = IcyReader.metaInt(of: response)
        gate.withLock { icy = IcyReader(every: every) }

        Self.log.notice("station open, metaint \(every, privacy: .public)")
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive data: Data) {
        // **The text is removed before the decoder sees any of it.** A decoder given the
        // raw stream would try to decode `StreamTitle='...'` as audio, which gives a click
        // at best.
        let said = announced
        let audio = gate.withLock { icy.take(data) { title in said?(title) } }

        guard !audio.isEmpty else { return }
        gate.withLock { received += audio.count }

        do { try pcm.take(audio) }
        catch {
            Self.log.error("station unreadable after \(self.received) bytes")
            gate.withLock { failure = .dropped }
            pcm.finish(.theBytesWouldNotParse)
            dataTask.cancel()
            stopped?(.dropped)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didCompleteWithError error: (any Error)?) {
        // **A cancellation is not a fault**: it happens when another station is tuned.
        //
        // A station has no end of its own, so a request that completed without an error
        // means the station stopped sending, not that it finished. Only a cancel is
        // intentional.
        guard let error, (error as? URLError)?.code != .cancelled else {
            pcm.finish((error as? URLError)?.code == .cancelled ? .itWasPutDown : .theBytesStopped)
            return
        }

        gate.withLock { failure = .dropped }
        pcm.finish(.theBytesStopped)
        stopped?(.dropped)
    }
}
