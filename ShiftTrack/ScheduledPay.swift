import Foundation

/// Hourly amount from the recovered walk in `0x10011b1d0`.
/// The live caller copies the shift's own start and end, then replaces
/// `breakMinutes` only. This amount is that scheduled interval. It is not
/// pay earned up to now.
///
/// Each 60-second slice is scaled by the no-span fraction, so the base sum
/// matches `scheduledHourlyYen`. Night and holiday use that slice's base.
/// Overtime counts the same paid slice, with prior minutes of 0: minutes
/// from earlier shifts were not identified. Wage bands and a non-empty wage
/// history are not applied; those selection rules were not closed.
enum ScheduledPay {
    struct Amount: Equatable {
        var base: Double
        var premium: Double
        var total: Double
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
        if customPay != nil || workplace.payIsDaily || breakMinutes < 0 {
            return nil
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
            hourlyWage: workplace.hourlyWage
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
            let sliceYen = InOutRecovered.hourlyYen(paidMinutes: paidSlice, hourlyWage: workplace.hourlyWage)
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
                    hourlyWage: workplace.hourlyWage,
                    ratePercent: workplace.overtimeRatePercent
                )
            }
            prior += paidSlice
            cursor = next
        }
        return Amount(
            base: base,
            premium: premium,
            total: InOutRecovered.liveNumericTotal(base: base, premium: premium)
        )
    }

    static func amountText(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == value.rounded(), abs(value) < Double(Int.max) {
            return Formatters.yen(Int(value))
        }
        return "¥" + String(format: "%.2f", value)
    }
}
