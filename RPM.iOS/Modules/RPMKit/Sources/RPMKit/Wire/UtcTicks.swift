import Foundation

/// A .NET timestamp, which is what the store holds for a favourite.
///
/// **Not unix seconds, and the two travel side by side.** A mark carries
/// `favoritedAt` in ticks (hundred-nanosecond intervals since the first of January
/// in the year one) while the `updatedAt` beside it is unix seconds, because the
/// first came from a desktop and the second from the store. Writing one where the
/// other is expected is off by nineteen centuries and nothing anywhere reports it.
/// This is one function with one name and not code written at each call site, for exactly
/// that reason: there is one conversion and it has one name.
public enum UtcTicks {
    /// Seconds between the .NET epoch (0001-01-01) and the unix one (1970-01-01).
    public static let toUnixEpoch: Int64 = 62_135_596_800

    public static func of(_ moment: Date) -> Int64 {
        Int64((moment.timeIntervalSince1970 + Double(toUnixEpoch)) * 10_000_000)
    }

    public static var now: Int64 { of(Date()) }

    public static func date(_ ticks: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - Double(toUnixEpoch))
    }
}
