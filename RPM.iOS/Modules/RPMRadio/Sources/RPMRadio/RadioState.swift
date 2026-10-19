import Foundation
import Observation
import RPMKit

/// Where rpm's own radio record is read from. ``RadioRepositoryClient`` in the app; a fake in tests.
public protocol RadioRecord: Sendable {
    func state(_ reading: RadioRepositoryClient.Reading) async throws -> RadioRepositoryClient.State
    func logo(station uuid: String, stamp: String) async throws -> RadioRepositoryClient.Logo
}

extension RadioRepositoryClient: RadioRecord {}

/// What has been decided about radio stations since this copy last looked: which ones not to show,
/// and whether any logo has changed. It matches the desktop's `RadioState`.
///
/// **Why the phone has to be told.** The url cache keeps a station logo for thirty days, as the
/// server asks. Without this state, a logo replaced in the admin would reach a phone that already
/// has the old one only after about a month, and a station taken out of the list would never leave it.
///
/// **Read without waiting.** ``logoStamp`` and ``isHidden(_:)`` hold the last answer that arrived.
/// Before the first answer they mean "no stamp" and "nothing hidden". Both are observed, so a list
/// or a logo drawn before the answer lands is drawn again when it does.
///
/// **Asked at most once an hour**, and the first ask of each launch goes past the url cache: see
/// ``RadioRepositoryClient/Reading/pastTheStore``.
@MainActor @Observable
public final class RadioState {
    /// What to put in a logo's address, so a logo changed in the admin is asked for again. Empty
    /// when nothing has been changed by hand.
    public private(set) var logoStamp = ""

    /// The stations hidden and the stations edited in the admin, as last answered. Observed, so a list
    /// drawn before the answer lands is drawn again when it does.
    public private(set) var rules = StationRules.none

    @ObservationIgnored private let record: any RadioRecord
    @ObservationIgnored private let now: () -> ContinuousClock.Instant

    /// When the server last answered, or was asked and failed. Nil until then.
    @ObservationIgnored private var askedAt: ContinuousClock.Instant?

    /// Whether this launch has had an answer from the server rather than from the url cache.
    @ObservationIgnored private var heardThisLaunch = false

    /// One ask at a time, however many screens want one.
    @ObservationIgnored private var asking = false

    /// An hour: the server's own max-age on the answer. Long enough that the ask is not a cost on
    /// every screen, short enough that a change in the admin shows within the hour.
    public static let fresh: Duration = .seconds(3600)

    public convenience init(record: any RadioRecord) {
        self.init(record: record, now: { ContinuousClock.now })
    }

    init(record: any RadioRecord, now: @escaping () -> ContinuousClock.Instant) {
        self.record = record
        self.now = now
    }

    /// Whether this station has been taken out of the app: every row the directory files it
    /// under is hidden.
    ///
    /// **The station, not its uuid.** A listed station is several directory rows folded into one,
    /// and the fold keeps one uuid (the others are in ``RadioStation/alsoFiledAs``). See
    /// ``StationRules/hides(_:)``.
    ///
    /// **Every row, not any row**, as the desktop's `RadioState.IsHidden` does. The admin hides the
    /// row that was pressed, and a duplicate row is often hidden while the station's main row is
    /// not. Hiding on any row would remove a station such as NPO Radio 1, whose two 32k AAC rows
    /// are hidden but whose 192k MP3 row is not.
    public func isHidden(_ station: RadioStation) -> Bool { rules.hides(station) }

    /// Asks, unless an answer is under an hour old. Nothing waits on it and nothing is reported.
    /// Without an answer the phone shows no stamp and hides nothing.
    public func refresh() async {
        if let askedAt, askedAt.duration(to: now()) < Self.fresh { return }
        guard !asking else { return }
        asking = true
        defer { asking = false }

        do {
            let read = try await record.state(heardThisLaunch ? .stored : .pastTheStore)
            heardThisLaunch = true
            askedAt = now()

            // Only on a change: an assignment is an observed change whatever its value, and the
            // hourly answer almost always says the same thing.
            let stamp = read.logos
            let named = Set(read.hidden.map { $0.lowercased() })
            var edits: [String: StationEdit] = [:]
            for (uuid, wire) in read.edits {
                if let edit = StationEdit.of(name: wire.name, tags: wire.tags, description: wire.description) {
                    edits[uuid.trimmingCharacters(in: .whitespaces).lowercased()] = edit
                }
            }
            let next = StationRules(hidden: named, edits: edits)
            if stamp != logoStamp { logoStamp = stamp }
            if next != rules { rules = next }
        } catch RPMError.offline {
            // Not an answer, and not a reason to wait an hour: the address is fine, the phone is
            // offline. The next screen that calls `refresh()` asks again.
        } catch {
            // The last answer stands. It is marked as asked, so a server that is failing is not
            // asked again by every screen that appears.
            askedAt = now()
        }
    }

    /// This station's logo as rpm holds it, at the stamp in hand.
    public func logo(for station: RadioStation) async throws -> RadioRepositoryClient.Logo {
        try await record.logo(station: station.uuid, stamp: logoStamp)
    }
}
