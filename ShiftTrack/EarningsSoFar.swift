import Foundation

/// “Earnings so far” for one shift, shown live on the home screen.
///
/// The home screen used to show ¥0 because an older formula read the wage only
/// from `Workplace.wageHistory`, which is empty for workplaces made in the
/// editor or by import. This type uses `PayMath` / `PayRates` (the same table
/// as the monthly totals) and accrues the stored hourly wage for the time
/// already worked, including a shift that started yesterday. A break has no
/// clock time in this app, so it is spread evenly over the shift; when the
/// shift ends the value equals the shift's wage in the totals (transport and
/// 天引・手当 are not wages earned by the minute and are shown separately).
enum EarningsSoFar {
    enum Phase: Equatable {
        /// Seconds until the start.
        case upcoming(startsIn: TimeInterval)
        /// Seconds worked so far and seconds left.
        case working(elapsed: TimeInterval, remaining: TimeInterval)
        case finished
    }

    struct Progress: Equatable {
        var phase: Phase
        /// Wage earned up to `now`, floored to whole yen.
        var earnedYen: Int
        /// Wage for the whole shift (no transport, no adjustment).
        var wageTotalYen: Int
        /// Share of the shift's clock span that has passed, 0...1.
        var fraction: Double
        var start: Date
        var end: Date

        var isWorking: Bool {
            if case .working = phase { return true }
            return false
        }
    }

    /// Start and end instants of a stored shift. `rollsToNextDay` is the
    /// pattern flag (`nil` for ordinary rows, which roll when end <= start).
    static func interval(
        day: Date,
        start: Int,
        end: Int,
        rollsToNextDay: Bool?,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        let dayStart = calendar.startOfDay(for: day)
        guard let startDate = calendar.date(
            byAdding: .minute,
            value: ShiftDatePolicy.clockMinutes(start),
            to: dayStart
        ) else { return nil }
        let endDate = PayMath.endDate(
            day: day,
            start: start,
            end: end,
            rollsToNextDay: rollsToNextDay,
            calendar: calendar
        )
        guard endDate > startDate else { return nil }
        return (startDate, endDate)
    }

    static func interval(of shift: WorkShift, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        interval(
            day: shift.date,
            start: shift.startMinutes,
            end: shift.endMinutes,
            rollsToNextDay: shift.partID == nil ? nil : shift.patternEndOnNextDay,
            calendar: calendar
        )
    }

    static func progress(for shift: WorkShift, now: Date, calendar: Calendar = .current) -> Progress? {
        guard let workplace = shift.workplace else { return nil }
        return progress(
            workplace: workplace,
            day: shift.date,
            start: shift.startMinutes,
            end: shift.endMinutes,
            breakMinutes: shift.breakMinutes,
            customPay: shift.customPay,
            rollsToNextDay: shift.partID == nil ? nil : shift.patternEndOnNextDay,
            paidOverride: shift.partID == nil ? nil : shift.workedMinutes,
            now: now,
            calendar: calendar
        )
    }

