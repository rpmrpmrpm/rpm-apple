import Foundation
import os
import RPMKit

/// The cover of the song a station says it is playing, so the player, the mini player and the lock
/// screen can show the song and not only the station's logo. Asked of the RPM API
/// (``RPMCloudClient/songCover(artist:title:size:)``). The Android app's `SongCovers` keeps the same
/// rules.
///
/// One ask per song for the life of the app, keyed on the artist and title folded (``SongAsk``). Two
/// asks while the first is running share its answer. A song the API found no cover for is kept as
/// having none. An ask that failed (offline, refused) is forgotten, so the song is asked again the
/// next time it plays.
public final class SongCovers: Sendable {
    /// The size the cover is asked for, in pixels: the player's sleeve on a large screen, which the
    /// mini player shares.
    public static let size = 600

    /// How long a busy answer is waited out before the one more ask: the API's Retry-After.
    private static let busyWait: Duration = .seconds(5)

    private let cloud: RPMCloudClient
    private let asks = Asks()

    /// The covers found so far, by ``SongAsk/key``, for ``peek(_:)``.
    private let found = OSAllocatedUnfairLock<[String: URL]>(initialState: [:])

    public init(cloud: RPMCloudClient) {
        self.cloud = cloud
    }

    /// The cover already found for this song, without asking.
    public func peek(_ song: SongAsk) -> URL? {
        let key = song.key
        return found.withLock { $0[key] }
    }

    /// The address of this song's cover, or nil where there is none or it could not be asked.
    public func cover(_ song: SongAsk) async -> URL? {
        let key = song.key
        let cloud = cloud
        let answer = await asks.answer(for: key) {
            let first = await cloud.songCover(artist: song.artist, title: song.title, size: Self.size)
            guard first == .busy else { return first }
            // A song nobody has asked about is looked up while the ask waits. One that takes
            // longer than the API waits comes back busy, and is asked once more after the wait.
            try? await Task.sleep(for: Self.busyWait)
            return await cloud.songCover(artist: song.artist, title: song.title, size: Self.size)
        }
        guard case .found(let url) = answer else { return nil }
        found.withLock { $0[key] = url }
        return url
    }
}

/// The asks made so far, by song. A finished ask stays when it found a cover or found none; a
/// failed one is removed, so the next ask for the song goes to the API again.
private actor Asks {
    private var known: [String: Task<SongCoverAnswer, Never>] = [:]

    func answer(for key: String,
                ask: @escaping @Sendable () async -> SongCoverAnswer) async -> SongCoverAnswer {
        if let running = known[key] { return await running.value }

        // Not tied to the caller: a caller that goes away does not stop the ask, and its answer
        // is kept for the next caller.
        let task = Task { await ask() }
        known[key] = task
        let answer = await task.value

        switch answer {
        case .found, .none:
            break
        case .failed, .busy:
            // Only this ask's entry. A newer ask for the same song may have taken its place.
            if known[key] == task { known[key] = nil }
        }
        return answer
    }
}
