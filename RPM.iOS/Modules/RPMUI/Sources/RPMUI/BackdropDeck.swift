import SwiftUI
import CoreGraphics
import RPMArt

/// An artist's photographs as a deck the user can page through, and the swipe that moves it.
///
/// The C# counterpart is `RPM.Core/Art/BackdropDeck.cs`.
///
/// The automatic crop is only arithmetic: the person looking at the screen is the one who can
/// tell that the good photograph is the third one. A swipe pages through the photographs, and
/// the pictures move together under the finger: **the gesture is the transition**. There is no
/// snap back followed by a fade. That combination looks like a mistake: the picture springs home
/// and then suddenly changes into a different one.
///
/// **The whole deck is laid out, not stacked on demand.** Every photograph the artist has
/// (at most eight, the number the desktop's own preselector keeps) is fetched, cut for this frame
/// and given a place: picture *n* sits `n - showing` frames to the right of the one on screen,
/// whether or not anybody is looking at it. A swipe then moves one number, `travel`, and nothing
/// is decided while a finger is down. Stacking a neighbour only when the drag begins does not
/// work: the picture is often not ready yet, so it appears after the gesture and not during it.
///
/// **Peek, then commit.** The position only advances once the picture is available, so what is
/// on screen and where the deck says it is can never disagree. The deck stops at both ends and
/// does not wrap: a ring of photographs gives no way to tell that you have seen them all, and
/// there are usually only a few.
///
/// **A type, not a handful of `@State` values on the stage.** A drag moves the pictures sixty
/// times a second. If the offset were held on the stage, every frame would re-evaluate the
/// record, the column, the scrim and the chrome as well. Held here, only ``StagePictures``
/// reads it, and only that view redraws.
@Observable
@MainActor
final class BackdropDeck {
    /// Every photograph that has come down, cut for this frame, by its place in the deck.
    ///
    /// Held for the whole deck and not for a window of it. Eight full-frame bitmaps are some
    /// tens of megabytes. That is the cost of a swipe that moves a picture already available
    /// instead of fetching one while the finger is down.
    private(set) var pictures: [Int: CGImage] = [:]

    /// Which of them is on screen.
    private(set) var showing = 0

    /// How many the artist has. This is not how many have been fetched. See ``pictures``.
    private(set) var count = 0

    /// How far the deck has been moved from where it sits, in points. One number for all of
    /// them, because they move as one thing.
    private(set) var travel: CGFloat = 0

    /// The photograph that is up, or nil while it is still coming down.
    var picture: CGImage? { pictures[showing] }

    /// Under `RPM_STAGE_DIAG`, what the deck was asked to do. Assigned by the stage, so there is
    /// one place in this app that decides whether anything is said.
    var say: (String) -> Void = { _ in }

    /// Set while the deck is being filled, so filling runs once and not once per frame of a drag.
    private var filling = false

    // What the deck is a deck OF. Held and not passed in, because a swipe happens long after
    // the stage last supplied any of it.
    private var store: BackdropStore?
    private var artist: String?
    private var album: String?
    private var scene: ArtScene?

    /// Whose deck this is, case-folded, so the same artist spelled with different capitals on two
    /// tracks is not treated as a different artist.
    private var whose: String?

    nonisolated init() {}

    // ── the figures ──

    /// How many of an artist's photographs are kept. This matches the desktop's
    /// `BackdropPreselector.MaxRanked`, for the same reason: more than eight is a gallery
    /// nobody asked for, and every photograph costs about a megabyte of the user's data.
    static let most = 8

    /// How far a drag has to carry the deck to count, as a fraction of the frame. The picture
    /// itself is the measure, so it is the same gesture on every handset. The flick needs less
    /// distance: a fast finger is a decision even when it has barely moved, but it must move at
    /// least `flickMinTravel` points so that a tap does not count.
    private static let commitFraction: CGFloat = 0.22
    private static let flickSpeed: CGFloat = 700, flickMinTravel: CGFloat = 12

    /// How far the deck follows a finger when there is nowhere to go: at the end of the deck, or
    /// when the next photograph has not been fetched yet. It moves a little and springs back,
    /// which shows that the swipe cannot be completed.
    private static let rubberFollow: CGFloat = 0.35, rubberMax: CGFloat = 24

