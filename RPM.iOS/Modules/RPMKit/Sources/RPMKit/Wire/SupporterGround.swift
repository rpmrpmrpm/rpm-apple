import Foundation

/// Which ground the app is drawn on for a launch, and when that is decided.
///
/// It is the gate for the Gold backdrop, the vinyl in its gold pressing: it says whether this
/// launch may use it (``Backdrop/standing(stored:gold:)``). The blue pressing is the Vinyl tile
/// and is available to everybody, supporters included. The default is RPaMp's ground.
///
/// The desktop asks its supporter service every time it restyles
/// (`Backdrop.Resolve`), and on a machine that already knows the answer that is the
/// right approach. A phone does not know: the plan of the account comes down with the
/// quota, seconds after the first screen is drawn, and after a library read and the
/// wall of covers. Asking live there would mean the app opens blue and turns gold
/// while somebody is looking at it, which looks like a fault and not like a
/// thank-you.
///
/// **So the answer is remembered and not asked, except at the one moment when it can be
/// adopted.** What the cloud last said is on the disk before the process starts, and
/// ``isGold`` reads it before the first frame. From then on only ``adopt(isSupporter:in:)``
/// can change it, and it has exactly one caller: a sign-in, where the plan of the account
/// is read while the sign-in screen is still shown and the ground it decides is
/// the ground the app is first drawn on. Nothing is swapped, because nothing of the
/// account is on the screen yet.
///
/// ``remember(isSupporter:in:)`` is the other entry point and it is deliberately weaker: it
/// writes what the NEXT launch will read and cannot change this one. Every later quota
/// read goes through it, so support that starts while the app is open shows the next time
/// the app opens, and support that ends works the same way. This is the right trade for a
/// background: a picture that changes while you read a screen is worse than one that
/// changes when you come back to it.
///
/// It lives beside the wire types for the same reason ``AudioLadder`` does: two
/// things have to agree on what a supporter may have, and neither of them owns it.
public enum SupporterGround {
    /// **Nowhere else names this string.** The value is read at launch and written a
    /// few seconds later from somewhere else entirely, so a second spelling of the
    /// key would be a ground that never turns gold and nothing on screen to say why.
    private static let key = "supporter.gold"

    /// Whether this launch stands on the gold pressing.
    ///
    /// Settled on the first ask, which is the first screen drawn, and after that it
    /// changes only through ``adopt(isSupporter:in:)``. `private(set)` is the whole
    /// gate: a quota read cannot reach this even by accident, it can only leave a note
    /// for the next launch.
    ///
    /// Main-actor, because it is a picture: everything that reads it is a view body,
    /// and a background that could be changed from a network callback could change in
    /// the middle of a frame.
    @MainActor public private(set) static var isGold: Bool = remembered(in: .standard)

    /// The plan of the account has just been read at a sign-in: use it now, and
    /// remember it for next time.
    ///
    /// The one way this launch's ground can change, and it is only right where nothing
    /// of the account is drawn yet: the moment between the sign-in screen and the
    /// library. Called from anywhere else it causes the swap that this whole arrangement
    /// exists to prevent.
    ///
    /// - Parameter store: has no default, so the tests can pass their own and the app's
    ///   one call site says which one it means.
    @MainActor public static func adopt(isSupporter: Bool, in store: UserDefaults) {
        remember(isSupporter: isSupporter, in: store)
        isGold = isSupporter
    }

    /// What the cloud has just said about the account, kept for the next launch.
    ///
    /// - Parameter store: has no default, for the reason above.
    public static func remember(isSupporter: Bool, in store: UserDefaults) {
        store.set(isSupporter, forKey: key)
    }

    /// What a store is holding: the ground the next launch will open on.
    ///
    /// False is blue, and an account nobody has asked about yet reads as false.
    /// That is the right way round for the one fact that cannot be checked at the
    /// moment it is used: a free account never sees a supporter's backdrop, and a
    /// supporter whose plan has not been read yet sees the app's own until the
    /// next sign-in.
    public static func remembered(in store: UserDefaults) -> Bool {
        store.bool(forKey: key)
    }
}
