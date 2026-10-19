import Foundation

/// The rates a track is served at, and who may have which.
///
/// Ported from `RPM.Fingerprint/AudioLadder.cs`. It lives beside the wire types
/// and not beside the player, for the same reason as in the .NET solution: **two
/// things have to agree on it** and neither owns it. The store decides what a
/// given account may be given; this side decides what to ask for, and a screen
/// that offers what the store will not serve has a setting that does nothing.
///
/// The ladder matches iBroadcast's. What supporting rpm buys is the lossless
/// original, not a wider choice of lossy rates.
public enum AudioLadder {
    /// Smallest first.
    public static let rates = [96, 128, 192, 256, 320]

    /// What a free account is served, whatever it asks for.
    public static let freeKilobits = 128

    /// The untranscoded file. What supporting rpm buys.
    public static let original = 0

    /// The rate used on a network where data is limited (Low Data Mode). It is the
    /// lowest rate that still sounds like music, and the same rendition that a free
    /// account is served, so it certainly exists at the store and is not a number
    /// made up for this case.
    public static let frugal = 128

    /// Whether a rate is one that gets made. Any other number was invented by the
    /// caller.
    public static func isOnTheLadder(_ kilobits: Int) -> Bool { rates.contains(kilobits) }

    /// The rate actually served for one that was asked for: the nearest rung at or
    /// below it, never above what the account is allowed.
    public static func serve(_ asked: Int, mayHaveOriginal: Bool) -> Int {
        if asked == original { return mayHaveOriginal ? original : freeKilobits }

        let capped = mayHaveOriginal ? asked : Swift.min(asked, freeKilobits)

        // Down, never up. Rounding up would spend data nobody agreed to and, for a
        // free account, hand over a rendition they are not entitled to.
        var served = rates[0]
        for rate in rates where rate <= capped { served = rate }
        return served
    }

    /// The rates one account may choose between, and whether the choice is theirs to
    /// make.
    ///
    /// **The cap is not only a display detail.** ``serve(_:mayHaveOriginal:)`` already
    /// refuses to give a free account anything above ``freeKilobits``, so a screen
    /// that offers the whole ladder to one offers a setting that does nothing:
    /// the box reads 320, the stream is 128, and the only place the two are compared
    /// is a log line.
    ///
    /// There is no third state for "not read yet". An account whose plan has not
    /// been read is offered ``unread``, which is the whole ladder: the choice is
    /// theirs either way and only the serving is capped, and telling
    /// somebody they are on the free plan because a request timed out is the worse of
    /// the two mistakes.
    public struct RateOffer: Equatable, Sendable {
        /// The rates on offer, in the order a chooser lists them.
        public let rungs: [Int]

        /// Whether the choice has been taken away, which is what a screen greys out.
        public let capped: Bool

        /// Every rung, **the original first**, then the other rates from the
        /// highest to the lowest.
        public static let whole = RateOffer(rungs: [original, 320, 256, 192, 128, 96],
                                            capped: false)

        /// The one rung a free account is served, and nothing else to pick from.
        /// Listing the others greyed out would only say the same thing in a longer way.
        public static let free = RateOffer(rungs: [freeKilobits], capped: true)

        /// What is offered before the plan of the account is known, and when reading
        /// it failed. See the note on the type: the whole ladder, on purpose.
        public static var unread: RateOffer { whole }

        public static func of(isSupporter: Bool) -> RateOffer { isSupporter ? whole : free }

        /// Where a remembered rate is in this offer. A rate that is not in it (for
        /// example a supporter's 320 read back after their support ended) gives the
        /// first rung, which for ``free`` is the only one there is.
        public func indexOf(_ kilobits: Int) -> Int {
            rungs.firstIndex(of: kilobits) ?? 0
        }

        /// The rate this offer would actually settle on for a remembered one, which is
        /// what a player asks the store for.
        public func settles(on kilobits: Int) -> Int {
            rungs.contains(kilobits) ? kilobits : rungs[0]
        }

        /// What to ask the store for, given both remembered rates and the state of the
        /// network.
        ///
        /// **Three questions are answered together here.** Which of the two settings
        /// applies depends on the network; whether the account may have what that setting
        /// says depends on the plan; and whether the person has asked the phone to use
        /// less data depends on Settings. If a screen answers two of the three and a
        /// player answers the other one, the box and the stream of a setting disagree.
        ///
        /// **Low Data Mode caps the chosen rate at ``AudioLadder/frugal``.**
        /// It is not `min` alone, because the original is zero and `min(0, 128)` is the
        /// original: the one rate that must never pass the limit is the one that plain
        /// arithmetic would let through.
        public func settles(onWifi: Int, onCellular: Int, reach: Reach) -> Int {
            let asked = reach.costsData ? onCellular : onWifi
            guard reach.isConstrained else { return settles(on: asked) }

            let rationed = asked == AudioLadder.original
                ? AudioLadder.frugal
                : Swift.min(asked, AudioLadder.frugal)

            return settles(on: rationed)
        }

        /// What is actually served for a rate chosen under this offer.
        public func serves(_ asked: Int) -> Int {
            AudioLadder.serve(asked, mayHaveOriginal: !capped)
        }
    }
}

/// **Where a track's bytes come from, and therefore how a seek works.**
///
/// Nothing about an address says which of the two it is, and they are seeked
/// differently: a stored object is byte-addressable, and a rendition being encoded as
/// it is sent has no bytes to range over. Getting it wrong fails silently in
/// both directions (a range request to the encoder is answered with the start of the
/// track, and a `from=` sent to the store is ignored), so the store says which kind it
/// is, and this is what it says.
public enum StreamKind: Sendable, Equatable {
    /// An object in the store. A seek is a range request, at the byte the parser
    /// works out.
    case stored

    /// A rendition that is made while it is served, because none exists at the
    /// rate that was asked for. A seek restarts the encoder at the new position.
    case live
}
