import SwiftData
import SwiftUI

struct PayBreakdownScreen: View {
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Environment(\.dismiss) private var dismiss
    @State private var anchor = Date()

    private var calendar: Calendar { ShiftOverlap.tokyo }

    var body: some View {
        let slices = monthSlices
        let base = slices.reduce(0) { $0 + $1.baseYen }
        let transport = slices.reduce(0) { $0 + $1.transportYen }
        let adjustment = slices.reduce(0) { $0 + $1.adjustmentYen }
        let total = base + transport + adjustment
        return ScreenScroll {
            HStack {
                Text("\(calendar.component(.month, from: anchor))月の給与")
                    .designFont(16, weight: .black)
                Spacer()
                Button("閉じる") { dismiss() }
                    .foregroundStyle(Theme.accentText)
            }
            Text("支給見込み")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            Text(Formatters.yen(total))
                .designFont(34, weight: .semibold, design: .rounded, digits: true)
                .foregroundStyle(Theme.ink)
            Text("深夜・休日の割増は、この内訳では分けていません。今日の見込とは別の計算です。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            composition(base: base, transport: transport, adjustment: adjustment)
            row("基本給", yen: base, signed: false)
            row("交通費", yen: transport, signed: true)
            row("天引・手当", yen: adjustment, signed: true)
            Text("勤務先別")
                .designFont(17, weight: .semibold)
                .padding(.top, SpacingTokens.annualIncome[2])
            ForEach(workplaceTotals(slices), id: \.id) { place in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .designFont(16)
                        Text(Formatters.hours(place.minutes))
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(Formatters.yen(place.yen))
                        .designFont(16, weight: .semibold, design: .rounded, digits: true)
                }
                .padding(.vertical, SpacingTokens.annualIncome[0])
            }
            Text("入金予定")
                .designFont(17, weight: .semibold)
                .padding(.top, SpacingTokens.annualIncome[2])
            ForEach(PayBreakdown.groupedByPayday(slices), id: \.day.key) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.day.month)月\(group.day.day)日")
                        .designFont(17, weight: .semibold)
                    Text(Formatters.yen(group.slices.reduce(0) { $0 + $1.total }))
                        .designFont(20, weight: .semibold, design: .rounded, digits: true)
                    ForEach(group.slices) { slice in
                        Text("\(slice.workplaceName)  \(Formatters.yen(slice.total))")
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, SpacingTokens.annualIncome[0])
            }
            live
        }
        .background(Theme.background)
    }

    private var monthSlices: [PaySlice] {
        let month = calendar.component(.month, from: anchor)
        let year = calendar.component(.year, from: anchor)
        return shifts.compactMap { shift in
            guard let place = shift.workplace else { return nil }
            let day = LocalDay.from(shift.date, calendar: calendar)
            guard day.year == year, day.month == month else { return nil }
            let history = place.wageHistory.map {
                WagePoint(day: LocalDay.from($0.at, calendar: calendar), yen: $0.hourlyWage)
            }
            return PayBreakdown.slice(
                PayShiftInput(
                    shiftID: shift.uuid,
                    workplaceID: place.uuid,
                    workplaceName: place.name,
                    day: day,
                    minutes: PayMath.workedMinutes(start: shift.startMinutes, end: shift.endMinutes, breakMinutes: shift.breakMinutes),
                    hourlyFallback: place.hourlyWage,
                    history: history,
                    transport: place.transportAllowance,
                    adjustment: shift.adjustmentYen,
                    closingDay: place.closingDay,
                    paydayDay: place.paydayDay,
                    monthOffset: place.paydayMonthOffset
                ),
                calendar: calendar
            )
        }
    }

    private func workplaceTotals(_ slices: [PaySlice]) -> [(id: UUID, name: String, minutes: Int, yen: Int)] {
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var minutes: [UUID: Int] = [:]
        var yen: [UUID: Int] = [:]
        for slice in slices {
            if names[slice.workplaceID] == nil { order.append(slice.workplaceID) }
            names[slice.workplaceID] = slice.workplaceName
            minutes[slice.workplaceID, default: 0] += slice.minutes
            yen[slice.workplaceID, default: 0] += slice.total
        }
        return order.map { ($0, names[$0] ?? "", minutes[$0] ?? 0, yen[$0] ?? 0) }
    }

    @ViewBuilder
    private func composition(base: Int, transport: Int, adjustment: Int) -> some View {
        let parts = [base, max(0, transport), max(0, adjustment)].filter { $0 > 0 }
        if parts.count > 1 {
            let sum = parts.reduce(0, +)
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(Theme.lime.opacity(part == base ? 1 : 0.45))
                        .frame(width: max(4, 280 * CGFloat(part) / CGFloat(max(sum, 1))), height: 10)
                }
            }
            .clipShape(Capsule())
        }
    }

    private func row(_ title: String, yen: Int, signed: Bool) -> some View {
        HStack {
            Text(title)
                .designFont(16)
            Spacer()
            Text(signed && yen > 0 ? "+\(Formatters.yen(yen))" : Formatters.yen(yen))
                .designFont(16, weight: .semibold, design: .rounded, digits: true)
        }
        .padding(.vertical, 10)
    }

    private var live: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let active = shifts.first { shift in
                guard let start = shiftStart(shift), let end = shiftEnd(shift) else { return false }
                return context.date >= start && context.date < end
            }
            if let active, let start = shiftStart(active) {
                let elapsed = Int(context.date.timeIntervalSince(start))
                let yen = LiveEarnings.yen(elapsedSeconds: elapsed, breakSeconds: 0, hourlyYen: active.workplace?.hourlyWage ?? 0)
                VStack(alignment: .leading, spacing: 6) {
                    Text("勤務中")
                        .designFont(13)
                        .foregroundStyle(Theme.muted)
                    Text(Formatters.yen(yen))
                        .designFont(38, weight: .semibold, design: .rounded, digits: true)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.18), value: yen)
                    Text("休憩の時刻が無い分は引いていません。表示は切り捨てです。")
                        .designFont(13)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, SpacingTokens.annualIncome[1])
            }
        }
    }

    private func shiftStart(_ shift: WorkShift) -> Date? {
        let day = calendar.startOfDay(for: shift.date)
        return calendar.date(byAdding: .minute, value: shift.startMinutes, to: day)
    }

    private func shiftEnd(_ shift: WorkShift) -> Date? {
        guard let start = shiftStart(shift) else { return nil }
        var minutes = shift.endMinutes - shift.startMinutes
        if minutes <= 0 { minutes += 24 * 60 }
        return calendar.date(byAdding: .minute, value: minutes, to: start)
    }
}
