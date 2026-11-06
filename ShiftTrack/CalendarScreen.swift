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

    private var settings: AppSettings? { settingsRows.first }
    private var weekStartsOnMonday: Bool { settings?.weekStartsOnMonday ?? false }

    var body: some View {
        ScreenScroll {
            HStack {
                Text("しふとらっく")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Theme.lime)
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
        }
        .background(Theme.background)
        .sheet(isPresented: Binding(
            get: { selectedDay != nil },
            set: { if !$0 { selectedDay = nil } }
        )) {
            if let selectedDay {
                DayDetailSheet(day: selectedDay, workplaceID: selectedID)
            }
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet(
                title: "カレンダーの見方",
                paragraphs: [
                    "上の勤務先は、件数に合わせて横幅を等分します。タップすると、その勤務先のシフトだけを表示します。",
                    "日付の下の点は勤務先の色です。点が多い日は複数の勤務があります。",
                    "ライム色の日は選択中です。タップすると、その日のシフトを見たり追加したりできます。"
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
                .frame(height: 5)
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
        }
        .buttonStyle(.plain)
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
