import SwiftUI
import SwiftData

struct CalendarScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query(sort: \ShiftRequest.date) private var requests: [ShiftRequest]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]
    @Query private var settingsRows: [AppSettings]

    @State private var month = Date()
    @State private var selectedID: UUID?
    @State private var selectedDay: Date?
    @State private var calendarDragging = false
    @State private var cover: CalendarCover?
    @State private var router = ImportRouter.shared
    @State private var gathering = false
    @State private var pickedDays: [Date] = []
    @State private var pendingPlace: ShiftPartPlace.Pending?
    @State private var placeNote = ""
    @State private var showGuide = false

    private enum CalendarCover: Identifiable {
        case workplace
        case add(Date)
        case editor(EditorRoute)
        case patterns
        case partEditor
        case request(RequestRoute)
        case help

        var id: String {
            switch self {
            case .workplace: "workplace"
            case .add(let date): "add-\(date.timeIntervalSinceReferenceDate)"
            case .editor(let route): "editor-\(route.id)"
            case .patterns: "patterns"
            case .partEditor: "part-editor"
            case .request(let route): "request-\(route.id)"
            case .help: "help"
            }
        }
    }

    private var settings: AppSettings? { settingsRows.first }
    private var weekStartsOnMonday: Bool { settings?.weekStartsOnMonday ?? false }

    var body: some View {
        ScreenScroll {
            HStack {
                InOutWordmark()
                Spacer()
                HelpButton { cover = .help }
            }
            .padding(.top, 8)

            if !workplaces.isEmpty {
                FilterChipBar(workplaces: workplaces, selectedID: $selectedID)
                    .padding(.top, 12)
            }

            HStack(alignment: .center) {
                Text(Formatters.monthTitle(month))
                    .font(.doto(40))
                    .foregroundStyle(Theme.ink)
                Spacer()
                monthButton("chevron.left", label: "前の月", identifier: "calendar.previousMonth") { moveMonth(-1) }
                monthButton("chevron.right", label: "次の月", identifier: "calendar.nextMonth") { moveMonth(1) }
            }
            .padding(.top, 16)
            if !Calendar.current.isDate(month, equalTo: .now, toGranularity: .month) {
                Button("今月に戻ります") {
                    month = Date()
                    selectedDay = ShiftDatePolicy.selectedDayAfterMonthChange(selected: selectedDay, visibleMonth: Date())
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.lime)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("calendar.thisMonth")
            }

            weekdayHeader
                .padding(.top, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(calendarCells) { cell in
                    if let day = cell.day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 56)
                    }
                }
            }
            .padding(.top, 8)
            .highPriorityGesture(
                DragGesture(minimumDistance: 28)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            calendarDragging = true
                        }
                    }
                    .onEnded { value in
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        defer { calendarDragging = false }
                        guard abs(horizontal) > abs(vertical), abs(horizontal) > 48 else { return }
                        moveMonth(horizontal < 0 ? 1 : -1)
                    }
            )

            patternSection

            HStack {
                Text(listTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if selectedDay != nil {
                    Button("月の一覧") { selectedDay = nil }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.lime)
                }
            }
            .padding(.top, 8)

            if workplaces.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("勤務先を1件追加すると、シフトを入れられます。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LimeCapsuleButton(title: "勤務先を追加", fillWidth: true) {
                        cover = .workplace
                    }
                }
            } else if listedShifts.isEmpty {
                Text(selectedDay == nil ? "この月のシフトはまだありません" : "この日のシフトはありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(listedShifts) { shift in
                        Button {
                            cover = .editor(EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid))
                        } label: {
                            ShiftCard(shift: shift, includeTransport: settings?.includeTransport ?? true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("calendar.shift")
                    }
                }
            }

            if !listedRequests.isEmpty {
                Text("希望")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                Text("希望はシフトではありません。給料の見込にも、今日の予定全体の時給分にも入りません。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    ForEach(listedRequests) { request in
                        Button {
                            cover = .request(RequestRoute(requestID: request.uuid, date: request.date))
                        } label: {
                            requestCard(request)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            LimeCapsuleButton(title: "＋シフトを追加", fillWidth: true) {
                cover = .add(addDay)
            }
            .padding(.top, 4)

            HStack(spacing: 12) {
                Button("パターン") { cover = .patterns }
                Button("希望を追加") {
                    cover = .request(RequestRoute(requestID: nil, date: addDay))
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.lime)
            .frame(maxWidth: .infinity)

            Button {
                router.presentChooser(fallbackDate: addDay, defaultWorkplace: assumedWorkplaceName)
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
        .onChange(of: router.focusRequest) { _, request in
            guard let request else { return }
            reveal(request.dates)
        }
        .onAppear {
            if !GuideMemory.suppressed && !GuideMemory.seen("calendar") {
                showGuide = true
            }
        }
        .overlay {
            if showGuide {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    GuideCard(
                        page: 1,
                        total: GuideCopy.calendar.count,
                        text: GuideCopy.calendar[0],
                        onBack: nil,
                        onNext: {
                            GuideMemory.mark("calendar")
                            showGuide = false
                        },
                        onClose: {
                            GuideMemory.mark("calendar")
                            showGuide = false
                        }
                    )
                }
            }
        }
        .sheet(item: $cover) { destination in
            switch destination {
            case .workplace:
                WorkplaceEditorView(existingID: nil)
            case .add(let day):
                ShiftAddChooser(day: day, workplaceID: selectedID, onSaved: reveal)
            case .editor(let route):
                ShiftEditorView(route: route, onSaved: { reveal([$0]) })
            case .patterns:
                PatternListView()
                    .presentationBackground(Theme.background)
            case .partEditor:
                ShiftPartEditor()
                    .presentationBackground(Theme.background)
            case .request(let route):
                RequestEditorView(route: route)
                    .presentationBackground(Theme.background)
            case .help:
                HelpSheet(
                    title: "カレンダーの見方",
                    paragraphs: [
                        "カレンダーを横にスワイプすると、見ている月だけが変わります。入っているシフトの日付は変わりません。日をタップすると、その日のシフトを下に出します。",
                        "上の勤務先は横幅を等分します。タップすると、その勤務先だけを表示します。",
                        "「給」は給料日です。月払いは今までと同じ日です。週払いと日払いは、勤務先で選んだときだけ印が変わります。設定のカレンダーで隠せます。",
                        "「希」は希望です。シフトではなく、給料には入りません。シフトにするまで見込金額は変わりません。",
                        "シフトパターンは、選んだ日へ開始・終了・勤務先を置きます。同じパターンの日は足しません。別のシフトがある日は保留して、そのタップでは追加しません。休憩は写しません。曜日のひな形は別の「パターン」です。",
                        "日付を押すと、その日の予定が下に出ます。選ぶモードのときだけ、その日をまとめて置く相手に加えます。赤い「！」は、時間の重なりや移動時間の不足がある日、と元の文にあります。印の出し方は未回収なので、この画面には出していません。保存の前の確認はシフト編集で出します。",
                        "＋シフトを追加の「シフト表」に日付と時刻を書くと、その場で保存してこの画面に出します。1件ずつ入力するか、直近10件の履歴からも追加できます。"
                    ]
                )
            }
        }
    }

    private struct CalendarCell: Identifiable {
        var id: String
        var day: Date?
    }

    private var calendarCells: [CalendarCell] {
        cells.enumerated().map { index, day in
            if let day {
                return CalendarCell(id: String(day.timeIntervalSinceReferenceDate), day: day)
            }
            return CalendarCell(id: "empty-\(index)", day: nil)
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
        let picked = pickedDays.contains { Calendar.current.isDate($0, inSameDayAs: day) }
        return Button {
            guard !calendarDragging else { return }
            let start = Calendar.current.startOfDay(for: day)
            selectedDay = start
            if gathering {
                togglePicked(start)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.doto(16))
                    .foregroundStyle(selected ? Theme.ink : (dayShifts.isEmpty ? Theme.ink : Theme.lime))
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
            .frame(height: 52)
            .background(selected ? Theme.lime : (dayShifts.isEmpty ? Theme.cardRaised : Theme.ink))
            .clipShape(Capsule())
            .overlay {
                if picked && !selected {
                    Capsule().stroke(Theme.lime, lineWidth: 1.5)
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
            .overlay(alignment: .topLeading) {
                if hasOpenRequest(day) {
                    Text("希")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(selected ? Theme.ink : Theme.lime)
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isToday ? "calendar.day.today" : dayIdentifier(day))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func dayIdentifier(_ day: Date) -> String {
        let calendar = Calendar.current
        return String(
            format: "calendar.day.%04d-%02d-%02d",
            calendar.component(.year, from: day),
            calendar.component(.month, from: day),
            calendar.component(.day, from: day)
        )
    }

    private var patternSection: some View {
        ShiftPartSection(
            parts: parts,
            dayChipDay: shownDay,
            patternDays: patternDays,
            note: placeNote,
            pending: pendingPlace,
            canCreate: !workplaces.isEmpty,
            gathering: gathering,
            pickedCount: pickedDays.count,
            onToggleGathering: {
                gathering.toggle()
                if !gathering {
                    pickedDays = []
                }
            },
            onCreate: { cover = .partEditor },
            onDayChip: { place($0, days: [shownDay]) },
            onPatternRow: { part in
                let days = patternDays
                guard !days.isEmpty else {
                    placeNote = "日付を選んでください"
                    pendingPlace = nil
                    return
                }
                place(part, days: days)
            },
            onClosePending: { pendingPlace = nil }
        )
    }

    private var shownDay: Date {
        selectedDay ?? addDay
    }

    private var patternDays: [Date] {
        if gathering {
            return pickedDays
        }
        return [shownDay]
    }

    private func togglePicked(_ day: Date) {
        if let index = pickedDays.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: day) }) {
            pickedDays.remove(at: index)
        } else {
            pickedDays.append(day)
        }
    }

    private func place(_ part: ShiftPart, days: [Date]) {
        let result = ShiftPartCommit.apply(
            part: part,
            days: days,
            shifts: shifts,
            workplaces: workplaces,
            context: context
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
            if drafts.count == 1 {
                selectedDay = drafts[0].day
                month = drafts[0].day
            }
        }
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

    private var assumedWorkplaceName: String {
        if let selectedID, let match = workplaces.first(where: { $0.uuid == selectedID }) {
            return match.name
        }
        return workplaces.count == 1 ? (workplaces.first?.name ?? "") : ""
    }

    private func reveal(_ dates: [Date]) {
        let days = Set(dates.map { Calendar.current.startOfDay(for: $0) })
        guard let first = days.min() else { return }
        month = first
        selectedDay = days.count == 1 ? first : nil
        selectedID = nil
    }

    private var addDay: Date {
        ShiftDatePolicy.anchorDay(selectedDay: selectedDay, visibleMonth: month)
    }

    private func isPayday(_ day: Date) -> Bool {
        guard settings?.showPaydayOnCalendar ?? true else { return false }
        let calendar = Calendar.current
        return workplaces.contains { workplace in
            let hasShift = shifts.contains { shift in
                shift.workplace?.uuid == workplace.uuid && calendar.isDate(shift.date, inSameDayAs: day)
            }
            return PaySchedule.showsMark(on: day, workplace: workplace, hasShiftThatDay: hasShift, calendar: calendar)
        }
    }

    private func hasOpenRequest(_ day: Date) -> Bool {
        openRequests.contains { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var openRequests: [ShiftRequest] {
        requests.filter { request in
            request.isOpen && (selectedID == nil || request.workplaceUUID == selectedID)
        }
    }

    private var listedRequests: [ShiftRequest] {
        let calendar = Calendar.current
        return openRequests
            .filter { request in
                if let selectedDay {
                    return calendar.isDate(request.date, inSameDayAs: selectedDay)
                }
                return calendar.isDate(request.date, equalTo: month, toGranularity: .month)
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.startMinutes < rhs.startMinutes }
                return lhs.date < rhs.date
            }
    }

    private func requestCard(_ request: ShiftRequest) -> some View {
        let workplace = workplaces.first { $0.uuid == request.workplaceUUID }
        return HStack(spacing: 10) {
            Text("希")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 22, height: 22)
                .background(Theme.lime)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(workplace?.name ?? "勤務先未定")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(Formatters.monthDayWeekday(request.date))  \(Formatters.clock(request.startMinutes))–\(Formatters.clock(request.endMinutes))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            let hex: String?
            if let partID = shift.partID, let part = parts.first(where: { $0.uuid == partID }) {
                hex = part.colorHex
            } else {
                hex = shift.workplace?.colorHex
            }
            guard let hex, seen.insert(hex).inserted else { continue }
            colors.append(hex)
        }
        return colors
    }

    private func moveMonth(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: delta, to: month) else { return }
        month = next
        selectedDay = ShiftDatePolicy.selectedDayAfterMonthChange(selected: selectedDay, visibleMonth: next)
    }

    private func monthButton(_ systemName: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.dayFilled)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
