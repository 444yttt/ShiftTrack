import Foundation

/// Hourly amount from the recovered walk in `0x10011b1d0`.
/// `0x10026e844` copies `ShiftInstance` start and end unchanged, then
/// replaces break minutes. No `min(now, end)` was found on that path.
/// The amount is that copied interval. It is not pay earned up to now.
/// 7500 yen for an 8-hour shift, 30 scaled break minutes, and a 1000 wage
/// is this formula's result. It was not read off the reference screen.
///
/// The wage integer is `selectedHourlyWage`. An empty history is 0.
/// If every history day is after the shift, the wage is left unset.
/// Wage-band bounds are still not applied. Each 60-second slice is scaled
/// by the no-span fraction. Overtime uses prior minutes of 0 because minutes
/// from earlier shifts were not identified.
enum ScheduledPay {
    struct Amount: Equatable {
        var base: Double
        var premium: Double
        var total: Double
    }

    enum Evaluation: Equatable {
        case amount(Amount)
        case notThisFormula
        case historyOpen
    }

    static func hourlyAmount(
        day: Date,
        start: Int,
        end: Int,
        breakMinutes: Int,
        workplace: Workplace,
        customPay: Int?,
        calendar: Calendar = .current
    ) -> Amount? {
        if case .amount(let amount) = evaluate(
            day: day,
            start: start,
            end: end,
            breakMinutes: breakMinutes,
            workplace: workplace,
            customPay: customPay,
            calendar: calendar
        ) {
            return amount
        }
        return nil
    }

    static func evaluate(
        day: Date,
        start: Int,
        end: Int,
        breakMinutes: Int,
        workplace: Workplace,
        customPay: Int?,
        calendar: Calendar = .current
    ) -> Evaluation {
        if customPay != nil || workplace.payIsDaily || breakMinutes < 0 {
            return .notThisFormula
        }
        let history = workplace.wageHistory.map { (effectiveFrom: $0.at, hourlyWage: $0.hourlyWage) }
        guard let wage = InOutRecovered.selectedHourlyWage(
            shiftDate: day,
            history: history,
            calendar: calendar
        ) else {
            return .historyOpen
        }
        let startDate = calendar.date(
            byAdding: .minute,
            value: ShiftDatePolicy.clockMinutes(start),
            to: calendar.startOfDay(for: day)
        ) ?? day
        var endDate = PayMath.endDate(day: day, start: start, end: end, calendar: calendar)
        var paidStart = startDate
        if workplace.roundingChangesClock {
            paidStart = InOutRecovered.roundedDate(
                startDate,
                unitMinutes: workplace.roundingUnitMinutes,
                direction: InOutRecovered.RoundingDirection.resolved(workplace.roundingStartRaw),
                calendar: calendar
            )
            endDate = InOutRecovered.roundedDate(
                endDate,
                unitMinutes: workplace.roundingUnitMinutes,
                direction: InOutRecovered.RoundingDirection.resolved(workplace.roundingEndRaw),
                calendar: calendar
            )
        }
        let duration = endDate.timeIntervalSince(paidStart)
        let base = InOutRecovered.scheduledHourlyYen(
            totalSeconds: duration,
            breakMinutes: breakMinutes,
            hourlyWage: wage
        )
        let fraction = InOutRecovered.paidMinuteFraction(
            totalSeconds: duration,
            breakMinutes: breakMinutes,
            hasBreakSpans: false
        )
        var premium = 0.0
        var prior = 0.0
        var cursor = paidStart
        let rates = workplace.holidayRatePercents
        while cursor < endDate {
            let next = min(endDate, cursor.addingTimeInterval(60))
            let sliceMinutes = next.timeIntervalSince(cursor) / 60
            let paidSlice = sliceMinutes * fraction
            let sliceYen = InOutRecovered.hourlyYen(paidMinutes: paidSlice, hourlyWage: wage)
            let midpoint = cursor.addingTimeInterval(next.timeIntervalSince(cursor) / 2)
            let minute = calendar.component(.hour, from: midpoint) * 60 + calendar.component(.minute, from: midpoint)
            premium += InOutRecovered.nightPremiumYen(
                sliceYen: sliceYen,
                ratePercent: workplace.nightRatePercent,
                enabled: workplace.nightPayEnabled,
                inWindow: InOutRecovered.minuteIsInPremiumWindow(
                    minuteOfDay: minute,
                    start: workplace.nightStartMinutes,
                    end: workplace.nightEndMinutes
                ),
                bandIncludesNight: false
            )
            if let holiday = InOutRecovered.holidayRatePercent(
                weekday: calendar.component(.weekday, from: midpoint),
                rates: rates
            ), holiday != 0 {
                premium += InOutRecovered.holidayPremiumYen(sliceYen: sliceYen, ratePercent: holiday)
            }
            let overtime = InOutRecovered.overtimeMinutes(
                sliceMinutes: paidSlice,
                priorMinutes: prior,
                threshold: Double(workplace.overtimeAfterMinutes)
            )
            if workplace.overtimeEnabled {
                premium += InOutRecovered.overtimePremiumYen(
                    overtimeMinutes: overtime,
                    hourlyWage: wage,
                    ratePercent: workplace.overtimeRatePercent
                )
            }
            prior += paidSlice
            cursor = next
        }
        return .amount(Amount(
            base: base,
            premium: premium,
            total: InOutRecovered.liveNumericTotal(base: base, premium: premium)
        ))
    }

    static func amountText(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == value.rounded(), abs(value) < Double(Int.max) {
            return Formatters.yen(Int(value))
        }
        return "¥" + String(format: "%.2f", value)
    }
}
