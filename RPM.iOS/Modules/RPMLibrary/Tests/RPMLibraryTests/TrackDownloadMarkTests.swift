import Testing
@testable import RPMLibrary

/// Which mark a song's row shows, from where its page's album or playlist stands and where the song
/// stands.
@MainActor
@Suite("The download marks on the rows")
struct TrackDownloadMarkTests {
    private let downloading = AlbumDownloads.Standing.downloading(have: 1, of: 4, fraction: 0.3,
                                                                  preparing: false)
    private let stuck = AlbumDownloads.Standing.stuck(have: 3, of: 4)

    /// While the page downloads, each row shows its own song's state.
    @Test func whileThePageDownloadsEachRowShowsItsSong() {
        #expect(TrackDownloadMark.of(page: downloading, track: .waiting) == .waiting)
        #expect(TrackDownloadMark.of(page: downloading, track: .preparing) == .preparing)
        #expect(TrackDownloadMark.of(page: downloading, track: .arriving(fraction: 0.5))
            == .arriving(fraction: 0.5))
        #expect(TrackDownloadMark.of(page: downloading, track: .onPhone) == .done)
        #expect(TrackDownloadMark.of(page: downloading, track: .stuck) == .stuck)
    }

    /// A page that is stuck shows which songs are on the phone and which could not come.
    @Test func aStuckPageShowsWhichSongsFailed() {
        #expect(TrackDownloadMark.of(page: stuck, track: .stuck) == .stuck)
        #expect(TrackDownloadMark.of(page: stuck, track: .onPhone) == .done)
    }

    /// A song the page's entry does not hold, such as a song added to the record after it was asked
    /// for, shows nothing.
    @Test func aSongNobodyAskedForShowsNothingWhileThePageDownloads() {
        #expect(TrackDownloadMark.of(page: downloading, track: .absent) == nil)
    }

    /// When the whole page is on the phone the key says so, and the rows show nothing.
    @Test func aPageOnThePhoneShowsNoMarks() {
        for track: TrackDownload in [.absent, .waiting, .preparing, .arriving(fraction: 0.2),
                                     .stuck, .onPhone] {
            #expect(TrackDownloadMark.of(page: .onPhone, track: track) == nil)
        }
    }

    /// A page nobody asked for marks only the songs another album or playlist brought to the phone.
    @Test func aPageNotAskedForMarksOnlySongsOnThePhone() {
        #expect(TrackDownloadMark.of(page: nil, track: .onPhone) == .done)
        for track: TrackDownload in [.absent, .waiting, .preparing, .arriving(fraction: 0.2), .stuck] {
            #expect(TrackDownloadMark.of(page: nil, track: track) == nil)
        }
    }

    /// The song's state is not read where the page alone decides, so those rows do not follow it.
    @Test func theSongIsNotReadWhenThePageIsOnThePhone() {
        var read = false
        func track() -> TrackDownload {
            read = true
            return .onPhone
        }
        #expect(TrackDownloadMark.of(page: .onPhone, track: track()) == nil)
        #expect(!read)
    }
}
