import SwiftUI
import RPMArt
import RPMRadio

extension HomeBannerView.StationWords {
    /// A station's card as the banners draw it, on home and on the radio home: the admin's
    /// description under the name, on up to two lines, where there is one, else the genre and the
    /// country; and the admin's card picture where there is one.
    ///
    /// The description is the station's own edit where it carries one, else the edit the rules
    /// hold for it now. The home page's stations come from the play counts and carry no edit.
    @MainActor
    static func card(_ station: RadioStation, kicker: String, state: RadioState) -> Self {
        let described = station.edit?.description ?? state.rules.edit(of: station)?.description
        return Self(kicker: kicker,
                    line: described ?? RadioHome.shortLine(station),
                    lines: described == nil ? 1 : 2,
                    picture: HomeBannerView.StationPicture.card(for: station, state: state))
    }
}

extension HomeBannerView.StationPicture {
    /// The card picture the admin chose for `station`, read through ``RadioState`` and decoded off
    /// the main actor at the size the card asks for. Nil where the rules list none for it.
    @MainActor
    static func card(for station: RadioStation, state: RadioState) -> Self? {
        let cards = state.rules.cards
        guard let uuid = cards.uuid(of: station) else { return nil }
        let key = uuid + "|" + cards.stamp
        return Self(key: key) { edge in
            let kept = key + "|" + String(edge)
            if let held = Self.decoded[kept] { return held }
            guard let data = try? await state.cardPicture(for: station) else { return nil }
            let image = await Task.detached(priority: .userInitiated) {
                Thumbnail.of(data, edge: edge)
            }.value
            if let image {
                if Self.decoded.count >= Self.decodedMost { Self.decoded.removeAll() }
                Self.decoded[kept] = image
            }
            return image
        }
    }

    /// The card pictures decoded so far, by station, stamp and size, shared by both banners, so a
    /// card that is built again as a banner turns does not read and decode its picture again.
    @MainActor private static var decoded: [String: CGImage] = [:]

    /// How many decoded card pictures are kept: twice as many as the radio banner has cards, for
    /// each of the two banners.
    private static let decodedMost = RadioHomePicks.bannerMost * 4
}
