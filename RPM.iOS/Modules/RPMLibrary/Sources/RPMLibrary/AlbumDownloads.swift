import Foundation
import Observation
import RPMKit
import os

/// Downloads albums to the phone so they play without a network.
///
/// **A background `URLSession` does the hard parts.** The
/// system carries on with the transfers while the app is suspended or has been closed, waits
/// for a network when there is none, and picks up again on its own when one comes back. The
/// app is woken when the session has finished, and the next tracks are asked for then.
///
/// **What to fetch is derived, never remembered.** The book says which tracks are wanted and
/// which have a file; the session says which are in flight. ``pump()`` takes the difference
/// whenever it is asked, so it is correct to call from anywhere and at any time: the network
/// coming back, the app coming forward, a download finishing, the key being pressed.
///
/// **Only stored objects are downloaded.** A rate the store has not made yet is signed as a
/// live encode, and a live encode that stops part way still answers 200. So the track waits
/// in ``RenditionWait`` while the store makes it, and is signed again until the store has
/// the whole object. The wait runs only while the app is running: a suspended app picks it
/// up when it comes forward.
///
/// Everything here runs on the main actor, but every `await` is a suspension point that
/// another call can enter through. That is why ``pump()`` folds overlapping calls into one
/// and why a track is claimed in `inFlight` before it is signed.
@MainActor
@Observable
public final class AlbumDownloads {
    /// What an album is, as far as this phone is concerned. An album nobody asked for has no
    /// standing at all, rather than a case for it: see ``standing(of:)``.
    public enum Standing: Sendable, Equatable {
        /// Some tracks still to come. `fraction` counts the parts of tracks that have
        /// arrived, so a ten-track album does not sit at nought for its whole first track.
        ///
        /// `preparing` is true while nothing is transferring and some of the tracks still
        /// to come are waiting for the store to make them at the chosen rate. See
        /// ``RenditionWait``.
        case downloading(have: Int, of: Int, fraction: Double, preparing: Bool)

        /// Every track has a file.
        case onPhone

        /// Some tracks failed ``mostGoes`` times and nothing is being tried for them. The
        /// key offers to try again.
        case stuck(have: Int, of: Int)
    }

    /// How many tracks are transferred at once. Enough to keep a connection busy between
    /// one finishing and the next being signed; few enough that every address is used well
    /// inside its signature's life.
    public static let atOnce = 4

    /// How many times one track is tried before its album is called stuck.
    public static let mostGoes = 3

    /// The session's name. One per app, and the same on every launch, which is how a
    /// relaunched app reconnects to transfers the system carried on with.
    public static let sessionName = "com.rpm.player.downloads"

    /// Handed over by the app delegate when the system wakes the app for this session, and
    /// called when the session has said everything it had to say. See
    /// `UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    public static var wokenFor: (() -> Void)?

    public let book: DownloadBook

    /// Every album with a standing, redrawn after each change. What the screens read.
    public private(set) var shown: [String: Standing] = [:]

    /// The keys of albums that have at least one track on the phone. What decides which
    /// records are greyed on the wall while offline.
    public private(set) var onPhone: Set<String> = []

    private let reach: NetworkReach
    private let sign: @Sendable (String, Int) async throws
        -> (url: URL, kilobits: Int, kind: StreamKind)
    private let make: @Sendable ([String], Int) async throws -> Void
    private let rate: @MainActor () -> Int

    /// Tracks with a transfer in the session, or being signed for one.
    private var inFlight: Set<String> = []

    /// How far each transfer has got, as a fraction of the track.
    private var partial: [String: Double] = [:]

    /// Failed goes per track. In memory only: a relaunch is a fresh three goes, which is
    /// what somebody who closed the app and opened it again expects.
    private var goes: [String: Int] = [:]

    /// Tracks the store is still making at the chosen rate. In memory only, like ``goes``:
    /// after a relaunch the first sign finds out again.
    private var making = RenditionWait()

    /// The next pump for tracks in ``making``. One at a time; each pass replaces it.
    private var wake: Task<Void, Never>?

    private var pumping = false
    private var pumpAgain = false

    private let relay: Relay
    private let session: URLSession

    private static let log = Logger(subsystem: "com.rpm.player", category: "downloads")

