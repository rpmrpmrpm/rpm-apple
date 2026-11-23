import Testing
import CoreGraphics
@testable import RPMDesign

/// What moves, and how much is drawn, in both power states.
@Suite("The motion plan")
struct MotionPlanTests {
    @Test("not saving power, everything moves and is drawn in full")
    func notSaving() {
        let plan = MotionPlan(saving: false)

        #expect(plan.stageRoom == .full)
        #expect(plan.cardRoomsMove)
        #expect(plan.marchSteps == 64)
        #expect(plan.lookScale == 1)
        #expect(plan.decorativeLoops)
    }

    @Test("saving power, less is drawn and only what answers the music moves")
    func saving() {
        let plan = MotionPlan(saving: true)

        #expect(plan.stageRoom == MotionPlan.savingStageRoom)
        #expect(plan.stageRoom != .full)
        #expect(!plan.cardRoomsMove)
        #expect(plan.marchSteps == 32)
        #expect(plan.lookScale == 0.5)
        #expect(!plan.decorativeLoops)
    }

    /// The room behind the player is still or drawn smaller, never drawn at a lower rate: the
    /// plan has no rate to give.
    @Test("saving power, the player's room is still or drawn smaller")
    func savingStageRoom() {
        switch MotionPlan(saving: true).stageRoom {
        case .still:
            break
        case .reduced(let scale):
            #expect(scale > 0 && scale < 1)
        case .full:
            Issue.record("the player's room is drawn in full while the phone saves power")
        }
    }

    @Test("the reduced room draws a quarter of each side")
    func reducedScale() {
        #expect(MotionPlan.reducedScale == 0.25)
        #expect(MotionPlan.StageRoom.reduced(scale: 0.25) != .reduced(scale: 0.5))
    }

    @Test("the plan nothing sets is the full plan")
    func full() {
        #expect(MotionPlan.full == MotionPlan(saving: false))
        #expect(MotionPlan(saving: true) != MotionPlan.full)
    }
}
