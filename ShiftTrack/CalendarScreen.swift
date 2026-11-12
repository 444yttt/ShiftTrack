import SwiftData
import SwiftUI

/// カレンダー. Month grid in a white card, the selected day's shifts and
/// requests, shift patterns, and the other ways to add shifts.
struct CalendarScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var lastPlaced: [WorkShift] = []

    private enum CalendarCover: Identifiable {
        case workplace
        case add(Date)
        case editor(EditorRoute)
        case patterns
        case partEditor
        case partEdit(UUID)
        case partList
        case request(RequestRoute)
        case help

        var id: String {
            switch self {
            case .workplace: "workplace"
            case .add(let date): "add-\(date.timeIntervalSinceReferenceDate)"
            case .editor(let route): "editor-\(route.id)"
            case .patterns: "patterns"
            case .partEditor: "part-editor"
            case .partEdit(let id): "part-\(id.uuidString)"
            case .partList: "part-list"
            case .request(let route): "request-\(route.id)"
            case .help: "help"
            }
        }
    }

    private var settings: AppSettings? { settingsRows.first }
    private var weekStartsOnMonday: Bool { settings?.weekStartsOnMonday ?? false }
    private var includeTransport: Bool { settings?.includeTransport ?? true }

    var body: some View {
        ScreenScroll(spacing: Space.m) {
            ScreenHeader(title: "カレンダー") {
                HelpButton { cover = .help }
                IconButton(systemImage: "plus", label: "シフトを追加", prominent: true, identifier: "calendar.add") {
                    cover = workplaces.isEmpty ? .workplace : .add(addDay)
                }
            }

            if workplaces.count >= 2 {
                FilterChipBar(workplaces: workplaces, selectedID: $selectedID)
            }

            monthCard

            daySection

            if !workplaces.isEmpty {
                patternSection
            }

            moreWays
        }
        .background(Theme.paper)
        .onChange(of: router.focusRequest) { _, request in
            guard let request else { return }
            reveal(request.dates)
        }
        .sheet(item: $cover) { destination in
            sheetContent(destination)
        }
    }

    // MARK: Month

    private var monthCard: some View {
        Card(spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.xxs) {
                DotoText(
                    Formatters.dotoMonth(month),
                    size: 30,
                    spoken: Formatters.monthTitle(month)
                )
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendar.month")
                Spacer(minLength: Space.xxs)
                if !Calendar.current.isDate(month, equalTo: .now, toGranularity: .month) {
                    TextLinkButton(title: "今月", identifier: "calendar.thisMonth") {
                        changeMonth(to: Date())
                    }
                }
                monthButton("chevron.left", label: "前の月", identifier: "calendar.previousMonth") { moveMonth(-1) }
                monthButton("chevron.right", label: "次の月", identifier: "calendar.nextMonth") { moveMonth(1) }
            }
            .sensoryFeedback(.selection, trigger: month)
            weekdayHeader
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(calendarCells) { cell in
                    if let day = cell.day {
                        dayCell(day)
                    } else {
                        Color.clear
                            .frame(height: 58)
                            .accessibilityHidden(true)
                    }
                }
            }
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
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: Space.s) {
            legendItem(Circle().fill(Theme.ink2).frame(width: 7, height: 7), "シフト")
            legendItem(Text("給").font(AppFont.badge).foregroundStyle(Theme.signalInk), "給料日")
            legendItem(Text("希").font(AppFont.badge).foregroundStyle(Theme.ink), "シフト希望")
        }
        .font(AppFont.helper)
        .foregroundStyle(Theme.ink2)
        .accessibilityElement(children: .combine)
    }

    private func legendItem<Mark: View>(_ mark: Mark, _ title: String) -> some View {
        HStack(spacing: 4) {
            mark
            Text(title)
        }
    }

    private struct CalendarCell: Identifiable {
        var id: String
        var day: Date?
    }

    private var calendarCells: [CalendarCell] {
        CalendarGrid.days(in: month, weekStartsOnMonday: weekStartsOnMonday).enumerated().map { index, day in
            if let day {
                return CalendarCell(id: String(day.timeIntervalSinceReferenceDate), day: day)
            }
            return CalendarCell(id: "empty-\(index)", day: nil)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(CalendarGrid.weekdaySymbols(weekStartsOnMonday: weekStartsOnMonday), id: \.self) { symbol in
                Text(symbol)
                    .font(AppFont.helper.weight(.semibold))
                    .foregroundStyle(weekdayColor(symbol: symbol))
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private static let sundayRed = Theme.danger
    /// Saturday blue: 6.6:1 on white.
    private func weekdayColor(symbol: String) -> Color {
        switch symbol {
        case "日": Self.sundayRed
        case "土": Theme.saturday
        default: Theme.ink2
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let dayShifts = shiftsFor(day)
        let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDateInToday(day)
        let colors = uniqueColors(dayShifts)
        let picked = pickedDays.contains { calendar.isDate($0, inSameDayAs: day) }
        let payday = isPayday(day)
        let request = hasOpenRequest(day)
        let weekday = calendar.component(.weekday, from: day)
        let numberColor: Color = selected
            ? Theme.onInk
            : (isToday ? Theme.onSignal : (weekday == 1 ? Self.sundayRed : (weekday == 7 ? Theme.saturday : Theme.ink)))
        return Button {
            guard !calendarDragging else { return }
            let start = calendar.startOfDay(for: day)
            selectedDay = start
            if gathering {
                togglePicked(start)
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(numberColor)
                HStack(spacing: 2) {
                    ForEach(colors.prefix(3), id: \.self) { hex in
                        Circle()
                            .fill(Color(hexString: hex))
                            .overlay(Circle().stroke(selected ? Theme.onInk : Theme.ink.opacity(0.35), lineWidth: 1))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(height: 8)
                HStack(spacing: 1) {
                    if payday {
                        Text("給")
                            .font(AppFont.badge)
                            .foregroundStyle(selected ? Theme.onInk : Theme.signalInk)
                    }
                    if request {
                        Text("希")
                            .font(AppFont.badge)
                            .foregroundStyle(selected ? Theme.onInk : Theme.ink)
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                selected ? Theme.ink : (isToday ? Theme.signal : Theme.paper),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay {
                if picked {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(selected ? Theme.signal : Theme.ink, lineWidth: 2.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if picked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(selected ? Theme.onInk : Theme.ink)
                        .padding(2)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayLabel(day, shifts: dayShifts.count, payday: payday, request: request, isToday: isToday))
        .accessibilityAddTraits(selected || picked ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier(isToday ? "calendar.day.today" : dayIdentifier(day))
    }

    private func dayLabel(_ day: Date, shifts: Int, payday: Bool, request: Bool, isToday: Bool) -> String {
        var parts = [Formatters.longDay(day)]
        if isToday { parts.append("今日") }
        if shifts > 0 { parts.append("シフト\(shifts)件") }
        if payday { parts.append("給料日") }
        if request { parts.append("シフト希望あり") }
        return parts.joined(separator: "、")
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

    // MARK: Day

    private var daySection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(
                title: listTitle,
                detail: selectedDay == nil ? "日付を押すと、その日だけを出します。" : nil,
                actionTitle: selectedDay == nil ? nil : "月の一覧に戻る",
                actionIdentifier: "calendar.monthList",
                action: selectedDay == nil ? nil : { selectedDay = nil }
            )
            if workplaces.isEmpty {
                EmptyState(
                    systemImage: "building.2",
                    message: "勤務先を1件登録すると、シフトを入れられます。",
                    actionTitle: "勤務先を追加",
                    actionIdentifier: "calendar.workplace.add"
                ) {
                    cover = .workplace
                }
            } else if listedShifts.isEmpty {
                EmptyState(
                    systemImage: "calendar",
                    message: selectedDay == nil ? "この月のシフトはまだありません" : "この日のシフトはありません",
                    actionTitle: selectedDay == nil ? "＋シフトを追加" : "この日に追加",
                    actionIdentifier: "calendar.addOnDay"
                ) {
                    cover = .add(addDay)
                }
            } else {
                ForEach(listedShifts) { shift in
                    Button {
                        cover = .editor(EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid))
                    } label: {
                        ShiftCard(shift: shift, includeTransport: includeTransport)
                    }
                    .buttonStyle(.plain)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                    .accessibilityIdentifier("calendar.shift")
                    .accessibilityLabel(ShiftSpeech.card(shift, includeTransport: includeTransport))
                }
                .animation(Motion.allowed(Motion.settle, reduce: reduceMotion), value: listedShifts.map(\.uuid))
                if selectedDay != nil {
                    SecondaryButton(title: "この日に追加", systemImage: "plus", identifier: "calendar.addOnDay") {
                        cover = .add(addDay)
                    }
                }
            }
            if !listedRequests.isEmpty {
                SectionHeader(title: "シフト希望", detail: "希望はシフトではありません。シフトにするまで、給料の見込みには入りません。")
                ForEach(listedRequests) { request in
                    Button {
                        cover = .request(RequestRoute(requestID: request.uuid, date: request.date))
                    } label: {
                        requestCard(request)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(requestLabel(request))
                }
            }
        }
    }

    private var listTitle: String {
        if let selectedDay { return Formatters.longDay(selectedDay) }
        return "この月のシフト"
    }

    private func requestLabel(_ request: ShiftRequest) -> String {
        let name = workplaces.first { $0.uuid == request.workplaceUUID }?.name ?? "勤務先未定"
        let kind = request.kindRaw == ShiftRequestKind.hopedRest ? "休み希望" : "出勤希望"
        return "\(kind)、\(name)、\(Formatters.monthDayWeekday(request.date))、\(Formatters.clock(request.startMinutes))から\(Formatters.clock(request.endMinutes))"
    }

    private func requestCard(_ request: ShiftRequest) -> some View {
        let workplace = workplaces.first { $0.uuid == request.workplaceUUID }
        let rest = request.kindRaw == ShiftRequestKind.hopedRest
        return HStack(spacing: Space.s) {
            Text("希")
                .font(AppFont.badge)
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(Theme.sunken, in: Circle())
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(rest ? "休み希望" : "出勤希望")・\(workplace?.name ?? "勤務先未定")")
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text("\(Formatters.monthDayWeekday(request.date))  \(Formatters.clock(request.startMinutes))–\(Formatters.clock(request.endMinutes))")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: Space.xs)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink2)
                .accessibilityHidden(true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: Patterns

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
                    placeNote = "日付を選んでください。"
                    pendingPlace = nil
                    return
                }
                place(part, days: days)
            },
            onClosePending: { pendingPlace = nil },
            onEdit: { cover = .partEdit($0.uuid) },
            onManage: { cover = .partList },
            onUndo: lastPlaced.isEmpty ? nil : { undoPlace() }
        )
    }

    private var shownDay: Date {
        selectedDay ?? addDay
    }

    private var patternDays: [Date] {
        gathering ? pickedDays : [shownDay]
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
        lastPlaced = result.inserted
        if let failure = result.failure {
            placeNote = failure
            pendingPlace = nil
            return
        }
        switch result.outcome {
        case .pending(let pending):
            pendingPlace = pending
            placeNote = "置きませんでした（0件）。"
        case .missingWorkplace:
            pendingPlace = nil
            placeNote = "このパターンの勤務先が見つからないため、置けませんでした。"
        case .placed(let drafts):
            pendingPlace = nil
            placeNote = ShiftPartPlace.placedNote(count: drafts.count)
            if drafts.count == 1 {
                selectedDay = drafts[0].day
                month = drafts[0].day
            }
        }
    }

    private func undoPlace() {
        ShiftPartCommit.undo(lastPlaced, context: context)
        lastPlaced = []
        placeNote = "取り消しました。"
    }

    // MARK: More ways to add

    private var moreWays: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "ほかの追加方法")
            Card(spacing: 0) {
                Button {
                    cover = .patterns
                } label: {
                    NavRow(systemImage: "repeat", title: "曜日でまとめて入れる", subtitle: "毎週入る曜日と時間の型から、空いている日にシフトを作ります")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("calendar.patterns")
                RowDivider()
                Button {
                    cover = .request(RequestRoute(requestID: nil, date: addDay))
                } label: {
                    NavRow(systemImage: "hand.raised", title: "シフト希望を残す", subtitle: "出したい希望を記録します。給料の見込みには入りません")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("calendar.request.add")
                RowDivider()
                Button {
                    router.presentChooser(fallbackDate: addDay, defaultWorkplace: assumedWorkplaceName)
                } label: {
                    NavRow(systemImage: "text.viewfinder", title: "シフト表から取り込む", subtitle: "写真や文字のシフト表を読み取って、まとめて入れます")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("calendar.import")
            }
        }
    }

    // MARK: Sheets

    @ViewBuilder private func sheetContent(_ destination: CalendarCover) -> some View {
        switch destination {
        case .workplace:
            WorkplaceWizard()
        case .add(let day):
            ShiftAddChooser(day: day, workplaceID: selectedID, onSaved: reveal)
        case .editor(let route):
            ShiftEditorView(route: route, onSaved: { reveal([$0]) })
        case .patterns:
            PatternListView()
                .presentationBackground(Theme.paper)
        case .partEditor:
            ShiftPartEditor(presetWorkplaceID: selectedID)
                .presentationBackground(Theme.paper)
        case .partEdit(let id):
            ShiftPartEditor(partID: id)
                .presentationBackground(Theme.paper)
        case .partList:
            ShiftPartList()
                .presentationBackground(Theme.paper)
        case .request(let route):
            RequestEditorView(route: route)
                .presentationBackground(Theme.paper)
        case .help:
            HelpSheet(title: "カレンダーの見方", paragraphs: HelpCopy.calendar)
        }
    }

    // MARK: Data

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
        changeMonth(to: next)
    }

    private func changeMonth(to next: Date) {
        let apply = {
            month = next
            selectedDay = ShiftDatePolicy.selectedDayAfterMonthChange(selected: selectedDay, visibleMonth: next)
        }
        if reduceMotion {
            apply()
        } else {
            withAnimation(Motion.settle, apply)
        }
    }

    private func monthButton(_ systemName: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.sunken, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