    /// Long enough to be seen, short enough to finish while the finger that threw it is still
    /// close. One animation for both endings, because they are the same movement: everything goes
    /// to where it now belongs. A refused swipe differs only in that no picture changed place
    /// first.
    private static let slide = Animation.spring(duration: 0.3)

    // ── what is up ──

    /// Puts an artist's photographs in, cut for this frame.
    ///
    /// A different artist starts at their first photograph. **The same artist keeps the one that
    /// is up**, so playing through their records does not undo a picture somebody chose by hand.
    /// Turning the phone does not undo it either, and that also comes through this function.
    func load(from store: BackdropStore?, artist: String?, album: String?,
              cutFor scene: ArtScene) async {
        let key = (artist ?? "").lowercased()

        // A photograph cut for one shape is cut wrong for another, so what came down for the old
        // frame is of no use to the new one.
        if whose != key || self.scene != scene { pictures = [:] }

        self.store = store
        self.artist = artist
        self.album = album
        self.scene = scene

        travel = 0

        let howMany = await store?.count(artist: artist, album: album) ?? 0

        // **Settled on an artist only when there is something to settle on.**
        //
        // The count is asked before choosing, and that order matters. The lookup can fail (a
        // phone that has not finished signing in can answer the first request and not the
        // second). An artist marked as settled after a failed lookup never gets a photograph
        // chosen, however many photographs they have. Nothing is recorded here unless a real
        // answer produced it.
        if whose != key, howMany > 0 {
            whose = key

            // Not simply the first. It is the one they were left on or, the first time this artist
            // comes up, the best of the first few, judged by what its crop would look like on
            // this frame. See `BackdropStore.opening`.
            let opening = await store?.opening(artist: artist, album: album, cutFor: scene)
            showing = opening?.at ?? 0

            if let opening {
                say("\(key.isEmpty ? "nobody" : key): picture \(opening.at) of \(opening.of), "
                    + "\(opening.fetched) fetched (\(opening.weighed / 1024)kB), "
                    + "\(opening.decoded) decoded, \(opening.judged) read, \(opening.why)")
            }
        }

        count = min(howMany, Self.most)
        fill()
    }

    /// Drops everything. Art for a screen nobody is looking at only uses memory.
    func clear() {
        pictures = [:]
        travel = 0
        count = 0
        whose = nil
    }

    // ── the swipe ──

    /// A finger on the deck. Nothing is decided here: the pictures are already in their places,
    /// so this only records how far they have been moved.
    ///
    /// - Parameter width: the frame, which is as far as the deck is allowed to be carried. The
    ///   deck moves one photograph per swipe, so a very long drag must not bring the picture
    ///   after the next one into view, and past one frame there would be a gap beside the pair
    ///   being drawn.
    func dragged(_ carried: CGFloat, width: CGFloat) {
        // A deck of one still moves a little. `BackdropDeck.CanPage` in the C# version gates the
        // *stacking* and not the nudge. That is correct: an artist with a single photograph
        // should show the end of the deck and not a picture fixed to the screen.
        guard count > 0 else { return }

        // Dragging left brings the next photograph in from the right, as a stack of pictures
        // moves everywhere else on this phone.
        let step = carried < 0 ? 1 : -1

        // Where there is nothing to move to (the end of the deck, or a photograph that has not
        // been fetched) the deck moves against a rubber band instead of sliding into a gap.
        travel = pictures[showing + step] != nil
            ? min(max(carried, -width), width)
            : min(max(carried * Self.rubberFollow, -Self.rubberMax), Self.rubberMax)
    }

