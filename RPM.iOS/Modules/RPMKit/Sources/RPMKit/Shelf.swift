import Foundation

/// Whose collection a cloud read is served from: this account's own, or one that
/// another account has shared.
///
/// A type rather than an optional argument, for the same reason as in `RPM.Core`:
/// forgetting "whose" fails silently in the worst way. A listing read without it
/// is the caller's own library shown under another account's name, and a stream
/// signed without it gives a 404 for a record that was there a moment ago. There
/// is no default, so every call that can be for another account says which one.
///
/// Nothing here is trusted. This says what to ask for, not what is allowed: the
/// server checks the grant on every request, so when a share is taken back the
/// music stops at the next track and not at the end of the hour.
public struct CloudShelf: Hashable, Sendable {
    /// The caller's own collection. The owner is empty, which is what every route
    /// serves when it is not told otherwise.
    public static let own = CloudShelf(ownerId: "")

    /// Another account's collection, by its account id. A blank id is a missing
    /// field and not another account, so it reads as `own` and not as a
    /// half-named shelf that would 404 everywhere.
    public static func of(_ ownerId: String) -> CloudShelf {
        CloudShelf(ownerId: ownerId.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private init(ownerId: String) { self.ownerId = ownerId }

    public let ownerId: String

    public var isOwn: Bool { ownerId.isEmpty }

    /// What goes on the wire, or nil when there is nothing to say.
    public var owner: String? { isOwn ? nil : ownerId }

    /// The query fragment, joined with `?` or `&` as the caller's URL needs.
    /// Both forms are here because the C# has both (`Also` and `Owned`), and
    /// using the wrong one builds a URL that the server silently ignores.
    public func query(first: Bool) -> String {
        guard let owner else { return "" }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let escaped = owner.addingPercentEncoding(withAllowedCharacters: allowed) ?? owner
        return (first ? "?" : "&") + "owner=" + escaped
    }
}

/// A shared collection that the store did not serve as itself.
///
/// Thrown when a listing requested for one account comes back without saying
/// that it belongs to that account. In practice this happens with a server that
/// does not know shared collections: an unbound query parameter is not an
/// error, so `?owner=` is dropped and the caller's OWN rows come back with a
/// 200. The client would then work on the wrong library without any sign of
/// trouble, which is why this throws and does not return an empty result.
public struct ShelfNotServedError: Error, Sendable {
    public let ownerId: String
    public init(ownerId: String) { self.ownerId = ownerId }
}
