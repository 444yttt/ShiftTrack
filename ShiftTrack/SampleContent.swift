import Foundation
import SwiftData

/// Fictional rows for simulator screenshots. Never used for a normal launch.
/// The store, its address and its to-dos are made up; no phone number is set,
/// so the screenshots also show the disabled 電話 / メッセージ actions.
enum SampleContent {
    static let argument = "-UITestingSample"

    @MainActor
    static func install(in context: ModelContext, now: Date = .now) {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return }
        let existing = (try? context.fetch(FetchDescriptor<Workplace>())) ?? []
        guard existing.isEmpty else { return }
        let place = Workplace(
            name: "架空茶房 北窓",
            colorHex: "C6F24E",
            hourlyWage: 1_600,
            transportAllowance: 300
        )
        place.place = "架空県北窓町1-2"
        place.closingDay = 0
        place.paydayMonthOffset = 1
        place.paydayDay = 25
        context.insert(place)

        // A shift that is running when the screenshots are taken: started two
        // hours ago (rounded down to 15 minutes), five hours long.
        let calendar = Calendar.current
        let startGuess = now.addingTimeInterval(-2 * 3_600)
        let dayStart = calendar.startOfDay(for: startGuess)
        let minutes = Int(startGuess.timeIntervalSince(dayStart) / 60)
        let start = minutes - minutes % 15
        let shift = WorkShift(
            date: dayStart,
            startMinutes: start,
            endMinutes: (start + 5 * 60) % (24 * 60),
            breakMinutes: 30,
            todosRaw: ShiftTodoCodec.encode([
                ShiftTodoCodec.Item(id: UUID(), title: "ケーキの在庫を数える", done: true),
                ShiftTodoCodec.Item(id: UUID(), title: "閉店前にレジを締める", done: false),
            ]),
            workplace: place
        )
        context.insert(shift)
        try? context.save()
    }
}
