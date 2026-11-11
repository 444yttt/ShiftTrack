import Foundation
import Testing
@testable import ShiftTrack

struct ShiftActivityPlanTests {
    private let clockIn = Date(timeIntervalSince1970: 1_700_000_000)
    private var plannedEnd: Date { clockIn.addingTimeInterval(8 * 60 * 60) }

    @Test
    func breaksMoveTheTimerStartForward() {
        let plan = ShiftActivityPlan.make(
            clockIn: clockIn,
            plannedEnd: plannedEnd,
            completedBreakSeconds: 30 * 60,
            paused: false,
            now: clockIn.addingTimeInterval(60 * 60),
            yenAsOf: 1_200
        )
        #expect(plan?.timerStart == clockIn.addingTimeInterval(30 * 60))
        #expect(plan?.timerEnd == plannedEnd)
        #expect(plan?.showsRunningTimer == true)
        #expect(plan?.staleAt == plannedEnd.addingTimeInterval(15 * 60))
        #expect(plan?.yenAsOf == 1_200)
    }

    @Test
    func aPauseFreezesTheTimer() {
        let now = clockIn.addingTimeInterval(2 * 60 * 60)
        let plan = ShiftActivityPlan.make(
            clockIn: clockIn,
            plannedEnd: plannedEnd,
            completedBreakSeconds: 0,
            paused: true,
            now: now,
            yenAsOf: 2_400
        )
        #expect(plan?.paused == true)
        #expect(plan?.timerStart == now)
        #expect(plan?.timerEnd == now)
        #expect(plan?.showsRunningTimer == false)
    }

    @Test
    func aBreakLongerThanTheShiftIsNotATimer() {
        let plan = ShiftActivityPlan.make(
            clockIn: clockIn,
            plannedEnd: clockIn.addingTimeInterval(20 * 60),
            completedBreakSeconds: 30 * 60,
            paused: false,
            now: clockIn,
            yenAsOf: 0
        )
        #expect(plan == nil)
    }
}
