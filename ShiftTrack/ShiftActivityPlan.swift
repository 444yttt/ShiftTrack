import Foundation

/// Timing for a Live Activity. The widget extension is not in this build:
/// a new extension needs its own provisioning profile.
struct ShiftActivityPlan: Equatable {
    var timerStart: Date
    var timerEnd: Date
    var paused: Bool
    var staleAt: Date
    var yenAsOf: Int

    /// Worked time starts later by the breaks already finished, so the timer
    /// shows time on the clock rather than elapsed wall time including breaks.
    static func make(
        clockIn: Date,
        plannedEnd: Date,
        completedBreakSeconds: TimeInterval,
        paused: Bool,
        now: Date,
        yenAsOf: Int
    ) -> ShiftActivityPlan? {
        let start = clockIn.addingTimeInterval(max(0, completedBreakSeconds))
        guard start < plannedEnd else { return nil }
        let stale = plannedEnd.addingTimeInterval(15 * 60)
        return ShiftActivityPlan(
            timerStart: paused ? now : start,
            timerEnd: paused ? now : plannedEnd,
            paused: paused,
            staleAt: stale,
            yenAsOf: yenAsOf
        )
    }

    /// A paused range is a single instant, so the system timer does not run.
    var showsRunningTimer: Bool {
        !paused && timerStart < timerEnd
    }
}
