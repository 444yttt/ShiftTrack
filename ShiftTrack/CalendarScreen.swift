import SwiftUI
import SwiftData

struct CalendarScreen: View {
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]

    @State private var month = Date()
    @State private var selectedID: UUID?
    @State private var selectedDay: Date?
    @State private var showHelp = false
    @State private var showAddChoices = false
    @State private var editor: EditorRoute?
    @State private var router = ImportRouter.shared

    private var settings: AppSettings? { settingsRows.first }
    private var weekStartsOnMonday: Bool { settings?.weekStartsOnMonday ?? false }

    var body: some View {
        ScreenScroll {
            HStack {
                Text("マイシフト")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                Spacer()
                HelpButton { showHelp = true }
            }
            .padding(.top, 8)

            FilterChipBar(workplaces: workplaces, selectedID: $selectedID)
                .padding(.top, 12)

            HStack(alignment: .center) {
                Text(Formatters.monthTitle(month))
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                Spacer()
                monthButton("chevron.left") { moveMonth(-1) }
                monthButton("chevron.right") { moveMonth(1) }
            }
            .padding(.top, 16)

            weekdayHeader
                .padding(.top, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 56)
                    }
                }
            }
            .padding(.top, 8)
            .gesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    if value.translation.width < -40 { moveMonth(1) }
                    if value.translation.width > 40 { moveMonth(-1) }
                }
            )

            HStack {
                Text(listTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if selectedDay != nil {
                    Button("月の一覧") { selectedDay = nil }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.lime)
                }
            }
            .padding(.top, 8)

            if listedShifts.isEmpty {
                Text(selectedDay == nil ? "この月のシフトはまだありません" : "この日のシフトはありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(listedShifts) { shift in
                        Button {
                            editor = EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid)
                        } label: {
                            ShiftCard(shift: shift, includeTransport: settings?.includeTransport ?? true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LimeCapsuleButton(title: "＋シフトを追加", fillWidth: true) {
                showAddChoices = true
            }
            .padding(.top, 4)

            Button {
                router.presentChooser()
            } label: {
                Text("シフト表から取り込む")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.lime)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.background)
        .sheet(isPresented: $showAddChoices) {
            ShiftAddChooser(day: addDay, workplaceID: selectedID)
        }
        .sheet(item: $editor) { route in
            ShiftEditorView(route: route)
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet(
                title: "マイシフトの見方",
                paragraphs: [
                    "カレンダーはスワイプで月を切り替えます。日をタップすると、その日のシフトを下に出します。月の一覧で、その月のシフトをまとめて見られます。",
                    "上の勤務先は横幅を等分します。タップすると、その勤務先だけを表示します。",
                    "「給」は給料日です。その他のカレンダーの設定で隠せます。",
                    "＋シフトを追加から、新しく入力するか、直近10件の履歴を選んで同じ時間を追加できます。"
                ]
            )
        }
    }

    private var cells: [Date?] {
        CalendarGrid.days(in: month, weekStartsOnMonday: weekStartsOnMonday)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(CalendarGrid.weekdaySymbols(weekStartsOnMonday: weekStartsOnMonday), id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let dayShifts = shiftsFor(day)
        let selected = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        let isToday = Calendar.current.isDateInToday(day)
        let colors = uniqueColors(dayShifts)
        return Button {
            selectedDay = Calendar.current.startOfDay(for: day)
        } label: {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(selected ? Theme.ink : .white)
                HStack(spacing: 3) {
                    if colors.isEmpty {
                        Circle().fill(Color.clear).frame(width: 5, height: 5)
                    } else {
                        ForEach(colors.prefix(3), id: \.self) { hex in
                            Circle()
                                .fill(selected ? Theme.ink.opacity(0.8) : Color(hexString: hex))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(selected ? Theme.lime : (dayShifts.isEmpty ? Color.clear : Theme.dayFilled))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if isToday && !selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.lime, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isPayday(day) {
                    Text("給")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(selected ? Theme.ink : Theme.lime)
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var listedShifts: [WorkShift] {
        let calendar = Calendar.current
        return shifts
            .filter { shift in
                if let selectedDay {
                    return calendar.isDate(shift.date, inSameDayAs: selectedDay)
                }
                return calendar.isDate(shift.date, equalTo: month, toGranularity: .month)
            }
            .filter { selectedID == nil || $0.workplace?.uuid == selectedID }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.startMinutes < rhs.startMinutes }
                return lhs.date < rhs.date
            }
    }

    private var listTitle: String {
        if let selectedDay { return Formatters.longDay(selectedDay) }
        return "この月のシフト"
    }

    private var addDay: Date {
        if let selectedDay { return selectedDay }
        let calendar = Calendar.current
        if calendar.isDate(Date(), equalTo: month, toGranularity: .month) { return Date() }
        return calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? Date()
    }

    private func isPayday(_ day: Date) -> Bool {
        guard settings?.showPaydayOnCalendar ?? true else { return false }
        let calendar = Calendar.current
        return workplaces.contains { workplace in
            calendar.isDate(PayMath.payday(in: day, workplace: workplace, calendar: calendar), inSameDayAs: day)
        }
    }

    private func shiftsFor(_ day: Date) -> [WorkShift] {
        shifts.filter { shift in
            Calendar.current.isDate(shift.date, inSameDayAs: day)
                && (selectedID == nil || shift.workplace?.uuid == selectedID)
        }
    }

    private func uniqueColors(_ dayShifts: [WorkShift]) -> [String] {
        var seen = Set<String>()
        var colors: [String] = []
        for shift in dayShifts.sorted(by: { $0.startMinutes < $1.startMinutes }) {
            guard let hex = shift.workplace?.colorHex, seen.insert(hex).inserted else { continue }
            colors.append(hex)
        }
        return colors
    }

    private func moveMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
        month = next
    }

    private func monthButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.dayFilled)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
