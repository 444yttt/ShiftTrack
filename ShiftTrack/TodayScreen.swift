import SwiftData
import SwiftUI

struct TodayScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]
    @Query private var settingsRows: [AppSettings]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var sheet: TodaySheet?
    @State private var pendingPlace: ShiftPartPlace.Pending?
    @State private var placeNote = ""
    /// Bumped when the app becomes active. The recovered 30-second and
    /// 1-second schedules were not tied to this timeline.
    @State private var resumedAt = Date.distantPast
    @State private var guidePage = 0
    @State private var showGuide = false
    private enum TodaySheet: Identifiable {
        case editor(EditorRoute)
        case part
        case unconfirmed
        case periods

        var id: String {
            switch self {
            case .editor(let route): "editor-\(route.id)"
            case .part: "part"
            case .unconfirmed: "unconfirmed"
            case .periods: "periods"
            }
        }
    }

    private var settings: AppSettings? { settingsRows.first }
    private var weekStartsOnMonday: Bool { settings?.weekStartsOnMonday ?? false }
    private var includeTransport: Bool { settings?.includeTransport ?? true }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = max(context.date, resumedAt)
            ScreenScroll {
                HStack {
                    InOutWordmark()
                    Spacer()
                    HelpButton { showGuide = true }
                }
                HStack {
                    Text("今週のシフト")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    weekButton("chevron.left") { moveWeek(-1) }
                    weekButton("chevron.right") { moveWeek(1) }
                }
                .padding(.top, 8)
                weekStrip
                    .highPriorityGesture(weekSwipe)
                Text(Formatters.longDay(day))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 12)
                Text(clock(now).replacingOccurrences(of: ":", with: "∶"))
                    .font(.doto(64))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("today.time")
                Text(Formatters.longDay(Date()))
                    .font(.system(size: 1))
                    .foregroundStyle(Theme.background)
                    .accessibilityIdentifier("today.clock")
                dayList(now: now)
                todoLine
                payCards(now: now)
                ShiftPartSection(
                    parts: parts,
                    dayChipDay: day,
                    patternDays: [day],
                    note: placeNote,
                    pending: pendingPlace,
                    canCreate: !workplaces.isEmpty,
                    gathering: false,
                    pickedCount: 0,
                    showsGathering: false,
                    showsPatternRows: false,
                    identifierPrefix: "today",
                    onToggleGathering: {},
                    onCreate: { sheet = .part },
                    onDayChip: { place($0) },
                    onPatternRow: { place($0) },
                    onClosePending: { pendingPlace = nil }
                )
            }
        }
        .background(Theme.background)
        .onAppear {
            if !GuideMemory.suppressed && !GuideMemory.seen("today") {
                showGuide = true
            }
        }
        .overlay {
            if showGuide {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    GuideCard(
                        page: guidePage + 1,
                        total: GuideCopy.today.count,
                        text: GuideCopy.today[guidePage],
                        onBack: guidePage == 0 ? nil : { guidePage -= 1 },
                        onNext: {
                            if guidePage + 1 >= GuideCopy.today.count {
                                GuideMemory.mark("today")
                                showGuide = false
                                guidePage = 0
                            } else {
                                guidePage += 1
                            }
                        },
                        onClose: {
                            GuideMemory.mark("today")
                            showGuide = false
                            guidePage = 0
                        }
                    )
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resumedAt = .now
            }
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .editor(let editor):
                ShiftEditorView(route: editor)
            case .part:
                ShiftPartEditor()
                    .presentationBackground(Theme.background)
            case .unconfirmed:
                UnconfirmedList(shifts: shifts.filter(\.needsAttendanceCheck)) { shift in
                    sheet = .editor(EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid))
                }
            case .periods:
                PayPeriodsView()
            }
        }
    }

    private func place(_ part: ShiftPart) {
        let result = ShiftPartCommit.apply(
            part: part,
            days: [day],
            shifts: shifts,
            workplaces: workplaces,
            context: modelContext
        )
        if let failure = result.failure {
            placeNote = failure
            pendingPlace = nil
            return
        }
        switch result.outcome {
        case .pending(let pending):
            pendingPlace = pending
            placeNote = "追加した件数 0"
        case .missingWorkplace:
            pendingPlace = nil
            placeNote = "勤務先がないので、どの日にも置いていません。"
        case .placed(let drafts):
            pendingPlace = nil
            placeNote = "置いた件数 \(drafts.count)。同じパターンの日は足していません。休憩は0分のままです。"
        }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("today.title")
            Text(Formatters.longDay(Date()))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("today.clock")
            Text(clock(now))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("today.time")
            if !Calendar.current.isDateInToday(day) {
                Text("下に出しているのは \(Formatters.longDay(day))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var weekStrip: some View {
        let days = weekDays
        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: day)
                let hasShift = shifts.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
                let filled = hasShift && !selected
                Button {
                    day = date
                } label: {
                    VStack(spacing: 4) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.doto(18))
                            .foregroundStyle(filled ? Theme.lime : Theme.ink)
                        Text(weekdayMark(date))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(filled ? Color.white.opacity(0.8) : Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(selected ? Theme.lime : (filled ? Theme.ink : Color.white))
                    .clipShape(Circle())
                    .overlay {
                        if selected && Calendar.current.isDateInToday(date) {
                            Circle().stroke(Theme.ink, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Formatters.longDay(date))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.week")
    }

    private var todoLine: some View {
        let titles = shifts
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .flatMap(\.todos)
            .map(\.title)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(Formatters.monthDayWeekday(day))のやること")
                .font(.system(size: 16, weight: .bold))
            if titles.isEmpty {
                Text("この日のやることはありません。シフトの「編集」から追加できます。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(titles.joined(separator: "、"))
                    .font(.system(size: 14))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 8)
    }

    private func payCards(now: Date) -> some View {
        let todayShifts = shifts.filter { Calendar.current.isDateInToday($0.date) }
        let todayYen = todayShifts.reduce(0) { $0 + $1.estimatedYen(includeTransport: includeTransport) }
        let monthMinutes = shifts.reduce(0) { sum, shift in
            let calendar = Calendar.current
            guard let interval = IncomeEngine.monthInterval(now, calendar: calendar) else { return sum }
            let day = calendar.startOfDay(for: shift.date)
            guard day >= interval.0, day < interval.1 else { return sum }
            return sum + shift.workedMinutes
        }
        let monthDays = Set(shifts.filter { shift in
            guard let interval = IncomeEngine.monthInterval(now) else { return false }
            let day = Calendar.current.startOfDay(for: shift.date)
            return day >= interval.0 && day < interval.1
        }.map { Calendar.current.startOfDay(for: $0.date) }).count
        let ended = shifts.filter(\.needsAttendanceCheck).count
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今日のお給料")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white)
                    Text(yenBody(todayYen) + " 円")
                        .font(.doto(28))
                        .foregroundStyle(Theme.lime)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("見込み")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                .background(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    Text("今月のお給料")
                        .font(.system(size: 13, weight: .medium))
                    Text(yenBody(monthYen(now: now)) + " 円")
                        .font(.doto(28))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("\(monthDays)日・\(Formatters.hours(monthMinutes))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Button {
                sheet = .periods
            } label: {
                rowLink("今月の支給見込み", value: "\(yenBody(monthYen(now: now)))円")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.periods")
            Button {
                sheet = .unconfirmed
            } label: {
                rowLink("確認していない勤務", value: "\(ended)件")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today.unconfirmed")
        }
        .padding(.top, 8)
    }

    private func rowLink(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .bold))
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var addShiftButton: some View {
        Button {
            sheet = .editor(EditorRoute(shiftID: nil, date: day, workplaceID: workplaces.first?.uuid))
        } label: {
            Text("+  シフトを追加")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Theme.ink)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("＋シフトを追加")
    }

    private func yenBody(_ value: Int) -> String {
        let body = Formatters.yen(value)
        return body.hasPrefix("¥") ? String(body.dropFirst()) : body
    }

    private func dayList(now: Date) -> some View {
        let rows = shifts
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.startMinutes < $1.startMinutes }
        return VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                VStack(spacing: 16) {
                    Text("この日のシフトはありません")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    addShiftButton
                        .padding(.bottom, 20)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                ForEach(rows) { shift in
                    shiftCard(shift, now: now)
                }
                addShiftButton
            }
        }
        .padding(.top, 8)
    }

    private func shiftCard(_ shift: WorkShift, now: Date) -> some View {
        let phase = phase(for: shift, now: now)
        let hours = Double(shift.workedMinutes) / 60
        return VStack(alignment: .leading, spacing: 12) {
            DayIllustration(hour: shift.startMinutes / 60)
            HStack {
                Circle()
                    .fill(shift.workplace?.color ?? Theme.lime)
                    .frame(width: 42, height: 42)
                    .overlay {
                        Text(String((shift.workplace?.name ?? "?").prefix(1)))
                            .font(.system(size: 18, weight: .bold))
                    }
                Text(shift.workplace?.name ?? "勤務先")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.muted)
            }
            HStack {
                Text(Formatters.monthDayWeekday(shift.date))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    sheet = .editor(EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid))
                } label: {
                    Label("編集", systemImage: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.cardRaised)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Formatters.clock(shift.startMinutes))–\(Formatters.clock(shift.endMinutes))")
                    .font(.doto(32))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(String(format: "%.1f時間", hours))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            if case .amount(let amount) = evaluation(for: shift, now: now) {
                Text(ScheduledPay.amountText(amount.total))
                    .font(.doto(36))
                    .accessibilityIdentifier("today.doto")
            }
            Text(LivePay.line(phase, evaluation: evaluation(for: shift, now: now)))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                miniAction("MAP")
                miniAction("電話")
                miniAction("メッセージ")
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func miniAction(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.cardRaised)
            .clipShape(Capsule())
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.left" ? "前の週" : "次の週")
        .accessibilityIdentifier(symbol == "chevron.left" ? "today.week.previous" : "today.week.next")
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
            customPay: shift.customPay,
            rollsToNextDay: shift.partID == nil ? nil : shift.patternEndOnNextDay
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

struct UnconfirmedList: View {
    var shifts: [WorkShift]
    var onEdit: (WorkShift) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(shifts) { shift in
                NavigationLink {
                    ShiftCheckView(shift: shift) { onEdit(shift) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Formatters.longDay(shift.date)) \(Formatters.clock(shift.startMinutes))〜\(Formatters.clock(shift.endMinutes))")
                            .designFont(13, weight: .bold)
                        Text(shift.workplace?.name ?? "勤務先")
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .navigationTitle("確認していない勤務")
            .safeAreaInset(edge: .top) {
                Text("終わった勤務を押すと、時間・休憩を確認できます。")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .toolbar {
                Button("閉じる") { dismiss() }
            }
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
