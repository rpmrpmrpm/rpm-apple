import Foundation
import Observation
import RPMKit

/// The stars the person gave records on this device, 1 to 5, by account and the record's first cover
/// key. The Android TV's `AlbumRatings`.
///
/// **Kept on this device only.** The desktop keeps its album ratings in its own library and the cloud
/// has no route for them, so a rating made here is not seen on another device.
///
/// `@Observable` and `@MainActor`: a page that shows a record's stars redraws when they change.
@MainActor
@Observable
public final class AlbumRatings {
    public static let most = 5

    @ObservationIgnored private let defaults: UserDefaults

    /// Moves on every rating written, so a view that read ``stars(of:account:)`` reads again.
    private var changes = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stars given `album` under `account`, 0 for none.
    public func stars(of album: CloudAlbum, account: String) -> Int {
        _ = changes
        return defaults.integer(forKey: Self.key(album, account))
    }

    /// Gives `album` `stars` under `account`; 0 clears the rating. More than ``most`` is ``most``.
    public func rate(_ album: CloudAlbum, stars: Int, account: String) {
        let key = Self.key(album, account)
        if stars <= 0 {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(min(stars, Self.most), forKey: key)
        }
        changes += 1
    }

    /// `rpm.albumRating.<account>|<cover key>`: the record's first cover key, as its favourite mark is
    /// filed, or its own key where it has none.
    private static func key(_ album: CloudAlbum, _ account: String) -> String {
        let cover = AlbumArtKey.spellings(.cover, for: album.tracks).first ?? album.key
        return "rpm.albumRating.\(account)|\(cover)"
    }
}
