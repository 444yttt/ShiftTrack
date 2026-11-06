import Foundation
import SwiftData

@MainActor
enum SampleSeeder {
    static func seedIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        guard existing.isEmpty else { return }
        seed(in: context)
    }

    static func seed(in context: ModelContext) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        let settings = AppSettings()
        context.insert(settings)

        let cafe = Workplace(
            name: "カフェA",
            colorHex: "C8FF00",
            hourlyWage: 1_200,
            transportAllowance: 500,
            notes: "駅から徒歩5分。まかないあり。",
            createdAt: date(year, 1, 1, calendar)
        )
        let conv = Workplace(
            name: "コンビニB",
            colorHex: "5B8CFF",
            hourlyWage: 1_300,
            transportAllowance: 400,
            notes: "深夜帯は時給に含めて記録する。",
            createdAt: date(year, 1, 2, calendar)
        )
        let juku = Workplace(
            name: "塾C",
            colorHex: "FF6B9A",
            hourlyWage: 1_500,
            transportAllowance: 300,
            notes: "生徒2名。準備も勤務時間に含める。",
            createdAt: date(year, 1, 3, calendar)
        )
        context.insert(cafe)
        context.insert(conv)
        context.insert(juku)

        guard
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
        else { return }

        var cursor = start
        while cursor <= end {
            let month = calendar.component(.month, from: cursor)
            let weekday = calendar.component(.weekday, from: cursor)
            if month != 11 {
                if weekday == 4 {
                    insert(cafe, cursor, 11 * 60, 16 * 60, 0, "", context)
                } else if weekday == 7 {
                    insert(conv, cursor, 18 * 60, 23 * 60, 0, "", context)
                } else if weekday == 2, calendar.component(.weekOfYear, from: cursor) % 2 == 0 {
                    insert(juku, cursor, 16 * 60, 19 * 60, 0, "", context)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let november: [(Int, Workplace, Int, Int, Int, String)] = [
            (1, cafe, 9 * 60, 14 * 60, 0, ""),
            (3, cafe, 12 * 60, 17 * 60, 0, ""),
            (3, conv, 18 * 60, 22 * 60, 0, ""),
            (5, cafe, 10 * 60, 16 * 60, 60, ""),
            (7, cafe, 10 * 60, 15 * 60, 0, ""),
            (8, conv, 18 * 60, 23 * 60, 0, ""),
            (10, juku, 16 * 60, 19 * 60, 0, ""),
            (12, cafe, 11 * 60, 16 * 60, 0, ""),
            (12, conv, 18 * 60, 22 * 60, 0, ""),
            (15, cafe, 11 * 60, 16 * 60, 0, ""),
            (15, conv, 17 * 60, 21 * 60, 0, ""),
            (17, cafe, 10 * 60, 14 * 60, 0, ""),
            (19, cafe, 13 * 60, 18 * 60, 30, "ホール"),
            (22, cafe, 10 * 60, 15 * 60, 0, ""),
            (24, cafe, 11 * 60, 16 * 60, 0, ""),
            (24, conv, 18 * 60, 23 * 60, 0, ""),
            (26, cafe, 10 * 60, 15 * 60, 0, ""),
            (29, cafe, 12 * 60, 17 * 60, 0, "")
        ]
        for spec in november {
            guard let day = calendar.date(from: DateComponents(year: year, month: 11, day: spec.0)) else { continue }
            insert(spec.1, day, spec.2, spec.3, spec.4, spec.5, context)
        }
        try? context.save()
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    private static func insert(
        _ workplace: Workplace,
        _ day: Date,
        _ start: Int,
        _ end: Int,
        _ breakMinutes: Int,
        _ notes: String,
        _ context: ModelContext
    ) {
        let shift = WorkShift(
            date: day,
            startMinutes: start,
            endMinutes: end,
            breakMinutes: breakMinutes,
            notes: notes,
            workplace: workplace
        )
        context.insert(shift)
    }
}