    /// - Parameters:
    ///   - sign: a signed address for one of this account's own tracks at a rate, the rate it
    ///     is actually served at, and whether it is a stored object or a live encode.
    ///   - make: asks the store to make these tracks at a rate. Used when a sign answers with
    ///     a live encode, which a download never takes.
    ///   - rate: the rate to ask for, read at the start of each pass.
    public init(book: DownloadBook, reach: NetworkReach,
                sign: @escaping @Sendable (String, Int) async throws
                    -> (url: URL, kilobits: Int, kind: StreamKind),
                make: @escaping @Sendable ([String], Int) async throws -> Void,
                rate: @escaping @MainActor () -> Int) {
        self.book = book
        self.reach = reach
        self.sign = sign
        self.make = make
        self.rate = rate

        let relay = Relay(book: book)
        self.relay = relay

        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionName)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: relay, delegateQueue: queue)

        relay.owner = self
        redraw()
    }

    /// Picks up the transfers the system carried on with while the app was away, then asks
    /// for whatever is still missing. Called once, at launch.
    public func begin() async {
        let tasks = await session.allTasks
        for task in tasks {
            guard let said = Relay.read(task.taskDescription) else { task.cancel(); continue }

            // A transfer for a track nobody wants any more: an album removed while the app
            // was closed and the system was still fetching it.
            guard book.isWanted(said.rpmId) else { task.cancel(); continue }
            inFlight.insert(said.rpmId)
        }
        redraw()
        await pump()
    }

    // ── what the screens ask ──

    /// Where an album stands, or nil for one nobody asked for.
    public func standing(of key: String) -> Standing? { shown[key] }

    /// Whether one track has a file on the phone.
    ///
    /// The answer is the book's, but ``shown`` is read first: it is redrawn on every change
    /// to the book, and reading it is what makes a view that asks this draw again when a
    /// track lands or is removed.
    public func isOnPhone(_ rpmId: String) -> Bool {
        _ = shown
        return book.held(rpmId) != nil
    }

    /// The albums asked for, newest first, with what each takes on the phone.
    public var list: [(album: CloudAlbum, bytes: Int64, standing: Standing)] {
        _ = shown
        return book.albums.compactMap { album in
            guard let standing = shown[album.key] else { return nil }
            return (album.asAlbum, book.bytes(of: album.key), standing)
        }
    }

    /// Everything the downloads take on the phone.
    public var bytes: Int64 {
        _ = shown
        return book.albums.reduce(0) { $0 + book.bytes(of: $1.key) }
    }

    // ── what the keys do ──

    /// Downloads an album, or tries again for one that is stuck.
    public func download(_ album: CloudAlbum) {
        book.want(album)
        for track in album.tracks { goes[track.rpmId] = nil }
        making.forget(album.tracks.map(\.rpmId))
        redraw()
        Task { await pump() }
    }

    /// Takes albums off the phone, and stops whatever was still coming for them.
    public func remove(_ keys: Set<String>) {
        let gone = book.drop(keys)
        guard !gone.isEmpty else { redraw(); return }

        for rpmId in gone {
            partial[rpmId] = nil
            goes[rpmId] = nil
        }
        making.forget(gone)

        Task {
            for task in await session.allTasks {
                if let said = Relay.read(task.taskDescription), gone.contains(said.rpmId) {
                    task.cancel()
                }
            }
        }
        redraw()
    }

    /// Signing out: every file goes, and every transfer stops.
    public func forgetEverything() {
        book.forgetAll()
        inFlight = []
        partial = [:]
        goes = [:]
        making.forgetAll()
        wake?.cancel()
        wake = nil
        Task { for task in await session.allTasks { task.cancel() } }
        redraw()
    }

    // ── the work ──

    /// Asks for whatever is missing, up to ``atOnce`` at a time.
    ///
    /// Safe to call from anywhere and as often as anybody likes: a call that arrives while
    /// one is running is folded into it rather than run beside it.
    public func pump() async {
        guard !pumping else { pumpAgain = true; return }
        pumping = true
        defer { pumping = false }

        repeat {
            pumpAgain = false
            await pumpOnce()
        } while pumpAgain
    }

    private func pumpOnce() async {
        // The session would wait for a network by itself, but the signature would not: it
        // is one of this app's own requests and the gate refuses it. Nothing to do until
        // the network comes back, which calls this again.
        guard reach.now.isOnline else { return }

        // Read once per pass, so every track in one pass is asked for at the same rate. A
        // change of setting is picked up by the next pass, which the setting's own change
        // starts.
        let asked = rate()

        let waiting = book.missing.filter {
            !inFlight.contains($0) && (goes[$0] ?? 0) < Self.mostGoes
                && making.isDue($0, kilobits: asked, now: Date())
        }

        var more = false

        for rpmId in waiting.prefix(max(0, Self.atOnce - inFlight.count)) {
            // Claimed before the await, so a second pump arriving in the gap does not sign
            // the same track again.
            inFlight.insert(rpmId)

            do {
                let signed = try await sign(rpmId, asked)

                // Removed while it was being signed.
                guard book.isWanted(rpmId) else { inFlight.remove(rpmId); continue }

                // Not made at this rate yet. A download never takes the live encode: it has
                // answered 200 before it knows whether it will finish, so a cut-off track
                // would be kept as a whole one. The store is asked to make it, and the
                // stored object is downloaded once there is one.
                if signed.kind == .live {
                    inFlight.remove(rpmId)
                    switch making.stillMaking(rpmId, kilobits: asked, now: Date()) {
                    case .new:
                        // The slot is free again, so the next track can be signed in this
                        // pump rather than at the next wake.
                        more = true
                    case .waiting:
                        break
                    case .overdue:
                        goes[rpmId, default: 0] += 1
                        if (goes[rpmId] ?? 0) >= Self.mostGoes { making.forget([rpmId]) }
                        Self.log.error("\(rpmId, privacy: .public) was not made at \(asked) kbps in time for a download")
                    }
                    continue
                }

                making.forget([rpmId])

                let task = session.downloadTask(with: signed.url)
                task.taskDescription = Relay.write(rpmId: rpmId, kilobits: signed.kilobits)
                task.resume()
            } catch {
                inFlight.remove(rpmId)

                // A refusal from the gate is the network, not the track, and is not a go.
                if case .offline? = error as? RPMError { return }
                goes[rpmId, default: 0] += 1
                Self.log.error("could not sign \(rpmId, privacy: .public) for a download: \(String(describing: error), privacy: .public)")
            }
        }

        await askTheStoreToMake()
        redraw()
        scheduleWake()

        if more { pumpAgain = true }
    }

    /// Asks the store to make every track waiting on it that it has not been asked for yet,
    /// **and every other track still to come at the same rate**, in one ask.
    ///
    /// All of them at once because of how the store runs the transcoder. An ask starts it at
    /// most once every thirty seconds, and a run reads the want list once, at its start.
    /// Tracks asked for in later pieces, as the slots free up, land after that read and wait
    /// for the five-minute schedule. Asking for tracks that turn out to exist costs nothing:
    /// the store counts them as ready and makes nothing.
    ///
    /// An ask that fails is left unasked and sent again on the next pass, so a lost request
    /// costs one backoff and not the whole ``RenditionWait/giveUp``.
    private func askTheStoreToMake() async {
        for (kilobits, waiting) in making.unasked {
            let wanted = Set(waiting.filter { book.isWanted($0) })
            making.forget(waiting.filter { !wanted.contains($0) })
            guard !wanted.isEmpty else { continue }

            // In the book's order, which is the order the transcoder is handed them.
            let send = book.missing.filter {
                wanted.contains($0) || (!inFlight.contains($0)
                    && (goes[$0] ?? 0) < Self.mostGoes
                    && !making.wasAsked($0, kilobits: kilobits))
            }
            let ahead = send.filter { !wanted.contains($0) }

            do {
                try await make(send, kilobits)
                making.asked(Array(wanted), kilobits: kilobits)
                making.askedAhead(ahead, kilobits: kilobits)
            } catch {
                if case .offline? = error as? RPMError { return }
                Self.log.error("could not ask for \(send.count) tracks at \(kilobits) kbps: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Pumps again when the next waiting track is due to be asked about.
    ///
    /// Never sooner than five seconds from now. A track that is due but was not signed
    /// because every slot was taken would otherwise be a wake due at once, and a pump that
    /// wakes itself at once is a loop; those tracks are signed when a transfer finishes,
    /// which pumps.
    private func scheduleWake() {
        wake?.cancel()
        wake = nil
        guard let next = making.nextCheck else { return }

        let delay = max(next.timeIntervalSinceNow, 5)
        wake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }

            // Let go of the handle before pumping. The pump ends by scheduling the next
            // wake, which cancels whatever `wake` holds; if that were still this task, the
            // pump would cancel itself and every sign after that point would throw.
            self.wake = nil
            await self.pump()
        }
    }

    // ── what the session says, on the main actor ──

    fileprivate func moved(_ rpmId: String, fraction: Double) {
        guard inFlight.contains(rpmId) else { return }

        // Every two percent is plenty for a ring, and the session says this many times a
        // second.
        let was = partial[rpmId] ?? 0
        guard fraction - was >= 0.02 || fraction >= 1 else { return }
        partial[rpmId] = fraction
        redraw()
    }

    fileprivate func finished(_ rpmId: String, kept: Bool, counts: Bool) {
        inFlight.remove(rpmId)
        partial[rpmId] = nil

        if !kept, counts, book.isWanted(rpmId) { goes[rpmId, default: 0] += 1 }

        redraw()
        Task { await pump() }
    }

    /// The system woke the app because the session had finished. The next tracks are asked
    /// for **before** the system is told it may suspend the app again, or the app is put
    /// back to sleep with nothing queued and the album stops half way.
    fileprivate func sessionIsDone() async {
        await pump()

        // A pump already running when this arrived folded this one into itself; wait for
        // it rather than answering while it is still signing.
        for _ in 0..<100 where pumping { try? await Task.sleep(for: .milliseconds(50)) }

        let handler = Self.wokenFor
        Self.wokenFor = nil
        handler?()
    }

    /// Works out every standing again from the book, the transfers in flight and the goes.
    private func redraw() {
        var next: [String: Standing] = [:]
        var some: Set<String> = []

        for album in book.albums {
            guard let (have, of) = book.count(of: album.key) else { continue }
            if have > 0 { some.insert(album.key) }

            if have == of { next[album.key] = .onPhone; continue }

            let left = album.tracks.map(\.rpmId).filter { book.held($0) == nil }
            let trying = left.contains {
                inFlight.contains($0) || (goes[$0] ?? 0) < Self.mostGoes
            }

            if trying {
                let arriving = left.reduce(0.0) { $0 + (partial[$1] ?? 0) }
                let fraction = of > 0 ? (Double(have) + arriving) / Double(of) : 0
                let preparing = !left.contains { inFlight.contains($0) }
                    && left.contains { making.isWaiting($0) }
                next[album.key] = .downloading(have: have, of: of, fraction: fraction,
                                               preparing: preparing)
            } else {
                next[album.key] = .stuck(have: have, of: of)
            }
        }

        if next != shown { shown = next }
        if some != onPhone { onPhone = some }
    }

    // ── the session's delegate ──

    /// The session's delegate, on the session's own queue.
    ///
    /// A class of its own because a background session holds its delegate strongly for as
    /// long as it lives, and the delegate's first job, moving a finished file, has to happen
    /// before the callback returns, which is before any hop to the main actor could.
    private final class Relay: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let book: DownloadBook
        weak var owner: AlbumDownloads?

        /// Tracks whose file was put in place, by the task that brought it. Read when the
        /// same task says it has completed, which the session always says after the file.
        private var kept: [Int: Bool] = [:]
        private let lock = NSLock()

        init(book: DownloadBook) { self.book = book }

        /// A task names its track and the rate it was signed at, so a relaunched app knows
        /// both without anything held in memory.
        static func write(rpmId: String, kilobits: Int) -> String { "\(kilobits)|\(rpmId)" }

        static func read(_ said: String?) -> (rpmId: String, kilobits: Int)? {
            guard let said, let bar = said.firstIndex(of: "|"),
                  let kilobits = Int(said[..<bar])
            else { return nil }
            return (String(said[said.index(after: bar)...]), kilobits)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            guard let said = Self.read(downloadTask.taskDescription) else { return }

            // A 403 is an expired signature and a 404 a track gone from the store. Either
            // way the body is not the record, and it is not kept.
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            let good = (200...299).contains(status)
                && book.keep(said.rpmId, from: location, kilobits: said.kilobits)

            lock.withLock { kept[downloadTask.taskIdentifier] = good }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0,
                  let said = Self.read(downloadTask.taskDescription) else { return }

            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let rpmId = said.rpmId
            Task { @MainActor [weak owner] in owner?.moved(rpmId, fraction: fraction) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: (any Error)?) {
            guard let said = Self.read(task.taskDescription) else { return }

            let good = lock.withLock { kept.removeValue(forKey: task.taskIdentifier) } ?? false

            // A cancel is somebody removing the album, not the track failing.
            let cancelled = (error as? URLError)?.code == .cancelled
            let rpmId = said.rpmId

            Task { @MainActor [weak owner] in
                owner?.finished(rpmId, kept: good, counts: !cancelled)
            }
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            Task { @MainActor [weak owner] in await owner?.sessionIsDone() }
        }
    }
}
