import Foundation

/// One shift already counted for a month. The screen chooses the month.
struct MonthShiftFact: Equatable {
    var startMinutes: Int
    var endMinutes: Int
    var workedMinutes: Int
    var yen: Int
    var workplaceName: String
}

/// Hours, yen, and late-night count are computed here. A model does not write them.
enum MonthFacts {
    struct Summary: Equatable {
        var shiftCount: Int
        var workedMinutes: Int
        var estimatedPayYen: Int
        var lateNightShiftCount: Int
        var workplaceCount: Int
    }

    static func summarize(
        _ rows: [MonthShiftFact],
        nightStart: Int = InOutRecovered.defaultNightStartMinute,
        nightEnd: Int = InOutRecovered.defaultNightEndMinute
    ) -> Summary {
        let names = Set(rows.map(\.workplaceName).filter { !$0.isEmpty })
        return Summary(
            shiftCount: rows.count,
            workedMinutes: rows.reduce(0) { $0 + max(0, $1.workedMinutes) },
            estimatedPayYen: rows.reduce(0) { $0 + $1.yen },
            lateNightShiftCount: rows.filter {
                overlapsNight(start: $0.startMinutes, end: $0.endMinutes, nightStart: nightStart, nightEnd: nightEnd)
            }.count,
            workplaceCount: names.count
        )
    }

    /// Night is the workplace wall-clock window, usually 22:00–5:00.
    /// A morning shift can sit inside the 0:00–5:00 half without crossing midnight itself.
    static func overlapsNight(start: Int, end: Int, nightStart: Int, nightEnd: Int) -> Bool {
        let pieces = end > start ? [(start, end)] : [(start, 24 * 60), (0, end)]
        let nights = [(0, nightEnd), (nightStart, 24 * 60)]
        return pieces.contains { piece in
            nights.contains { night in
                min(piece.1, night.1) > max(piece.0, night.0)
            }
        }
    }

    static func headline(_ summary: Summary) -> String {
        "\(Formatters.hours(summary.workedMinutes))勤務・給与見込み\(Formatters.yen(summary.estimatedPayYen))・深夜勤務\(summary.lateNightShiftCount)回"
    }

}