    /// - Parameter width: the frame the gesture happened in, which is what "far enough" is
    ///   measured against.
    func released(_ carried: CGFloat, velocity: CGFloat, width: CGFloat) {
        guard count > 0 else { return }

        let step = carried < 0 ? 1 : -1
        let there = pictures[showing + step] != nil

        let flicked = abs(velocity) >= Self.flickSpeed && abs(carried) >= Self.flickMinTravel
        let carriedFar = abs(carried) >= width * Self.commitFraction

        guard there, flicked || carriedFar else {
            // Back where it came from, at the ends of the deck too.
            withAnimation(Self.slide) { travel = 0 }
            return
        }

        // **The deck changes first, and the animation catches up.**
        //
        // Both numbers change at once, to their resting values: the next photograph becomes the
        // one showing, and nothing is carried. A picture is drawn at
        // `travel + (its place - showing) × width`, so the picture being landed on moves from
        // where the finger left it to the middle, and the one being left moves from the middle
        // to a frame away. It is one movement over one distance, in step, and nothing is left
        // over at the end.
        //
        // Do not instead animate `travel` out to a whole frame and move the deck in the
        // animation's completion handler. A spring reports itself complete before it has
        // stopped moving, so the deck would be rearranged under a picture that is still moving.
        // The rearrangement itself has no animation, so whatever distance the spring had not
        // yet covered would be covered in one frame, and the picture would jump. The C# version
        // (`BackdropStage.Settle`) changes which layer is in front the moment the finger lifts,
        // for the same reason.
        withAnimation(Self.slide) {
            showing += step
            travel = 0
        }

        land()
    }

    /// Arriving at a photograph: what is written down, and what is fetched next.
    private func land() {
        say("landed on picture \(showing)")

        // **Landing is choosing.** Loading is not: every photograph the artist has is fetched
        // long before anybody arrives at it, and recording a pick for one nobody has seen would
        // make the last photograph fetched the artist's chosen backdrop.
        if let store, let artist {
            let album = self.album, at = showing
            Task { await store.remember(artist: artist, album: album, at: at) }
        }

        fill()
    }

    /// Brings down every photograph the artist has, cut for this frame, nearest the one on
    /// screen first.
    ///
    /// **Nearest first.** The next swipe is far more likely to go to a neighbour than to the far
    /// end, so the pictures arrive in the order somebody would reach them. Each is published as it
    /// arrives and not all at the end, so the first swipe can move as soon as there is a picture
    /// to move to.
    ///
    /// One after another and not all at once: this spends the user's cellular data on pictures
    /// nobody has asked for yet, and the record is turning at sixty frames a second while it
    /// happens.
    private func fill() {
        guard !filling, let store, let scene, count > 0 else { return }

        filling = true
        let mine = whose
        let from = showing

        Task {
            defer { filling = false }

            for at in Self.order(around: from, of: count) where pictures[at] == nil {
                let got = await store.backdrop(artist: artist, album: album,
                                               at: at, cutFor: scene)

                // The music moved on: this photograph is of an artist nobody is listening to.
                guard mine == whose else { return }

                if let got { pictures[at] = got }
            }

            say("\(pictures.count) of \(count) down, \(showing) up")
        }
    }

    /// The deck's places, nearest `from` first: the one on screen, then either side of it, and
    /// outwards. Forward before back at each step, because forward is the swipe people make.
    static func order(around from: Int, of count: Int) -> [Int] {
        guard count > 0 else { return [] }

        var places = [from]
        var step = 1

        while places.count < count {
            for at in [from + step, from - step] where at >= 0 && at < count {
                places.append(at)
            }
            step += 1
        }

        return places
    }
}

/// The artist's photographs, drawn: the one that is up, and its neighbours in their places
/// either side of the frame.
///
/// A separate view for the reason given on ``BackdropDeck``: this is what a drag redraws, and
/// it should be all a drag redraws.
struct StagePictures: View {
    let deck: BackdropDeck

    /// The width of the screen, which is how far apart the pictures sit.
    let width: CGFloat

    var body: some View {
        ZStack {
            // Three at most, because a fourth cannot be on screen however far a finger has
            // carried the deck, and every picture drawn is a full-frame bitmap composited on
            // every frame of the gesture.
            ForEach(deck.showing - 1...deck.showing + 1, id: \.self) { at in
                if let picture = deck.pictures[at] {
                    sheet(picture)
                        .offset(x: deck.travel + CGFloat(at - deck.showing) * width)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.45), value: deck.picture == nil)
    }

    private func sheet(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
