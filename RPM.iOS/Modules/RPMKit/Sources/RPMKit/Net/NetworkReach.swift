import Foundation
import Network

/// Supplies network path readings. This is a protocol so that a test can supply readings without a
/// real network. The one type that touches `Network` is `NWPathWatcher`, below.
public protocol PathWatcher: Sendable {
    /// Every reading the system reports, for as long as the stream is kept.
    func readings() -> AsyncStream<Reach>
}

/// The real watcher, backed by `NWPathMonitor`.
public struct NWPathWatcher: PathWatcher {
    public init() {}

    public func readings() -> AsyncStream<Reach> {
        AsyncStream { continuation in
            let held = Held()

            held.monitor.pathUpdateHandler = { path in
                continuation.yield(Reach.reading(satisfied: path.status == .satisfied,
                                                 expensive: path.isExpensive,
                                                 constrained: path.isConstrained))
            }

            // Ending the stream stops the monitor. Otherwise each subscriber leaks a monitor. A phone
            // that wakes up twenty times a day would end up with twenty monitors all reporting.
            continuation.onTermination = { _ in held.monitor.cancel() }

            held.monitor.start(queue: DispatchQueue(label: "rpm.reach"))
        }
    }

    /// `NWPathMonitor` is not `Sendable`, but the closures above are. The monitor is used only in this
    /// construction and in the termination handler. The termination handler cannot run before this
    /// construction does. The box records that, because the compiler cannot check it.
    private final class Held: @unchecked Sendable {
        let monitor = NWPathMonitor()
    }
}

/// The one place the app asks how far it can reach. It is also the gate that requests check before
/// they open a socket.
///
/// This is not an actor, on purpose. `Transport` asks it before every request, from whatever isolation
/// the caller is on. An `await` there would add a suspension point in front of a check that exists to
/// be cheaper than the request it guards. So the reading is kept under a lock, and ``now`` can be read
/// from any thread.
///
/// **Online is believed at once. Offline has to last.** A Wi-Fi to cellular handoff, a lift, or a phone
/// waking up can each cause a short `.unsatisfied` reading that recovers by itself. Publishing those would
/// show a banner and refuse a request that would have worked. So an offline reading waits ``settling``, and
/// it is published only if the reading at the end of the wait is still offline. The check uses what is true
/// at the end of the wait, not a note made at the start. So two overlapping waits agree and do not race.
public final class NetworkReach: @unchecked Sendable {
    /// How long the line must look gone before the app reports it.
    public static let settling = Duration.milliseconds(1200)

    /// How long one request that finds the line dead blocks all other requests.
    ///
    /// This matches the ten seconds that the desktop holds a "not online" answer, for the same reason.
    /// Someone is waiting to see the screen change, so the period must be short.
    public static let holdingAway = Duration.seconds(10)

    private let lock = NSLock()
    private let watcher: any PathWatcher
    private let settling: Duration

    /// The most recent path reading, whether or not it has been published.
    private var latest = Reach.unknown

    /// The settled reading that is published to everyone else.
    private var told = Reach.unknown

    private var listeners: [UUID: AsyncStream<Reach>.Continuation] = [:]
    private var watching: Task<Void, Never>?
    private var started = false

    /// Until when a request that found the line dead keeps the gate closed. See ``doubt()``.
    private var doubtedUntil: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    public init(watching watcher: any PathWatcher = NWPathWatcher(),
                settling: Duration = NetworkReach.settling) {
        self.watcher = watcher
        self.settling = settling
    }

    /// **The gate's answer**: the path's own reading, combined with what the last request found out.
    ///
    /// This decides whether a socket is opened. It is not the same question as ``changes``. `NWPath` can
    /// report `.satisfied` for hotel Wi-Fi that drops every packet, or for a router whose internet line is
    /// down. When a request has just shown that, this reports offline and ``changes`` does not. The check is
    /// cheap, synchronous and safe from any thread.
    public var now: Reach {
        lock.withLock {
            guard let until = doubtedUntil, clock.now < until else { return told }
            return Reach(isOnline: false, costsData: told.costsData,
                         isConstrained: told.isConstrained)
        }
    }

    /// **The path's reading**, which is what the person sees and what sets the audio rate. It emits only
    /// when the value changes. To read both the stream and ``path``, subscribe to this stream first and
    /// then read ``path``. A reading that arrives between the two is then buffered, not lost.
    ///
    /// A doubt is deliberately not published here. A banner that says "no internet connection" is a claim
    /// about the phone, and one failed request is not enough evidence for it. Screens whose reads failed
    /// say "couldn't reach your library", which is accurate and narrower. A doubt closes the gate. It does
    /// not show a sign.
    public var changes: AsyncStream<Reach> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { listeners[id] = continuation }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.listeners[id] = nil }
            }
        }
    }

    /// The settled path reading, regardless of what the last request found out. The banner and the audio
    /// rate ladder use this.
    public var path: Reach { lock.withLock { told } }

    /// **Records that a request found the line dead while the path reported it as up.**
    ///
    /// This is the reverse direction of the path reading, as in the desktop's `OnlineGateHandler`. Without this, every screen discovers the dead network alone, each after a full
    /// timeout. Opening a record waits, opening a playlist waits, opening the radio waits. With this, one
    /// request pays the timeout, and the others are refused at once.
    ///
    /// **The doubt expires on its own.** Nothing else would lift it. A captive portal that starts working
    /// sends no path update, so a gate held closed until the path changes would never open again. After
    /// ``holdingAway``, the next request goes out and either works or doubts again.
    public func doubt() {
        lock.withLock { doubtedUntil = clock.now.advanced(by: Self.holdingAway) }
    }

    /// Starts watching the path. This is safe to call more than once. The app calls it each time it comes
    /// to the foreground, and a second watcher would give a second answer.
    public func begin() {
        let claimed = lock.withLock { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard claimed else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            for await reading in self.watcher.readings() {
                if Task.isCancelled { return }
                self.take(reading)
            }
        }

        lock.withLock { watching = task }
    }

    public func stop() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            let running = watching
            watching = nil
            started = false
            return running
        }
        task?.cancel()
    }

    // The settling rule

    private func take(_ reading: Reach) {
        let now: Reach? = lock.withLock {
            // A path update is news from the system, which is better evidence than anything a request
            // worked out. Any doubt is cleared by it.
            doubtedUntil = nil
            latest = reading
            guard reading != told else { return nil }

            // Published at once: any reading that says there is a line, and any change made while the app
            // already believes there is no line. Only a change from online to offline has to wait.
            if reading.isOnline || !told.isOnline {
                told = reading
                return reading
            }
            return nil
        }

        if let now { announce(now); return }

        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.settling)
            self.settleIfStillAway()
        }
    }

    /// Publishes the raw reading if the line is still gone. This is checked against the reading that holds
    /// now, not the one that was current when the wait began.
    private func settleIfStillAway() {
        let now: Reach? = lock.withLock {
            guard !latest.isOnline, latest != told else { return nil }
            told = latest
            return latest
        }
        if let now { announce(now) }
    }

    /// Sends the reading to the listeners. This runs outside the lock. A listener's `yield` runs whatever
    /// code is on the other end of the stream, and holding a lock during that call can deadlock two of these.
    private func announce(_ reading: Reach) {
        let waiting = lock.withLock { Array(listeners.values) }
        for listener in waiting { listener.yield(reading) }
    }
}