    static func progress(
        workplace: Workplace,
        day: Date,
        start: Int,
        end: Int,
        breakMinutes: Int,
        customPay: Int? = nil,
        rollsToNextDay: Bool? = nil,
        paidOverride: Int? = nil,
        now: Date,
        calendar: Calendar = .current
    ) -> Progress? {
        guard let span = interval(day: day, start: start, end: end, rollsToNextDay: rollsToNextDay, calendar: calendar) else {
            return nil
        }
        let total = PayMath.quote(
            workplace: workplace,
            day: day,
            start: start,
            end: end,
            breakMinutes: breakMinutes,
            customPay: customPay,
            adjustment: 0,
            includeTransport: false,
            paidOverride: paidOverride,
            calendar: calendar
        )
        let length = span.end.timeIntervalSince(span.start)
        if now < span.start {
            return Progress(
                phase: .upcoming(startsIn: span.start.timeIntervalSince(now)),
                earnedYen: 0,
                wageTotalYen: total,
                fraction: 0,
                start: span.start,
                end: span.end
            )
        }
        if now >= span.end {
            return Progress(phase: .finished, earnedYen: total, wageTotalYen: total, fraction: 1, start: span.start, end: span.end)
        }
        let elapsed = now.timeIntervalSince(span.start)
        let fraction = min(1, max(0, elapsed / length))
        let earned: Double
        if customPay != nil || workplace.payIsDaily {
            earned = Double(total) * elapsed / length
        } else {
            let paidTotal = paidOverride ?? PayMath.workedMinutes(start: start, end: end, breakMinutes: breakMinutes)
            // Multiply before dividing so whole minutes stay exact in floating point.
            earned = PayMath.timedAmountExact(
                workplace: workplace,
                day: day,
                start: start,
                paidMinutes: Double(paidTotal) * elapsed / length,
                calendar: calendar
            )
        }
        // A hair of tolerance so 2999.9999999 (a whole ¥3,000 in exact math) does not show ¥2,999.
        let floored = Int((max(0, earned) + 1e-6).rounded(.down))
        return Progress(
            phase: .working(elapsed: elapsed, remaining: span.end.timeIntervalSince(now)),
            earnedYen: min(floored, total),
            wageTotalYen: total,
            fraction: fraction,
            start: span.start,
            end: span.end
        )
    }

    /// The shift in progress at `now`, including one stored on the previous
    /// day that runs past midnight. The earliest start wins when two overlap.
    static func current(in shifts: [WorkShift], now: Date, calendar: Calendar = .current) -> WorkShift? {
        shifts
            .compactMap { shift -> (WorkShift, Date)? in
                guard shift.workplace != nil, let span = interval(of: shift, calendar: calendar) else { return nil }
                return span.start <= now && now < span.end ? (shift, span.start) : nil
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}

/// Which shifts the home screen shows for the day being viewed.
enum HomeFocus {
    /// Shifts that belong on `day`: those stored on it, plus (for today) an
    /// overnight shift from yesterday that is still running. Sorted by start.
    static func shifts(on day: Date, from all: [WorkShift], now: Date, calendar: Calendar = .current) -> [WorkShift] {
        var rows = all.filter { calendar.isDate($0.date, inSameDayAs: day) }
        if calendar.isDate(day, inSameDayAs: now),
           let running = EarningsSoFar.current(in: all, now: now, calendar: calendar),
           !rows.contains(where: { $0.uuid == running.uuid }) {
            rows.append(running)
        }
        return rows.sorted { lhs, rhs in
            let left = EarningsSoFar.interval(of: lhs, calendar: calendar)?.start ?? lhs.date
            let right = EarningsSoFar.interval(of: rhs, calendar: calendar)?.start ?? rhs.date
            return left < right
        }
    }

    /// The workplace the quick actions act on: the shift in progress, else the
    /// next one still to come among `rows`, else the first row, else the first
    /// workplace.
    static func workplace(rows: [WorkShift], fallback: [Workplace], now: Date, calendar: Calendar = .current) -> Workplace? {
        if let running = rows.first(where: { shift in
            guard let span = EarningsSoFar.interval(of: shift, calendar: calendar) else { return false }
            return span.start <= now && now < span.end
        }), let place = running.workplace {
            return place
        }
        if let next = rows.first(where: { shift in
            guard let span = EarningsSoFar.interval(of: shift, calendar: calendar) else { return false }
            return span.start > now
        }), let place = next.workplace {
            return place
        }
        return rows.first?.workplace ?? fallback.first
    }

    /// One second while a shift is running, otherwise every 30 seconds.
    static func tickSeconds(shifts: [WorkShift], now: Date, calendar: Calendar = .current) -> Double {
        EarningsSoFar.current(in: shifts, now: now, calendar: calendar) == nil ? 30 : 1
    }
}
