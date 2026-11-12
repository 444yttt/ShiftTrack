import SwiftData
import SwiftUI

/// ホーム. Landscape header with the dot-matrix clock, the week, the viewed
/// day's shifts with live earnings, quick actions for the current workplace,
/// the day's to-dos and this month at a glance.
struct TodayScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]
    @Query private var settingsRows: [AppSettings]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var sheet: TodaySheet?
    @State private var pendingPlace: ShiftPartPlace.Pending?
    @State private var placeNote = ""
    @State private var lastPlaced: [WorkShift] = []
    /// Bumped when the app becomes active so the clock never shows a stale minute.
    @State private var resumedAt = Date.distantPast
    /// True while a shift is running; the timeline then ticks every second.
    @State private var live = false
    @State private var showHelp = false

    private enum TodaySheet: Identifiable {
        case editor(EditorRoute)
        case wizard
        case part
        case partEdit(UUID)
        case partList
        case unconfirmed
        case periods
        case todos(UUID)
        case message(UUID)
        case workplace(UUID)

        var id: String {
            switch self {
            case .editor(let route): "editor-\(route.id)"
            case .wizard: "wizard"
            case .part: "part"
            case .partEdit(let id): "part-\(id.uuidString)"
            case .partList: "part-list"
            case .unconfirmed: "unconfirmed"
            case .periods: "periods"
            case .todos(let id): "todos-\(id.uuidString)"
            case .message(let id): "message-\(id.uuidString)"
            case .workplace(let id): "workplace-\(id.uuidString)"
            }
        }
    }

    private var settings: AppSettings? { settingsRows.first }
    private var weekStartsOnMonday: Bool { settings?.weekStartsOnMonday ?? false }
    private var includeTransport: Bool { settings?.includeTransport ?? true }

    /// Ticks land on minute boundaries (shift starts are whole minutes), and every
    /// second while a shift runs so the earnings count up.
    private var minuteStart: Date {
        Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
    }

    var body: some View {
        TimelineView(.periodic(from: minuteStart, by: live ? 1 : 60)) { context in
            let now = max(context.date, resumedAt)
            let running = EarningsSoFar.current(in: shifts, now: now) != nil
            content(now: now)
                .onChange(of: running, initial: true) { _, value in
                    if live != value { live = value }
                }
        }
        .background(Theme.paper)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resumedAt = .now
            }
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet(title: "ホームの見方", paragraphs: HelpCopy.home)
        }
        .sheet(item: $sheet) { route in
            sheetContent(route)
        }
    }

    // MARK: Layout

    private func content(now: Date) -> some View {
        let rows = HomeFocus.shifts(on: day, from: shifts, now: now)
        let place = HomeFocus.workplace(rows: rows, fallback: workplaces, now: now)
        return ScreenScroll(spacing: Space.m) {
            topBar(place: place)
            LandscapeHeader(now: now)
            weekSection
            daySection(rows: rows, now: now)
            if let place {
                quickActions(place)
            }
            todoSection(rows: rows)
            if !workplaces.isEmpty {
                patternSection
            }
            monthSection(now: now)
        }
    }

    private func topBar(place: Workplace?) -> some View {
        HStack(spacing: Space.xs) {
            Text("しふとらっく")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.xs)
            HelpButton { showHelp = true }
            IconButton(systemImage: "plus", label: "シフトを追加", prominent: true, identifier: "today.add") {
                sheet = .editor(EditorRoute(shiftID: nil, date: day, workplaceID: place?.uuid ?? workplaces.first?.uuid))
            }
        }
        .padding(.top, Space.xs)
    }

    // MARK: Week

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xxs) {
                Text(weekTitle)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.xxs)
                if !Calendar.current.isDateInToday(day) {
                    TextLinkButton(title: "今日に戻る", identifier: "today.back") {
                        setDay(Calendar.current.startOfDay(for: .now))
                    }
                }
                weekButton("chevron.left", label: "前の週", identifier: "today.week.previous") { moveWeek(-1) }
                weekButton("chevron.right", label: "次の週", identifier: "today.week.next") { moveWeek(1) }
            }
            weekStrip
                .highPriorityGesture(weekSwipe)
        }
    }

    private var weekTitle: String {
        let days = weekDays
        guard let first = days.first, let last = days.last else { return "今週" }
        let calendar = Calendar.current
        let firstText = "\(calendar.component(.month, from: first))月\(calendar.component(.day, from: first))日"
        let lastText = calendar.component(.month, from: first) == calendar.component(.month, from: last)
            ? "\(calendar.component(.day, from: last))日"
            : "\(calendar.component(.month, from: last))月\(calendar.component(.day, from: last))日"
        return "\(firstText)〜\(lastText)"
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { date in
                dayButton(date)
            }
        }
        .animation(Motion.allowed(Motion.chip, reduce: reduceMotion), value: day)
        .sensoryFeedback(.selection, trigger: day)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("週の日付。左右にスワイプすると前後の週に移ります。")
        .accessibilityIdentifier("today.week")
    }

    private func dayButton(_ date: Date) -> some View {
        let calendar = Calendar.current
        let selected = calendar.isDate(date, inSameDayAs: day)
        let isToday = calendar.isDateInToday(date)
        let dayShifts = shifts.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let dotColor = dayShifts.first?.workplace?.color
        return Button {
            setDay(date)
        } label: {
            VStack(spacing: 2) {
                Text(weekdayMark(date))
                    .font(AppFont.helper)
                    .foregroundStyle(selected ? Color.white : Theme.ink2)
                Text("\(calendar.component(.day, from: date))")
                    .font(.body.weight(.bold).monospacedDigit())
                    .foregroundStyle(selected ? Color.white : Theme.ink)
                Circle()
                    .fill(dotColor ?? Color.clear)
                    .overlay {
                        if dotColor != nil {
                            Circle().stroke(selected ? Color.white : Theme.ink.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .frame(width: 7, height: 7)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                selected ? Theme.ink : (isToday ? Theme.signal : Theme.surface),
                in: RoundedRectangle(cornerRadius: Radius.control + 4, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Formatters.longDay(date) + (isToday ? "、今日" : "") + (dayShifts.isEmpty ? "" : "、シフト\(dayShifts.count)件"))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Day

    private func daySection(rows: [WorkShift], now: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: isToday ? "今日のシフト" : "\(Formatters.longDay(day))のシフト")
            if workplaces.isEmpty {
                EmptyState(
                    systemImage: "building.2",
                    message: "まず勤務先を登録しましょう。時給を入れておくと、勤務中の稼ぎがここで増えていきます。",
                    actionTitle: "勤務先を追加",
                    actionIdentifier: "today.workplace.add"
                ) {
                    sheet = .wizard
                }
            } else if rows.isEmpty {
                EmptyState(
                    systemImage: "calendar.badge.plus",
                    message: "この日のシフトはありません",
                    actionTitle: "＋シフトを追加",
                    actionIdentifier: "＋シフトを追加"
                ) {
                    sheet = .editor(EditorRoute(shiftID: nil, date: day, workplaceID: workplaces.first?.uuid))
                }
            } else {
                ForEach(rows) { shift in
                    ShiftNowCard(
                        shift: shift,
                        now: now,
                        includeTransport: includeTransport,
                        onEdit: {
                            sheet = .editor(EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid))
                        },
                        onConfirm: { sheet = .unconfirmed }
                    )
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
                }
                SecondaryButton(title: "＋シフトを追加", identifier: "＋シフトを追加") {
                    sheet = .editor(EditorRoute(shiftID: nil, date: day, workplaceID: rows.first?.workplace?.uuid ?? workplaces.first?.uuid))
                }
            }
        }
        .animation(Motion.allowed(Motion.settle, reduce: reduceMotion), value: day)
    }

    // MARK: Quick actions

    private func quickActions(_ place: Workplace) -> some View {
        let mapReason = WorkplaceContact.mapReason(for: place)
        let phoneReason = WorkplaceContact.phoneReason(for: place)
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "\(place.name) の連絡先", detail: "地図を開く・電話をかける・遅れる連絡を送る")
            HStack(alignment: .top, spacing: Space.xs) {
                QuickActionTile(title: "地図", systemImage: "map.fill", disabledReason: mapReason, identifier: "today.action.map") {
                    if let url = WorkplaceContact.mapURL(for: place) { openURL(url) }
                }
                QuickActionTile(title: "電話", systemImage: "phone.fill", disabledReason: phoneReason, identifier: "today.action.phone") {
                    if let url = WorkplaceContact.telURL(place.phone) { openURL(url) }
                }
                QuickActionTile(title: "メッセージ", systemImage: "message.fill", disabledReason: phoneReason, identifier: "today.action.message") {
                    sheet = .message(place.uuid)
                }
            }
            if mapReason != nil || phoneReason != nil {
                TextLinkButton(title: "住所や電話番号を登録する", systemImage: "square.and.pencil", identifier: "today.action.edit") {
                    sheet = .workplace(place.uuid)
                }
            }
        }
    }

    // MARK: To-dos

    private struct TodoRow: Identifiable {
        var id: UUID { item.id }
        var shiftID: UUID
        var place: String
        var item: ShiftTodoCodec.Item
    }

    private func todoSection(rows: [WorkShift]) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        let items = rows.flatMap { shift in
            shift.todos.map { TodoRow(shiftID: shift.uuid, place: shift.workplace?.name ?? "", item: $0) }
        }
        let doneCount = items.filter(\.item.done).count
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(
                title: isToday ? "今日のやること" : "この日のやること",
                detail: items.isEmpty ? nil : "\(items.count)件中 \(doneCount)件 完了"
            )
            Card(spacing: 0) {
                if rows.isEmpty {
                    InfoNote(text: "シフトがある日に、やることを入れられます。")
                        .padding(.vertical, Space.xs)
                } else {
                    if items.isEmpty {
                        Text("やることはまだありません")
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink2)
                            .frame(minHeight: 44)
                    }
                    ForEach(items) { row in
                        todoButton(row, showsPlace: rows.count > 1)
                        RowDivider()
                    }
                    addTodoButton(rows: rows)
                }
            }
        }
    }

    private func todoButton(_ row: TodoRow, showsPlace: Bool) -> some View {
        Button {
            toggle(row)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: row.item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.item.done ? Theme.signalInk : Theme.ink2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.item.title)
                        .font(AppFont.body)
                        .foregroundStyle(row.item.done ? Theme.ink2 : Theme.ink)
                        .strikethrough(row.item.done, color: Theme.ink2)
                    if showsPlace, !row.place.isEmpty {
                        Text(row.place)
                            .font(AppFont.helper)
                            .foregroundStyle(Theme.ink2)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(row.item.title)
        .accessibilityValue(row.item.done ? "完了" : "未完了")
        .accessibilityHint("押すと完了と未完了を切り替えます")
        .accessibilityAddTraits(row.item.done ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("today.todo.\(row.item.title)")
    }

    @ViewBuilder private func addTodoButton(rows: [WorkShift]) -> some View {
        if rows.count == 1, let only = rows.first {
            TextLinkButton(title: "やることを追加・編集", systemImage: "plus", identifier: "today.todo.add") {
                sheet = .todos(only.uuid)
            }
        } else {
            Menu {
                ForEach(rows) { shift in
                    Button("\(shift.workplace?.name ?? "勤務先") \(Formatters.clock(shift.startMinutes))–\(Formatters.clock(shift.endMinutes))") {
                        sheet = .todos(shift.uuid)
                    }
                }
            } label: {
                Label("やることを追加・編集", systemImage: "plus")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.signalInk)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("today.todo.add")
        }
    }

    private func toggle(_ row: TodoRow) {
        guard let shift = shifts.first(where: { $0.uuid == row.shiftID }) else { return }
        var items = shift.todos
        guard let index = items.firstIndex(where: { $0.id == row.item.id }) else { return }
        items[index].done.toggle()
        shift.todos = items
        try? modelContext.save()
    }

    // MARK: Patterns

    private var patternSection: some View {
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
            onClosePending: { pendingPlace = nil },
            onEdit: { sheet = .partEdit($0.uuid) },
            onManage: { sheet = .partList },
            onUndo: lastPlaced.isEmpty ? nil : { undoPlace() }
        )
    }

    private func place(_ part: ShiftPart) {
        let result = ShiftPartCommit.apply(
            part: part,
            days: [day],
            shifts: shifts,
            workplaces: workplaces,
            context: modelContext
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
        }
    }

    private func undoPlace() {
        ShiftPartCommit.undo(lastPlaced, context: modelContext)
        lastPlaced = []
        placeNote = "取り消しました。"
    }

    // MARK: Month

    private func monthSection(now: Date) -> some View {
        let calendar = Calendar.current
        let interval = IncomeEngine.monthInterval(now, calendar: calendar)
        let monthShifts = shifts.filter { shift in
            guard let interval else { return false }
            let start = calendar.startOfDay(for: shift.date)
            return start >= interval.0 && start < interval.1
        }
        let yen = monthShifts.reduce(0) { $0 + $1.estimatedYen(includeTransport: includeTransport) }
        let minutes = monthShifts.reduce(0) { $0 + $1.workedMinutes }
        let days = Set(monthShifts.map { calendar.startOfDay(for: $0.date) }).count
        let unconfirmed = shifts.filter(\.needsAttendanceCheck).count
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "\(calendar.component(.month, from: now))月のまとめ", detail: "働く日で数えています。給料日ごとの金額は「支給の見込み」で見られます。")
            Card {
                Text("勤務の見込み（\(includeTransport ? "交通費込み" : "交通費なし")）")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
                DotoText("¥" + Formatters.yenDigits(yen), size: 34, spoken: "勤務の見込み \(yen)円")
                    .accessibilityIdentifier("today.month.total")
                HStack(spacing: Space.xs) {
                    StatTile(title: "勤務日", value: "\(days)日")
                    StatTile(title: "勤務時間", value: Formatters.hours(minutes))
                }
                RowDivider()
                Button {
                    sheet = .periods
                } label: {
                    NavRow(systemImage: "calendar.badge.clock", title: "支給の見込み", subtitle: "勤務先ごと、給料日ごとの金額")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("today.periods")
                if unconfirmed > 0 {
                    RowDivider()
                    Button {
                        sheet = .unconfirmed
                    } label: {
                        NavRow(systemImage: "checkmark.seal", title: "確認していない勤務", subtitle: "終わった勤務の時間と休憩を確かめます", value: "\(unconfirmed)件")
                    }
                    .buttonStyle(RowButtonStyle())
                    .accessibilityIdentifier("today.unconfirmed")
                }
            }
        }
    }

    // MARK: Sheets

    @ViewBuilder private func sheetContent(_ route: TodaySheet) -> some View {
        switch route {
        case .editor(let editor):
            ShiftEditorView(route: editor)
        case .wizard:
            WorkplaceWizard()
        case .part:
            ShiftPartEditor()
                .presentationBackground(Theme.paper)
        case .partEdit(let id):
            ShiftPartEditor(partID: id)
                .presentationBackground(Theme.paper)
        case .partList:
            ShiftPartList()
                .presentationBackground(Theme.paper)
        case .unconfirmed:
            UnconfirmedList(shifts: shifts.filter(\.needsAttendanceCheck)) { shift in
                sheet = .editor(EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid))
            }
        case .periods:
            PayPeriodsView()
        case .todos(let id):
            TodoEditor(shiftID: id)
                .presentationBackground(Theme.paper)
        case .message(let id):
            if let place = workplaces.first(where: { $0.uuid == id }) {
                MessageComposerSheet(workplace: place)
            }
        case .workplace(let id):
            WorkplaceEditorView(existingID: id)
        }
    }

    // MARK: Week helpers

    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 48 else { return }
                moveWeek(value.translation.width < 0 ? 1 : -1)
            }
    }

    private func setDay(_ date: Date) {
        if reduceMotion {
            day = date
        } else {
            withAnimation(Motion.chip) { day = date }
        }
    }

    private func moveWeek(_ weeks: Int) {
        setDay(WeekPage.day(byAddingWeeks: weeks, to: day))
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

    private func weekButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// One shift on the home screen. While it runs, the earnings count up every
/// second from the hourly wage (see `EarningsSoFar`).
struct ShiftNowCard: View {
    var shift: WorkShift
    var now: Date
    var includeTransport: Bool
    var onEdit: () -> Void
    var onConfirm: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let progress = EarningsSoFar.progress(for: shift, now: now)
        let name = shift.workplace?.name ?? "勤務先"
        Card(spacing: Space.s) {
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(shift.workplace?.color ?? Theme.signal)
                    .overlay(Circle().stroke(Theme.ink.opacity(0.25), lineWidth: 1))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(name)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: Space.xs)
                if let progress {
                    StatusChip(text: status(progress), emphasized: progress.isWorking)
                }
            }
            DotoText(
                "\(Formatters.clock(shift.startMinutes))–\(Formatters.clock(shift.endMinutes))",
                size: 30,
                spoken: "\(Formatters.spokenClock(shift.startMinutes))から\(Formatters.spokenClock(shift.endMinutes))まで"
            )
            .accessibilityIdentifier("today.shift.time")
            Text(detailLine)
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
            if let progress {
                earnings(progress)
            } else {
                InfoNote(text: "開始と終了が同じため、見込みを出していません。", tone: .warning)
            }
            HStack(spacing: Space.xs) {
                SecondaryButton(title: "編集", systemImage: "pencil", fillWidth: false, identifier: "today.shift.edit") {
                    onEdit()
                }
                if shift.needsAttendanceCheck {
                    SecondaryButton(title: "時間を確認", systemImage: "checkmark.seal", fillWidth: false, identifier: "today.shift.confirm") {
                        onConfirm()
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func earnings(_ progress: EarningsSoFar.Progress) -> some View {
        switch progress.phase {
        case .working(_, let remaining):
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("いままでの稼ぎ")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                DotoText(
                    "¥" + Formatters.yenDigits(progress.earnedYen),
                    size: 46,
                    spoken: "いままでの稼ぎ \(progress.earnedYen)円",
                    maxScale: 1.3
                )
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(progress.earnedYen)))
                .animation(Motion.allowed(Motion.press, reduce: reduceMotion), value: progress.earnedYen)
                .accessibilityIdentifier("today.earned")
                ProgressBar(value: progress.fraction, label: "勤務の進み具合")
                HStack(alignment: .firstTextBaseline) {
                    Text("時給分の見込み \(Formatters.yen(progress.wageTotalYen))")
                    Spacer(minLength: Space.xs)
                    Text("終わりまで あと\(Formatters.remaining(remaining))")
                }
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
                if let extras = extrasLine {
                    InfoNote(text: extras)
                }
            }
        case .upcoming(let startsIn):
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("この勤務の見込み")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                DotoText("¥" + Formatters.yenDigits(total), size: 32, spoken: "この勤務の見込み \(total)円")
                    .accessibilityIdentifier("today.estimate")
                Text("はじまりまで あと\(Formatters.remaining(startsIn))")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
            }
        case .finished:
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("この勤務の稼ぎ")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                DotoText("¥" + Formatters.yenDigits(total), size: 32, spoken: "この勤務の稼ぎ \(total)円")
                    .accessibilityIdentifier("today.estimate")
                Text(shift.needsAttendanceCheck ? "終わりました。時間と休憩が予定どおりか確認できます。" : "終わりました。確認済みです。")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    private var total: Int {
        shift.estimatedYen(includeTransport: includeTransport)
    }

    private var detailLine: String {
        var parts = [Formatters.hours(shift.workedMinutes)]
        if shift.breakMinutes > 0 {
            parts.append("休憩\(shift.breakMinutes)分")
        }
        if let interval = EarningsSoFar.interval(of: shift),
           !Calendar.current.isDate(interval.start, inSameDayAs: interval.end) {
            parts.append("翌日\(Formatters.clock(shift.endMinutes))まで")
        }
        return parts.joined(separator: "・")
    }

    /// Transport and 天引・手当 are not earned by the minute; say where they are.
    private var extrasLine: String? {
        guard let workplace = shift.workplace else { return nil }
        var items: [String] = []
        if includeTransport, workplace.transportAllowance > 0 {
            items.append("交通費 \(Formatters.yen(workplace.transportAllowance))")
        }
        if shift.adjustmentYen != 0 {
            items.append("天引・手当 \(shift.adjustmentYen > 0 ? "+" : "−")\(Formatters.yen(abs(shift.adjustmentYen)))")
        }
        guard !items.isEmpty else { return nil }
        return items.joined(separator: "、") + " はこの数字に入れず、勤務の見込み \(Formatters.yen(total)) に入っています。"
    }

    private func status(_ progress: EarningsSoFar.Progress) -> String {
        switch progress.phase {
        case .working: "勤務中"
        case .upcoming(let startsIn): startsIn < 3_600 ? "まもなく" : "これから"
        case .finished: shift.needsAttendanceCheck ? "未確認" : "終了"
        }
    }
}

/// Finished shifts whose times have not been confirmed yet.
struct UnconfirmedList: View {
    var shifts: [WorkShift]
    var onEdit: (WorkShift) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.s) {
                InfoNote(text: "終わった勤務を選ぶと、実際の時間と休憩を確かめて確定できます。確定すると、この一覧から消えます。")
                    .padding(.top, Space.xs)
                if shifts.isEmpty {
                    EmptyState(systemImage: "checkmark.seal", message: "確認していない勤務はありません")
                } else {
                    Card(spacing: 0) {
                        ForEach(shifts) { shift in
                            NavigationLink {
                                ShiftCheckView(shift: shift) { onEdit(shift) }
                            } label: {
                                NavRow(
                                    title: shift.workplace?.name ?? "勤務先",
                                    subtitle: "\(Formatters.longDay(shift.date)) \(Formatters.clock(shift.startMinutes))〜\(Formatters.clock(shift.endMinutes))"
                                )
                            }
                            .buttonStyle(RowButtonStyle())
                            RowDivider()
                        }
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle("確認していない勤務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
        }
    }
}

enum WeekPage {
    /// Moves the day being viewed by whole weeks. Never writes a stored shift date.
    static func day(byAddingWeeks weeks: Int, to day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return InOutRecovered.addingWeeks(weeks, to: start, calendar: calendar) ?? start
    }
}
