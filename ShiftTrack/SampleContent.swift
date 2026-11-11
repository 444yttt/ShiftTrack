import Foundation
import SwiftData

/// Fictional rows for simulator screenshots. Never used for a normal launch.
enum SampleContent {
    static let argument = "-UITestingSample"

    @MainActor
    static func install(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        let existing = (try? context.fetch(FetchDescriptor<Workplace>())) ?? []
        guard existing.isEmpty else { return }
        let place = Workplace(
            name: "架空茶房 北窓",
            colorHex: "C6F24E",
            hourlyWage: 1_600,
            transportAllowance: 0
        )
        place.place = "架空県北窓"
        context.insert(place)
        let shift = WorkShift(
            date: .now,
            startMinutes: 11 * 60 + 30,
            endMinutes: 20 * 60 + 30,
            breakMinutes: 0,
            workplace: place
        )
        context.insert(shift)
        try? context.save()
    }
}
