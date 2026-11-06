import Foundation

enum PayMath {
    static func workedMinutes(start: Int, end: Int, breakMinutes: Int) -> Int {
        let span: Int
        if end > start {
            span = end - start
        } else if end < start {
            span = end + 24 * 60 - start
        } else {
            span = 0
        }
        return max(0, span - max(0, breakMinutes))
    }

    static func yen(hourlyWage: Int, transport: Int, minutes: Int, includeTransport: Bool) -> Int {
        let wage = minutes > 0 ? (max(0, hourlyWage) * minutes + 30) / 60 : 0
        let ride = includeTransport ? max(0, transport) : 0
        return wage + ride
    }

    static func endDate(day: Date, start: Int, end: Int, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: day)
        var endDate = calendar.date(byAdding: .minute, value: end, to: base) ?? day
        if end <= start {
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return endDate
    }
}

struct ShiftSnapshot: Identifiable {
    var id: UUID
    var workplaceID: UUID
    var workplaceName: String
    var colorHex: String
    var date: Date
    var endAt: Date
    var minutes: Int
    var yen: Int
}

enum IncomeEngine {
    struct Row: Identifiable {
        var id: UUID
        var name: String
        var colorHex: String
        var yen: Int
        var minutes: Int
        var share: Double
    }

    struct Totals {
        var workedYen = 0
        var workedMinutes = 0
        var scheduledYen = 0
        var scheduledMinutes = 0
        var rows: [Row] = []
        var forecastYen: Int { workedYen + scheduledYen }
        var forecastMinutes: Int { workedMinutes + scheduledMinutes }
    }

    static func totals(
        shifts: [ShiftSnapshot],
        from start: Date,
        until end: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Totals {
        var result = Totals()
        var buckets: [UUID: Row] = [:]
        for shift in shifts {
            let day = calendar.startOfDay(for: shift.date)
            guard day >= calendar.startOfDay(for: start), day < end else { continue }
            let worked = shift.endAt <= now
            if worked {
                result.workedYen += shift.yen
                result.workedMinutes += shift.minutes
            } else {
                result.scheduledYen += shift.yen
                result.scheduledMinutes += shift.minutes
            }
            var row = buckets[shift.workplaceID] ?? Row(
                id: shift.workplaceID,
                name: shift.workplaceName,
                colorHex: shift.colorHex,
                yen: 0,
                minutes: 0,
                share: 0
            )
            row.yen += shift.yen
            row.minutes += shift.minutes
            buckets[shift.workplaceID] = row
        }
        let total = result.forecastYen
        result.rows = buckets.values
            .filter { $0.yen > 0 || $0.minutes > 0 }
            .sorted { lhs, rhs in
                if lhs.yen == rhs.yen { return lhs.name < rhs.name }
                return lhs.yen > rhs.yen
            }
            .map { row in
                var copy = row
                copy.share = total > 0 ? Double(row.yen) / Double(total) : 0
                return copy
            }
        return result
    }

    static func annualized(workedYen: Int, now: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let days = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        guard day > 0, days > 0 else { return 0 }
        return Int((Double(workedYen) / Double(day) * Double(days)).rounded())
    }

    static func yearInterval(_ year: Int, calendar: Calendar = .current) -> (Date, Date)? {
        guard
            let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
            let end = calendar.date(byAdding: .year, value: 1, to: start)
        else { return nil }
        return (start, end)
    }

    static func monthInterval(_ date: Date, calendar: Calendar = .current) -> (Date, Date)? {
        let comps = calendar.dateComponents([.year, .month], from: date)
        guard
            let start = calendar.date(from: comps),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return nil }
        return (start, end)
    }
}

struct IncomeWall: Identifiable {
    var yen: Int
    var title: String
    var subtitle: String
    var detail: String
    var id: Int { yen }
}

enum IncomeWalls {
    static let all: [IncomeWall] = [
        IncomeWall(
            yen: 1_030_000,
            title: "103万",
            subtitle: "所得税の壁",
            detail: "給与収入103万円までなら所得税がかからず、扶養に残りやすい目安です。"
        ),
        IncomeWall(
            yen: 1_300_000,
            title: "130万",
            subtitle: "社会保険の壁",
            detail: "年収130万円を超えると、健康保険と年金の扶養から外れる目安です。週の労働時間や勤務先の規模でも加入が決まります。"
        ),
        IncomeWall(
            yen: 1_500_000,
            title: "150万",
            subtitle: "住民税の壁",
            detail: "住民税は自治体によりおおよそ100万円前後からかかることが多く、150万円は配偶者特別控除が満額になる上限としても知られています。"
        ),
        IncomeWall(
            yen: 1_600_000,
            title: "160万",
            subtitle: "特定扶養の壁",
            detail: "19〜22歳の特定扶養に関する控除の目安です。改正で金額が動くことがあります。"
        ),
        IncomeWall(
            yen: 1_780_000,
            title: "178万",
            subtitle: "扶養控除の壁",
            detail: "扶養控除の対象から外れていく年収帯の目安です。親の扶養か配偶者の扶養かで扱いが変わります。"
        ),
        IncomeWall(
            yen: 2_010_000,
            title: "201万",
            subtitle: "配偶者特別控除",
            detail: "配偶者特別控除は150万円を超えると段階的に減り、201万円を超えるとなくなる目安です。"
        )
    ]

    static let disclaimer = "登録したシフトからの概算です。税や社会保険の実際の判定は、働き方や家族の状況で変わります。"
}

enum CalendarGrid {
    static func weekdaySymbols(weekStartsOnMonday: Bool) -> [String] {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        guard weekStartsOnMonday else { return symbols }
        return Array(symbols[1...]) + [symbols[0]]
    }

    static func days(in month: Date, weekStartsOnMonday: Bool, calendar: Calendar = .current) -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard
            let first = calendar.date(from: comps),
            let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = weekStartsOnMonday ? (weekday + 5) % 7 : weekday - 1
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: first))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }
}

enum ShiftMapping {
    static func snapshots(_ shifts: [WorkShift], includeTransport: Bool) -> [ShiftSnapshot] {
        shifts.compactMap { shift in
            guard let workplace = shift.workplace else { return nil }
            return ShiftSnapshot(
                id: shift.uuid,
                workplaceID: workplace.uuid,
                workplaceName: workplace.name,
                colorHex: workplace.colorHex,
                date: shift.date,
                endAt: PayMath.endDate(day: shift.date, start: shift.startMinutes, end: shift.endMinutes),
                minutes: shift.workedMinutes,
                yen: shift.estimatedYen(includeTransport: includeTransport)
            )
        }
    }
}

enum TextNormalizer {
    static func fold(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping
        var result = ""
        result.reserveCapacity(folded.count)
        for character in folded {
            switch character {
            case "〜", "～", "~", "–", "—", "−", "－":
                result.append("-")
            default:
                result.append(character)
            }
        }
        return result
    }
}
