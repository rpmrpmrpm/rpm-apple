import Foundation
import Observation
import RPMKit
import RPMAudio

/// The settings that are kept between launches.
///
/// Stored in `UserDefaults` only. These are a few small values, and the system already
/// backs them up and removes them with the app, so a separate store is not needed.
@MainActor
@Observable
final class Prefs {
    /// The rate to ask for on a free network (`rateOnWifi`) and on a metered one
    /// (`rateOnCellular`).
    ///
    /// Both default to the original. The store limits a free account whatever is asked
    /// for, so a lower default would only make the phone ask for less than it may have.
    var rateOnWifi: Int {
        didSet { store.set(rateOnWifi, forKey: "rate.wifi") }
    }

    var rateOnCellular: Int {
        didSet { store.set(rateOnCellular, forKey: "rate.cellular") }
    }

    /// The rate to ask for when downloading, on any network. It is a separate setting
    /// because keeping a record and streaming it are different choices: for example the
    /// original for streaming at home, and 256 for downloads to save space.
    ///
    /// Applies to tracks that are signed after the change. A file already on the phone
    /// keeps the rate it was downloaded at.
    var rateForDownloads: Int {
        didSet { store.set(rateForDownloads, forKey: "rate.download") }
    }

    /// Whether loudness is levelled, and against what. The default is to match albums,
    /// as on the desktop.
    ///
    /// Stored by name, not by number: see ``NormalizeMode``.
    var levelling: NormalizeMode {
        didSet { store.set(levelling.rawValue, forKey: "levelling.mode") }
    }

    /// Whether records marked classical are levelled too. Off by default, as on the
    /// desktop, so that quiet music stays quiet.
    var levelsClassical: Bool {
        didSet { store.set(levelsClassical, forKey: "levelling.classical") }
    }

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store

        // Use `object(forKey:)`, not `integer(forKey:)`. The original rate is 0, and an
        // unset key also reads as 0 with `integer(forKey:)`, so a missing key must be
        // checked for explicitly.
        let onWifi = (store.object(forKey: "rate.wifi") as? Int) ?? AudioLadder.original
        rateOnWifi = onWifi
        rateOnCellular = (store.object(forKey: "rate.cellular") as? Int) ?? AudioLadder.original

        // When unset, downloads use the Wi-Fi setting, so an existing install keeps the
        // same download rate.
        rateForDownloads = (store.object(forKey: "rate.download") as? Int) ?? onWifi

        // A name this build does not know (written by a newer build) gives the default,
        // not off: levelling is on unless the person turned it off.
        levelling = store.string(forKey: "levelling.mode").flatMap(NormalizeMode.init(rawValue:))
            ?? .album

        // When unset, this is false, which is the default.
        levelsClassical = store.bool(forKey: "levelling.classical")
    }

    /// The rate to ask the store for, given the network and what the account may have.
    ///
    /// **One answer covers all the limits.** A saved rate is not used if the account is
    /// not entitled to it, or if the person has asked the phone to save data. For
    /// example, a saved 320 from an expired supporter account becomes the one rate a
    /// free account has, instead of being sent and rejected. The same 320 in Low Data
    /// Mode becomes 128.
    ///
    /// The rule itself is `AudioLadder.RateOffer`, not here. The store and this app must
    /// agree on it, and a second copy in the app could go out of date.
    func kilobits(on reach: Reach, offer: AudioLadder.RateOffer) -> Int {
        offer.settles(onWifi: rateOnWifi, onCellular: rateOnCellular, reach: reach)
    }
}
