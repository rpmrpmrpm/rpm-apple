import SwiftUI
import RPMKit
import RPMLibrary
import RPMDesign

/// How the records tab shows the records: as a grid of covers, or as a list of records with their
/// songs. Stored by name in the user defaults, so the tab opens the way it was left.
public enum LibraryLayout: String, CaseIterable, Sendable {
    case grid
    case list

    var label: String {
        switch self {
        case .grid: Loc.get("Library_ViewGrid")
        case .list: Loc.get("Library_ViewAlbums")
        }
    }

    var mark: String {
        switch self {
        case .grid: Glyph.grid
        case .list: Glyph.rows
        }
    }
}

/// The records as a list, the phone's version of the desktop's album list and data table together:
/// each record with its songs under it, or, ordered by song title, every song as a row of its own.
/// The order is ``AlbumListing``'s. The letters down the right edge jump to the first row filed
/// under a letter (``LetterRail``).
struct AlbumList: View {
    let listing: AlbumListing
    let covers: any CoverStore
    let playing: String?
    let onOpen: (CloudAlbum) -> Void
    let onPlay: (CloudTrack) -> Void
    let isTrackMarked: (CloudTrack) -> Bool
    let isTrackMine: (CloudTrack) -> Bool
    let onMarkTrack: (CloudTrack, Bool) -> Void
    let onFile: (CloudTrack) -> Void
    let upNext: TrackActions.UpNext

    /// The letter under the finger on the rail, shown large in the middle of the list while the
    /// finger is down. Nil otherwise.
    @State private var held: Character?

    /// The width kept free on the right for the rail, so no row runs under it.
    private static let railRoom: Double = 26

    var body: some View {
        ScrollViewReader { proxy in
            DissolvingScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(listing.rows) { row in
                        switch row {
                        case .record(let album): block(album).id(row.id)
                        case .song(let track, _): songRow(track).id(row.id)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, RPMLayout.foot)
            }
            .overlay(alignment: .trailing) {
                LetterRail(present: Set(listing.firstUnder.keys), held: $held) { letter in
                    guard let id = listing.firstUnder[letter] else { return }
                    proxy.scrollTo(id, anchor: .top)
                }
                .padding(.trailing, 2)
            }
            .overlay {
                if let held {
                    Text(String(held))
                        .font(RPMFont.displayBold(40))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .rpmGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: held)
        }
    }

    // ── a record and its songs ──

    private func block(_ album: CloudAlbum) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // The record's line opens the record, as its cover does on the grid.
            Button { onOpen(album) } label: {
                HStack(spacing: 14) {
                    PlaylistSleeve(track: album.tracks.first, glyph: Glyph.record, edge: 64,
                                   corner: 6, mark: 22, covers: covers)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(album.album)
                            .font(RPMFont.displayBold(17))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(byLine(album))
                            .font(RPMFont.display(13))
                            .foregroundStyle(RPMInk.white(0x99 / 255))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)

            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { at, track in
                Button { onPlay(track) } label: { line(track, at: at, of: album) }
                    .buttonStyle(.plain)
                    .trackActions(track, marked: isTrackMarked(track), mine: isTrackMine(track),
                                  upNext: upNext, swipes: .menuOnly,
                                  onMark: onMarkTrack, onFile: onFile)
            }
        }
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, Self.railRoom)
        .padding(.top, 22)
    }

    /// Artist and year under the record's name, as on the desktop's album list.
    private func byLine(_ album: CloudAlbum) -> String {
        let year = AlbumSort.yearOf(album.tracks)
        return year > 0 ? "\(album.artist) \u{b7} \(year)" : album.artist
    }

    /// One song of a record: its number, its title, the artist where it is not the record's, and
    /// its length.
    private func line(_ track: CloudTrack, at: Int, of album: CloudAlbum) -> some View {
        HStack(spacing: 10) {
            Text(number(track, at: at))
                .font(RPMFont.display(13))
                .foregroundStyle(track.rpmId == playing ? .white : RPMInk.white(0x77 / 255))
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title ?? "")
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let artist = track.artist, !artist.isEmpty,
                   artist.caseInsensitiveCompare(album.artist) != .orderedSame {
                    Text(artist)
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(AlbumPage.length(track.duration))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x66 / 255))
        }
        .frame(minHeight: 40)
        .overlay(alignment: .leading) { playingMark(track).offset(x: -12) }
        .contentShape(Rectangle())
    }

    /// The song's number on its record, or its place in the list where it has none.
    private func number(_ track: CloudTrack, at: Int) -> String {
        let tagged = track.tags?.trackNumber ?? 0
        return String(tagged > 0 ? tagged : at + 1)
    }

    // ── one song, in song-title order ──

    /// A song on its own row: its record's cover, its title, its artist and record, and its length.
    private func songRow(_ track: CloudTrack) -> some View {
        Button { onPlay(track) } label: {
            HStack(spacing: 14) {
                PlaylistSleeve(track: track, glyph: Glyph.record, edge: 44, corner: 6, mark: 16,
                               covers: covers)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title ?? "")
                        .font(RPMFont.display(16))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text([track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }
                            .joined(separator: " \u{b7} "))
                        .font(RPMFont.display(13))
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(AlbumPage.length(track.duration))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0x66 / 255))
            }
            .frame(minHeight: 58)
            .overlay(alignment: .leading) { playingMark(track).offset(x: -12) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .trackActions(track, marked: isTrackMarked(track), mine: isTrackMine(track),
                      upNext: upNext, swipes: .menuOnly, onMark: onMarkTrack, onFile: onFile)
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, Self.railRoom)
    }

    /// The playing mark in the margin: three points of white, which is what playing looks like
    /// everywhere in this app.
    private func playingMark(_ track: CloudTrack) -> some View {
        Capsule()
            .fill(track.rpmId == playing ? Color.white : .clear)
            .frame(width: 3, height: 24)
    }
}

/// The index down the right edge of a list: A to Z, then "#" for everything else. The phone's
/// version of the desktop's `AlphabetRail`.
///
/// A press, or a finger moving along the rail, goes to the first row under that letter. A letter
/// with nothing under it is faint and does nothing, as on the desktop: an index that jumps to a gap
/// would be wrong. The rail takes every touch on its strip, so a drag never falls between two
/// letters, and it reports a letter only when it changes, so a drag scrolls once per letter.
struct LetterRail: View {
    let present: Set<Character>
    @Binding var held: Character?
    let onPick: (Character) -> Void

    /// The tallest a letter's row may be. On a short phone the rows are shorter, so all
    /// twenty-seven fit.
    private static let tallest: Double = 17

    var body: some View {
        GeometryReader { space in
            let letters = ArtistWall.alphabet
            let step = min(Self.tallest, space.size.height / Double(letters.count))
            let top = (space.size.height - step * Double(letters.count)) / 2

            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(String(letter))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ink(letter))
                        .frame(width: 22, height: step)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { touch in
                        let at = Int(((touch.location.y - top) / step).rounded(.down))
                        let letter = letters[min(max(at, 0), letters.count - 1)]
                        guard letter != held else { return }

                        held = letter
                        guard present.contains(letter) else { return }
                        Haptics.tick()
                        onPick(letter)
                    }
                    .onEnded { _ in held = nil })
        }
        .frame(width: 22)
        .accessibilityHidden(true)
    }

    private func ink(_ letter: Character) -> Color {
        guard present.contains(letter) else { return RPMInk.white(0x40 / 255) }
        return letter == held ? .white : RPMInk.white(0xB8 / 255)
    }
}
