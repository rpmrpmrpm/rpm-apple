import Testing
@testable import RPMDesign

/// The travel of a line that is too long for its column. The desktop has no tests for this.
/// These tests are written from what its code comments say.

@Test func aLineThatFitsNeverMoves() {
    #expect(MarqueeWalk.travel(text: 100, column: 200) == 0)
    #expect(MarqueeWalk.period(travel: 0) == 0)

    for at in stride(from: 0.0, through: 40, by: 0.5) {
        #expect(MarqueeWalk.offset(at: at, travel: 0) == 0)
    }
}

/// A few points of space after the tail show that the line has ended, before it starts again.
@Test func aLineWalksPastItsOwnTail() {
    #expect(MarqueeWalk.travel(text: 300, column: 200) == 110)
}

/// The rest at the start matters most, because the title is shown there.
@Test func aLineRestsAtItsStartBeforeItSetsOff() {
    for at in stride(from: 0.0, to: MarqueeWalk.startPause, by: 0.5) {
        #expect(MarqueeWalk.offset(at: at, travel: 110) == 0)
    }

    #expect(MarqueeWalk.offset(at: MarqueeWalk.startPause + 1, travel: 110) < 0)
}

@Test func aLineWalksLeftAtReadingPace() {
    let after = MarqueeWalk.offset(at: MarqueeWalk.startPause + 1, travel: 110)
    #expect(abs(after + MarqueeWalk.pace) < 0.001)
}

/// It holds at the far end long enough to be read, at exactly its tail.
@Test func aLineHoldsAtTheEndOfItsTravel() {
    let travel: Double = 110
    let arrived = MarqueeWalk.startPause + travel / MarqueeWalk.pace

    for at in stride(from: arrived + 0.01, to: arrived + MarqueeWalk.endPause, by: 0.2) {
        #expect(abs(MarqueeWalk.offset(at: at, travel: travel) + travel) < 0.001)
    }
}

/// It runs back faster than it walked out.
@Test func aLineRunsBackFasterThanItWalked() {
    let travel: Double = 110
    let holding = MarqueeWalk.startPause + travel / MarqueeWalk.pace + MarqueeWalk.endPause

    let out = MarqueeWalk.offset(at: MarqueeWalk.startPause + 1, travel: travel)
    let back = MarqueeWalk.offset(at: holding + 1, travel: travel)

    #expect(back > out, "the run back is not further along than the walk out")
    #expect(MarqueeWalk.backPace > MarqueeWalk.pace)
}

/// **The rule that must hold for any numbers.** A line never sits to the right of where it
/// started, and never to the left of its own tail.
@Test func aLineNeverLeavesItsOwnTravel() {
    for travel in [1.0, 12.0, 110.0, 900.0] {
        let cycle = MarqueeWalk.period(travel: travel)

        for step in 0...400 {
            let at = cycle * Double(step) / 400
            let where_ = MarqueeWalk.offset(at: at, travel: travel)

            #expect(where_ <= 0, "at \(at) of \(cycle) it sat at \(where_)")
            #expect(where_ >= -travel - 0.001, "at \(at) of \(cycle) it sat at \(where_)")
        }
    }
}

/// A cycle ends where it started, or the line jumps on every turn.
@Test func aCycleComesBackToWhereItStarted() {
    for travel in [12.0, 110.0, 900.0] {
        let cycle = MarqueeWalk.period(travel: travel)

        #expect(abs(MarqueeWalk.offset(at: cycle, travel: travel)) < 0.001)
        #expect(abs(MarqueeWalk.offset(at: cycle * 3, travel: travel)) < 0.001)
    }
}

/// At rest, everything past the column is hidden. At the end of the walk nothing is hidden: the
/// extra space is blank, not hidden letters.
@Test func whatIsHiddenAfterTheColumnRunsOutAtTheTail() {
    let travel = MarqueeWalk.travel(text: 300, column: 200)

    #expect(MarqueeWalk.hiddenAfter(offset: 0, travel: travel) == 100)
    #expect(MarqueeWalk.hiddenAfter(offset: -40, travel: travel) == 60)
    #expect(MarqueeWalk.hiddenAfter(offset: -100, travel: travel) == 0)
    #expect(MarqueeWalk.hiddenAfter(offset: -travel, travel: travel) == 0)
}

/// A line that fits hides nothing. This includes a line that moves within its small slack.
@Test func aLineThatFitsHidesNothingAfterTheColumn() {
    #expect(MarqueeWalk.hiddenAfter(offset: 0, travel: 0) == 0)

    let slackOnly = MarqueeWalk.travel(text: 195, column: 200)
    #expect(MarqueeWalk.hiddenAfter(offset: 0, travel: slackOnly) == 0)
}

/// A long title takes longer than a short one. Lines do not all take the same time.
@Test func aLongerLineTakesLonger() {
    #expect(MarqueeWalk.period(travel: 400) > MarqueeWalk.period(travel: 40))
}
