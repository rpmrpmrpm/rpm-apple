import Foundation

/// How far this phone can reach, described by three separate facts.
///
/// Keep these as three values. A single Bool cannot tell "no network" apart from "a network that
/// costs money". If the two were merged, a phone with no network at all would pick the cellular
/// rung. A screen cannot show "no connection" from a property named `costsData`, and a gate cannot
/// be built on one, so `isOnline` is kept separate.
///
/// The desktop's `RPM.Core/Net/Reach.cs` has a third answer, for a LAN whose internet line is down.
/// This phone has no such case. It reaches its records only through the cloud, so "a network with
/// nothing beyond it" and "no network" give the same answer to every caller.
public struct Reach: Sendable, Equatable {
    /// Whether anything at all can be reached. This is what the gate checks.
    public let isOnline: Bool

    /// Whether each byte costs money. This is true on cellular data. It is also true when the phone
    /// uses another phone's hotspot, which is Wi-Fi but still uses a cellular allowance. The right
    /// question is what a byte costs, not which interface carries it.
    public let costsData: Bool

    /// Low Data Mode: the person has asked, in Settings, to use less data. Apple asks apps that
    /// stream to respect this setting, and rpm has a control that matches it.
    public let isConstrained: Bool

    public init(isOnline: Bool, costsData: Bool, isConstrained: Bool) {
        self.isOnline = isOnline
        self.costsData = costsData
        self.isConstrained = isConstrained
    }

    /// The belief used before the first network path is reported.
    ///
    /// **The two guesses point in opposite directions, on purpose.** `costsData` starts as `true`, so
    /// that a track started in the half second before the monitor reports does not use cellular data
    /// by mistake. Wi-Fi corrects it later. `isOnline` starts as `true` so that the gate does not refuse
    /// the first request, which is the one a user is most likely to be waiting for. These are different
    /// guesses. No single starting value is safe for both.
    public static let unknown = Reach(isOnline: true, costsData: true, isConstrained: false)

    /// No network at all.
    public static let away = Reach(isOnline: false, costsData: true, isConstrained: false)

    /// A network that costs nothing and is not rationed. This is what a phone on home Wi-Fi reports.
    public static let freely = Reach(isOnline: true, costsData: false, isConstrained: false)

    /// Builds a reading from the three values that `NWPath` reports. It is kept apart from the code
    /// that reads `NWPath`, so that it can be tested without a network.
    ///
    /// **An unsatisfied path counts as expensive.** `NWPath` reports `isExpensive` as `false` when there
    /// is no path. That does not mean the path is free. It means there is nothing to charge for. If the
    /// value were read directly, a phone that lost signal and then reconnected on cellular data would
    /// treat its first track as Wi-Fi traffic.
    public static func reading(satisfied: Bool, expensive: Bool, constrained: Bool) -> Reach {
        Reach(isOnline: satisfied,
              costsData: satisfied ? expensive : true,
              isConstrained: satisfied && constrained)
    }
}
