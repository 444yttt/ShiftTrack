import Foundation

/// Local notification times. The system is asked only for future fires.
struct ShiftNotice: Equatable {
    enum Kind: String, Equatable {
        case before
        case end
    }

    static let prefix = "shifttrack.notice."
    static let leadMinutes = 30

    var shiftID: UUID
    var kind: Kind
    var fire: Date
    var title: String
    var body: String

    var identifier: String { "\(Self.prefix)\(kind.rawValue).\(shiftID.uuidString)" }

    struct Input: Equatable {
        var id: UUID
        var name: String
        var start: Date
        var end: Date
    }
}

enum ShiftNotices {
    static func interval(
        day: Date,
        startMinutes: Int,
        endMinutes: Int,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        let base = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .minute, value: startMinutes, to: base) ?? base
        var end = calendar.date(byAdding: .minute, value: endMinutes, to: base) ?? base
        if end <= start {
            end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return (start, end)
    }

    /// At most the fires that are still ahead, inside the horizon.
    static func plan(
        _ rows: [ShiftNotice.Input],
        now: Date,
        before: Bool,
        atEnd: Bool,
        leadMinutes: Int = ShiftNotice.leadMinutes,
        horizon: TimeInterval = 14 * 24 * 60 * 60
    ) -> [ShiftNotice] {
        let limit = now.addingTimeInterval(horizon)
        let lead = TimeInterval(max(0, leadMinutes) * 60)
        var notices: [ShiftNotice] = []
        for row in rows {
            let name = row.name.isEmpty ? "勤務" : row.name
            if before {
                let fire = row.start.addingTimeInterval(-lead)
                if fire > now, fire <= limit {
                    notices.append(ShiftNotice(
                        shiftID: row.id,
                        kind: .before,
                        fire: fire,
                        title: "まもなく勤務です",
                        body: "\(name) の開始 \(Self.clock(row.start)) の \(leadMinutes) 分前です。"
                    ))
                }
            }
            if atEnd, row.end > now, row.end <= limit {
                notices.append(ShiftNotice(
                    shiftID: row.id,
                    kind: .end,
                    fire: row.end,
                    title: "勤務の終わりです",
                    body: "\(name) の終了時刻です。時間を確認できます。"
                ))
            }
        }
        return notices.sorted { $0.fire < $1.fire }
    }

    private static func clock(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(format: "%d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}
