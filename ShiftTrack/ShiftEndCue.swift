import SwiftData
import SwiftUI
import UIKit

/// A shift end that falls after the previous foreground tick and at or before now.
/// The congratulations sheet is not part of this. That sheet opens only from
/// the unconfirmed-shift list.
enum ShiftEndCue {
    struct Moment: Equatable {
        var id: UUID
        var end: Date
    }

    static func crossed(previous: Date, now: Date, moments: [Moment]) -> [UUID] {
        guard now > previous else { return [] }
        return moments.compactMap { moment in
            guard moment.end > previous, moment.end <= now else { return nil }
            return moment.id
        }
    }
}

/// While the app stays in the foreground, one haptic fires when a shift's end
/// is crossed. Coming back from the background does not replay ends that
/// already passed. No sheet is presented.
struct ShiftEndPulse: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var shifts: [WorkShift]
    @State private var previous: Date?
    @State private var wasActive = false

    var body: some View {
        // The one-second clock keeps the run loop awake, so UI tests never go idle.
        if ProcessInfo.processInfo.arguments.contains("-UITestingSample")
            || ProcessInfo.processInfo.arguments.contains("-UITestingReset") {
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        } else {
            pulse
        }
    }

    private var pulse: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Color.clear
                .onChange(of: context.date) { _, now in
                    tick(now)
                }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tick(_ now: Date) {
        let active = scenePhase == .active
        if active, wasActive, let previous {
            let moments = shifts.map { shift in
                ShiftEndCue.Moment(
                    id: shift.uuid,
                    end: PayMath.endDate(
                        day: shift.date,
                        start: shift.startMinutes,
                        end: shift.endMinutes,
                        rollsToNextDay: shift.partID == nil ? nil : shift.patternEndOnNextDay
                    )
                )
            }
            if !ShiftEndCue.crossed(previous: previous, now: now, moments: moments).isEmpty {
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.prepare()
                generator.impactOccurred()
            }
        }
        if active {
            previous = now
        }
        wasActive = active
    }
}
