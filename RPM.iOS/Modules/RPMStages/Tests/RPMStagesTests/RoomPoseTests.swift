import Testing
@testable import RPMStages

/// Where along its drift a room starts. Rooms that started together used to stand in the same pose
/// and move in step.
struct RoomPoseTests {
    /// The same name is the same pose, so two views of one card draw one frame.
    @Test func theSameNameIsTheSamePose() {
        #expect(RoomPose.offset(of: "RightNow") == RoomPose.offset(of: "RightNow"))
    }

    /// Every pose is inside the drift's span.
    @Test func everyPoseIsInsideTheSpan() {
        for seed in ["", "a", "stage", "9bd8e5d4-1a2b-4c3d-9e8f-001122334455", String(repeating: "z", count: 500)] {
            let offset = RoomPose.offset(of: seed)
            #expect(offset >= 0 && offset < RoomPose.span, "\(seed): \(offset)")
        }
    }

    /// Pinned, because the pose has to be the same on every launch and every device: Swift's own
    /// `hashValue` is seeded per process and would move every room on every launch.
    @Test func thePoseIsTheSameOnEveryLaunch() {
        // FNV-1a's offset basis, 14695981039346656037, is the hash of empty input.
        #expect(RoomPose.offset(of: "") == Double((14_695_981_039_346_656_037 as UInt64) % 10_000_000) / 10_000_000 * RoomPose.span)
    }

    /// The rooms one screen holds together (the made-for-you row, a row of stations) start far
    /// apart: at least thirty seconds of drift between any two, so every figure has a different
    /// pose.
    @Test func roomsOnOneScreenStartApart() {
        let seeds = ["RightNow|", "OnRepeat|", "FavoriteTracks|", "FirstListens|", "LovedAndForgotten|",
                     "NPO Radio 1", "Radio 538", "NPO Radio 2", "Intense Radio", "stage"]
        let offsets = seeds.map(RoomPose.offset(of:))
        for i in offsets.indices {
            for j in offsets.indices where j > i {
                #expect(abs(offsets[i] - offsets[j]) > 30, "\(seeds[i]) and \(seeds[j])")
            }
        }
    }
}
