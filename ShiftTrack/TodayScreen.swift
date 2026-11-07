import SwiftData
import SwiftUI

struct TodayScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var editor: EditorRoute?
    /// Bumped when the app becomes active. The recovered 30-second and
    /// 1-second schedules were not tied to this timeline.
    @State private var resumedAt = Date.distantPast

    private var settings: AppSettings? { settingsRows.first }
    private var weekStartsOnMonday: Bool { settings?.weekStartsOnMonday ?? false }
    private var includeTransport: Bool { settings?.includeTransport ?? true }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = max(context.date, resumedAt)
            ScreenScroll {
                header(now: now)
                weekStrip
                    .highPriorityGesture(weekSwipe)
                summary(now: now)
                dayList(now: now)
                LimeCapsuleButton(title: "＋シフトを追加", fillWidth: true) {
                    editor = EditorRoute(shiftID: nil, date: day, workplaceID: workplaces.first?.uuid)
                }
                .padding(.top, 8)
            }
        }
        .background(Theme.background)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resumedAt = .now
            }
        }
        .sheet(item: $editor) { route in
            ShiftEditorView(route: route)
        }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(.white)
            Text("\(Formatters.longDay(day))  \(clock(now))")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var weekStrip: some View {
        let days = weekDays
        return HStack(spacing: 6) {
            weekButton("chevron.left") { moveWeek(-1) }
            ForEach(days, id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: day)
                let hasShift = shifts.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
                Button {
                    day = date
                } label: {
                    VStack(spacing: 4) {
                        Text(weekdayMark(date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(selected ? Theme.ink : .white)
                        Circle()
                            .fill(hasShift ? Color.white : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(selected ? Theme.lime : Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Formatters.longDay(date))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            weekButton("chevron.right") { moveWeek(1) }
        }
        .padding(.top, 12)
    }

    private func summary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("給与の目安")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.lime)
            Text("カードの円は、コピーされた開始から終了までを休憩の分数で割った時給分です。今を終了へ書く命令はこの経路にありません。時給は履歴の末尾から、適用日がシフトの日以前の行です。履歴が空のときは0で、勤務先の時給欄は使いません。8時間・休憩60分・時給1000円で休憩だけ30分にした式の結果は7500円です。これは画面で読んだ数字ではなく、今まで稼いだ金額でもありません。1秒の更新は開始以上かつ終了未満のときだけ作られ、その日付の出どころは未確定です。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("今月の見込み（このアプリの計算） \(Formatters.yen(monthYen(now: now)))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    private func dayList(now: Date) -> some View {
        let rows = shifts
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.startMinutes < $1.startMinutes }
        return VStack(alignment: .leading, spacing: 10) {
            Text(Calendar.current.isDateInToday(day) ? "今日のシフト" : Formatters.longDay(day))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 8)
            if rows.isEmpty {
                Text("この日のシフトはありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(rows) { shift in
                    Button {
                        editor = EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid)
                    } label: {
                        shiftCard(shift, now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shiftCard(_ shift: WorkShift, now: Date) -> some View {
        let phase = phase(for: shift, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(shift.workplace?.color ?? Theme.lime)
                    .frame(width: 10, height: 10)
                Text(shift.workplace?.name ?? "勤務先")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Formatters.clock(shift.startMinutes))–\(Formatters.clock(shift.endMinutes))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Text(LivePay.line(phase, evaluation: evaluation(for: shift, now: now)))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.lime)
            Text(LivePay.breakCaption(phase))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 48 else { return }
                moveWeek(value.translation.width < 0 ? 1 : -1)
            }
    }

    private func moveWeek(_ weeks: Int) {
        day = WeekPage.day(byAddingWeeks: weeks, to: day)
    }

    private var weekDays: [Date] {
        let start = weekStart(day)
        return (0..<7).compactMap { InOutRecovered.addingDays($0, to: start) }
    }

    private func weekStart(_ date: Date) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let leading = weekStartsOnMonday ? (weekday + 5) % 7 : weekday - 1
        return InOutRecovered.addingDays(-leading, to: dayStart) ?? dayStart
    }

    private func weekdayMark(_ date: Date) -> String {
        let symbols = CalendarGrid.weekdaySymbols(weekStartsOnMonday: false)
        let index = Calendar.current.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private func weekButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 64)
                .background(Theme.lime)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.left" ? "前の週" : "次の週")
    }

    private func clock(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(format: "%d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    private func phase(for shift: WorkShift, now: Date) -> LivePay.Phase {
        guard let workplace = shift.workplace else { return .notAShift }
        return LivePay.phase(
            now: now,
            day: shift.date,
            start: shift.startMinutes,
            end: shift.endMinutes,
            breakMinutes: shift.breakMinutes,
            workplace: workplace,
            customPay: shift.customPay
        )
    }

    private func evaluation(for shift: WorkShift, now: Date) -> ScheduledPay.Evaluation? {
        guard let workplace = shift.workplace else { return nil }
        let phase = phase(for: shift, now: now)
        let scaled: Int?
        switch phase {
        case .during(let value, _, _):
            scaled = value
        case .afterEnd(let value, _):
            scaled = value
        case .beforeStart, .notAShift:
            scaled = nil
        }
        guard let scaled else { return nil }
        return ScheduledPay.evaluate(
            day: shift.date,
            start: shift.startMinutes,
            end: shift.endMinutes,
            breakMinutes: scaled,
            workplace: workplace,
            customPay: shift.customPay
        )
    }

    private func monthYen(now: Date) -> Int {
        let calendar = Calendar.current
        guard let interval = IncomeEngine.monthInterval(now, calendar: calendar) else { return 0 }
        return shifts.reduce(0) { sum, shift in
            let day = calendar.startOfDay(for: shift.date)
            guard day >= interval.0, day < interval.1 else { return sum }
            return sum + shift.estimatedYen(includeTransport: includeTransport)
        }
    }
}

enum WeekPage {
    /// Moves the day being viewed. Does not write a stored shift date.
    /// `addingWeeks` is the recovered ×7 day step. Choosing ±1 follows the
    /// help text for the previous and next week, which was not an instruction
    /// in `0x10020499c`.
    static func day(byAddingWeeks weeks: Int, to day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return InOutRecovered.addingWeeks(weeks, to: start, calendar: calendar) ?? start
    }
}
