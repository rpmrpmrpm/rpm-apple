import Foundation
import RPMKit
import RPMLibrary
import RPMAudio

/// One song radio, from "Start radio" until something else is played.
///
/// The app keeps the run while it is on, and drops it whenever it starts any other queue.
/// While it is kept, a song this run queued becoming the one playing asks it for the songs
/// after it (``next(playing:inQueue:)``), as a radio's own queue rows do on the computer. A
/// song added with Play next plays in its turn, and the radio carries on from its own song
/// after it.
///
/// The crate is built off the main actor when the run starts, so the read overlaps the first
/// seconds of the song rather than following them.
@MainActor
public final class SongRadioRun {
    /// The song the radio started from.
    public let origin: String

    /// Every song this run has queued, oldest first, the origin included.
    private var history: [String]
    private var queued: Set<String>
    private let crate: Task<(RadioCrate, [String: CloudTrack]), Never>

    init(origin: CloudTrack, albums: [CloudAlbum], played: [String: PlayLog.Played], moods: CloudMoodLists?) {
        self.origin = origin.rpmId
        self.history = [origin.rpmId]
        self.queued = [origin.rpmId]
        self.crate = Task.detached(priority: .userInitiated) {
            let crate = RadioCrate.of(albums, played: played, moods: SongRadio.moods(in: moods))
            var byId: [String: CloudTrack] = [:]
            for album in albums { for track in album.tracks where byId[track.rpmId] == nil { byId[track.rpmId] = track } }
            return (crate, byId)
        }
    }

    /// Whether this run queued the song, the one it started from included.
    public func queued(_ track: CloudTrack) -> Bool { queued.contains(track.rpmId) }

    /// The songs to follow the one playing, closest first, at most ``SongRadio/ahead``. A song
    /// this run queued before and the listener has since taken out is not offered again.
    public func next(playing: String, inQueue: Set<String>) async -> [CloudTrack] {
        let history = self.history
        let (crate, byId) = await crate.value
        var random = SystemRandomNumberGenerator()
        let picks = SongRadio.pick(crate, seed: playing, origin: origin, inQueue: inQueue,
                                   history: history, count: SongRadio.ahead, using: &random)
        return picks.filter { !queued.contains($0) }.compactMap { byId[$0] }
    }

    /// Records that this run put the songs in the queue.
    public func note(_ tracks: [CloudTrack]) {
        for track in tracks where queued.insert(track.rpmId).inserted { history.append(track.rpmId) }
    }
}

extension LibrarySession {
    /// A radio on `track`, picking from the collection on screen with its play counts and
    /// the computer's mood lists.
    public func startRadio(on track: CloudTrack) -> SongRadioRun {
        SongRadioRun(origin: track, albums: albums, played: played, moods: radioMoods)
    }
}

extension SongRadioRun {
    /// Queues songs after the one playing until ``SongRadio/ahead`` follow it, if the song
    /// playing is one this run queued. The app calls it when the radio starts and on every
    /// change of track, while it keeps the run.
    ///
    /// The queue is asked again when the picks arrive: an answer that lands after the
    /// listener moved on, or after another answer filled the queue, adds nothing.
    public func topUp(_ player: Player) {
        guard let current = player.current, queued(current), room(in: player) > 0 else { return }
        Task { @MainActor in
            let picks = await next(playing: current.rpmId, inQueue: Set(player.queue.map(\.rpmId)))
            guard player.current?.rpmId == current.rpmId else { return }
            let space = room(in: player)
            guard space > 0 else { return }
            let inQueue = Set(player.queue.map(\.rpmId))
            let adding = Array(picks.filter { !inQueue.contains($0.rpmId) }.prefix(space))
            guard !adding.isEmpty else { return }
            note(adding)
            player.append(adding)
        }
    }

    /// How many more songs the queue wants after the one playing.
    private func room(in player: Player) -> Int {
        SongRadio.ahead - (player.queue.count - 1 - (player.index ?? 0))
    }
}
