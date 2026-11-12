import SwiftData
import SwiftUI

struct EditorRoute: Identifiable {
    var id: String { "\(shiftID?.uuidString ?? "new")-\(date.timeIntervalSinceReferenceDate)" }
    var shiftID: UUID?
    var date: Date
    var workplaceID: UUID?
}

struct ShiftAddChooser: View {
    var day: Date
    var workplaceID: UUID?
    var onSaved: ([Date]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \WorkShift.date, order: .reverse) private var shifts: [WorkShift]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]
    @Query private var settingsRows: [AppSettings]
    @State private var editor: EditorRoute?
    @State private var partNote = ""
    @State private var tableText = ""
    @State private var tableError = ""
    @State private var modelReading: TypedShiftEntry.Reading?
    @State private var modelNote = ""
    @State private var modelBusy = false
    @FocusState private var tableFocused: Bool

    private var history: [WorkShift] {
        var seen = Set<String>()
        var items: [WorkShift] = []
        for shift in shifts {
            guard let workplace = shift.workplace else { continue }
            let key = "\(workplace.uuid.uuidString)|\(shift.startMinutes)|\(shift.endMinutes)|\(shift.breakMinutes)"
            guard seen.insert(key).inserted else { continue }
            items.append(shift)
            if items.count == 10 { break }
        }
        return items
    }

    private var assumedWorkplace: Workplace? {
        if let workplaceID, let match = workplaces.first(where: { $0.uuid == workplaceID }) {
            return match
        }
        return workplaces.count == 1 ? workplaces.first : nil
    }

    private var typedReading: TypedShiftEntry.Reading? {
        TypedShiftEntry.read(
            text: tableText,
            now: Date(),
            calendar: ShiftOverlap.tokyo,
            knownNames: workplaces.map(\.name),
            fallbackDate: day,
            defaultWorkplace: assumedWorkplace?.name ?? ""
        )
    }

    private var drafts: [ShiftTextParser.Draft] {
        if let typedReading, typedReading.canSave, let draft = typedReading.draft() {
            return [draft]
        }
        if typedReading?.repeatsWeekly == true {
            return []
        }
        if let modelReading, modelReading.canSave, let draft = modelReading.draft() {
            return [draft]
        }
        return ShiftTextParser.parse(
            text: tableText,
            knownNames: workplaces.map(\.name),
            fallbackDate: day,
            defaultWorkplace: assumedWorkplace?.name ?? ""
        )
    }

    private func askModel() async {
        let source = tableText
        modelBusy = true
        defer { modelBusy = false }
        let reading = await ShiftEntryGate.resolve(
            text: source,
            now: Date(),
            calendar: ShiftOverlap.tokyo,
            knownNames: workplaces.map(\.name),
            fallbackDate: day,
            defaultWorkplace: assumedWorkplace?.name ?? "",
            filler: LiveSentenceFiller(
                now: Date(),
                calendar: ShiftOverlap.tokyo,
                knownNames: workplaces.map(\.name),
                fallbackDate: day,
                defaultWorkplace: assumedWorkplace?.name ?? ""
            )
        )
        guard source == tableText else { return }
        if reading?.canSave == true, typedReading?.canSave != true {
            modelReading = reading
            modelNote = "端末内で整理した候補です。追加する前に内容を確認できます。"
        } else {
            modelReading = nil
            modelNote = "規則でも端末内のモデルでも、追加できる形にはなりませんでした。"
        }
    }

    private var tableHint: String {
        var lines = ["日付を書かない行は\(Formatters.longDay(day))になります。"]
        if let name = assumedWorkplace?.name {
            lines.append("勤務先を書かない行は「\(name)」になります。")
        } else {
            lines.append("勤務先の名前を行に書いてください。")
        }
        lines.append("追加すると、この画面を閉じてカレンダーに出します。")
        return lines.joined(separator: "")
    }

    private var tableProblem: String {
        if !tableError.isEmpty { return tableError }
        let trimmed = tableText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, drafts.isEmpty else { return "" }
        if assumedWorkplace == nil {
            return "勤務先の名前と、開始・終了時刻を書いてください。例: 11/8 カフェA 10:00-15:00"
        }
        return "開始・終了時刻が読み取れません。例: 10:00-15:00"
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                Text("\(Formatters.longDay(day))に入れます")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, Space.xs)
                manualSection
                partsSection
                historySection
                tableSection
            }
            .background(Theme.paper)
            .navigationTitle("シフトを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        tableFocused = false
                        Keyboard.dismiss()
                    }
                    .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .sheet(item: $editor) { route in
                ShiftEditorView(route: route) { date in
                    onSaved([date])
                    dismiss()
                }
            }
        }
    }

    private var tableSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "文字で入れる", detail: "シフト表の行をそのまま書くか貼り付けます。1行に1件です。")
            Card {
                Text("シフト表の文字")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $tableText)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(8)
                        .focused($tableFocused)
                        .accessibilityLabel("シフト表の文字")
                        .accessibilityIdentifier("chooser.table")
                    if tableText.isEmpty {
                        Text(tablePlaceholder)
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink2)
                            .padding(14)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                .onChange(of: tableText) { _, _ in
                    tableError = ""
                    modelReading = nil
                    modelNote = ""
                }
                InfoNote(text: tableHint)
                if typedReading?.canSave != true, typedReading?.repeatsWeekly != true,
                   !tableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SecondaryButton(
                        title: modelBusy ? "整理しています…" : "読めない文を端末内で整理する",
                        systemImage: "sparkles",
                        identifier: "chooser.model"
                    ) {
                        Task { await askModel() }
                    }
                    .disabled(modelBusy)
                    InfoNote(text: "決まった形で読めた行はそのまま使います。整理した候補は、追加する前にここで確かめられます。")
                    if !modelNote.isEmpty {
                        InfoNote(text: modelNote, tone: .warning)
                    }
                }
                if let typedReading, typedReading.repeatsWeekly {
                    InfoNote(text: TypedShiftEntry.weeklyLine(typedReading), tone: .warning)
                } else if let typedReading, typedReading.canSave, typedReading.alternativeNoted {
                    InfoNote(text: TypedShiftEntry.alternativeLine(), tone: .warning)
                }
                if !tableProblem.isEmpty, typedReading?.repeatsWeekly != true {
                    InfoNote(text: tableProblem, tone: .error)
                }
                if !drafts.isEmpty {
                    Text("追加される候補")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink)
                    VStack(spacing: Space.xs) {
                        ForEach(Array(drafts.prefix(6))) { draft in
                            draftRow(draft)
                        }
                        if drafts.count > 6 {
                            Text("ほか \(drafts.count - 6) 件")
                                .font(AppFont.helper)
                                .foregroundStyle(Theme.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                PrimaryButton(title: drafts.isEmpty ? "読み取った行を追加" : "\(drafts.count)件を追加", identifier: "chooser.table.add") {
                    commitTable()
                }
                .disabled(drafts.isEmpty)
            }
        }
    }

    private var partsSection: some View {
        let visible = parts.filter { !$0.hidden }
        return VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "パターンで追加", detail: visible.isEmpty ? "カレンダーで「パターンを作る」と、よく入る時間をここから1回で追加できます。" : "押すと、その時間・休憩・やることで追加します。")
            if !visible.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        ForEach(visible) { part in
                            Button {
                                placePart(part)
                            } label: {
                                HStack(spacing: Space.xs) {
                                    Circle()
                                        .fill(Color(hexString: part.colorHex))
                                        .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                                        .frame(width: 12, height: 12)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(part.name)
                                            .font(AppFont.label)
                                            .foregroundStyle(Theme.ink)
                                        Text("\(Formatters.clock(part.startMinute))–\(Formatters.clock(part.endMinute))")
                                            .font(AppFont.helper.monospacedDigit())
                                            .foregroundStyle(Theme.ink2)
                                    }
                                }
                                .padding(.horizontal, Space.s)
                                .frame(minHeight: 56)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("chooser.pattern.\(part.name)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if !partNote.isEmpty {
                InfoNote(text: partNote, tone: .warning)
            }
        }
    }

    private func placePart(_ part: ShiftPart) {
        let result = ShiftPartCommit.apply(part: part, days: [day], shifts: shifts, workplaces: workplaces, context: context)
        if let failure = result.failure {
            partNote = failure
            return
        }
        switch result.outcome {
        case .placed(let drafts):
            if drafts.isEmpty {
                partNote = "この日には、同じパターンがすでにあります。"
            } else {
                onSaved([day])
                dismiss()
            }
        case .pending:
            partNote = "この日には別のシフトがあります。重ねるときは「1件ずつ入力」から追加してください。"
        case .missingWorkplace:
            partNote = "このパターンの勤務先が見つかりません。"
        }
    }

    private var tablePlaceholder: String {
        if let name = assumedWorkplace?.name {
            return "10:00-15:00\n18:00-23:00 休憩60分\n11/9 \(name) 9:00-13:00"
        }
        return "11/8 カフェA 10:00-15:00\n11/9 18:00-23:00 休憩60分"
    }

    private var manualSection: some View {
        Card(spacing: 0) {
            Button {
                editor = EditorRoute(shiftID: nil, date: day, workplaceID: workplaceID ?? assumedWorkplace?.uuid)
            } label: {
                NavRow(systemImage: "square.and.pencil", title: "1件ずつ入力", subtitle: "勤務先と時刻を選んで入れます")
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityIdentifier("chooser.manual")
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "前に入れた時間から", detail: history.isEmpty ? "シフトを入れると、次からここで同じ時間を選べます。" : "押すと、同じ勤務先・時間・休憩でこの日に追加します。")
            if !history.isEmpty {
                Card(spacing: 0) {
                    ForEach(history) { shift in
                        Button {
                            add(shift)
                        } label: {
                            HStack(spacing: Space.s) {
                                Circle()
                                    .fill(shift.workplace?.color ?? Theme.signal)
                                    .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shift.workplace?.name ?? "勤務先")
                                        .font(AppFont.rowTitle)
                                        .foregroundStyle(Theme.ink)
                                    Text("\(Formatters.clock(shift.startMinutes))–\(Formatters.clock(shift.endMinutes))・休憩\(shift.breakMinutes)分")
                                        .font(AppFont.helper.monospacedDigit())
                                        .foregroundStyle(Theme.ink2)
                                }
                                Spacer(minLength: Space.xs)
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundStyle(Theme.signalInk)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                        .accessibilityHint("この日に追加します")
                        RowDivider()
                    }
                }
            }
        }
    }

    private func draftRow(_ draft: ShiftTextParser.Draft) -> some View {
        HStack(spacing: Space.xs) {
            Circle()
                .fill(color(for: draft.workplaceName))
                .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.workplaceName)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink)
                Text(draftCaption(draft))
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 10)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func draftCaption(_ draft: ShiftTextParser.Draft) -> String {
        let when = draft.date().map { Formatters.monthDayWeekday($0) } ?? "\(draft.month)/\(draft.day)"
        let match = workplaces.first { normalize($0.name) == normalize(draft.workplaceName) }
        if match?.payIsDaily == true {
            return "\(when)  \(Formatters.clock(draft.startMinutes))–\(Formatters.clock(draft.endMinutes))  日給"
        }
        let decision = BreakRules.textDecision(
            breakIsExplicit: draft.breakIsExplicit,
            explicitMinutes: draft.breakMinutes,
            payIsDaily: false,
            customBreaks: match?.customBreaks ?? false,
            rules: match?.breakRules ?? [],
            start: draft.startMinutes,
            end: draft.endMinutes
        )
        let mark = decision.followsRules ? "（規則）" : "（入力）"
        return "\(when)  \(Formatters.clock(draft.startMinutes))–\(Formatters.clock(draft.endMinutes))  休憩\(decision.minutes)分\(mark)"
    }

    private func color(for name: String) -> Color {
        let key = normalize(name)
        if let match = workplaces.first(where: { normalize($0.name) == key }) {
            return match.color
        }
        return Theme.lime
    }

    private func add(_ source: WorkShift) {
        guard let workplace = source.workplace else { return }
        let preservedDate = source.date
        let shift = WorkShift(
            date: day,
            startMinutes: source.startMinutes,
            endMinutes: source.endMinutes,
            breakMinutes: source.breakMinutes,
            workplace: workplace
        )
        context.insert(shift)
        if !Calendar.current.isDate(source.date, inSameDayAs: preservedDate) {
            source.date = preservedDate
        }
        do {
            try context.save()
        } catch {
            tableError = "保存できませんでした。もう一度試してください。"
            return
        }
        onSaved([day])
        dismiss()
    }

    private func commitTable() {
        let parsed = drafts
        guard !parsed.isEmpty else { return }
        tableFocused = false
        let settings = settingsRows.first
        let wage = settings?.defaultHourlyWage ?? 1200
        let transport = settings?.defaultTransportAllowance ?? 500
        var created: [String: Workplace] = [:]
        var dates: [Date] = []
        for draft in parsed {
            let date = typedReading?.canSave == true
                ? draft.date(calendar: ShiftOverlap.tokyo)
                : draft.date()
            guard let date else { continue }
            guard let workplace = workplace(
                named: draft.workplaceName,
                wage: wage,
                transport: transport,
                created: &created
            ) else { continue }
            let decision = BreakRules.textDecision(
                breakIsExplicit: draft.breakIsExplicit,
                explicitMinutes: draft.breakMinutes,
                payIsDaily: workplace.payIsDaily,
                customBreaks: workplace.customBreaks,
                rules: workplace.breakRules,
                start: draft.startMinutes,
                end: draft.endMinutes
            )
            guard PayMath.workedMinutes(
                start: draft.startMinutes,
                end: draft.endMinutes,
                breakMinutes: decision.minutes
            ) > 0 else { continue }
            dates.append(date)
            let duplicate = shifts.contains { shift in
                shift.workplace?.uuid == workplace.uuid
                    && (typedReading?.canSave == true ? ShiftOverlap.tokyo : Calendar.current).isDate(shift.date, inSameDayAs: date)
                    && shift.startMinutes == draft.startMinutes
                    && shift.endMinutes == draft.endMinutes
            }
            if duplicate { continue }
            context.insert(WorkShift(
                date: date,
                startMinutes: draft.startMinutes,
                endMinutes: draft.endMinutes,
                breakMinutes: decision.minutes,
                breakFollowsRules: decision.followsRules,
                workplace: workplace
            ))
        }
        guard !dates.isEmpty else {
            tableError = "勤務時間が0分になる行だけです。開始と終了を変えてください。"
            return
        }
        do {
            try context.save()
        } catch {
            tableError = "保存できませんでした。もう一度試してください。"
            return
        }
        onSaved(dates)
        dismiss()
    }

    private func workplace(
        named name: String,
        wage: Int,
        transport: Int,
        created: inout [String: Workplace]
    ) -> Workplace? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        if let existing = created[key] { return existing }
        if let found = workplaces.first(where: { normalize($0.name) == key }) {
            created[key] = found
            return found
        }
        let used = Set(workplaces.map(\.colorHex) + created.values.map(\.colorHex))
        let color = Theme.palette.first { !used.contains($0) } ?? Theme.palette[(workplaces.count + created.count) % Theme.palette.count]
        let workplace = Workplace(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: color,
            hourlyWage: wage,
            transportAllowance: transport,
            notes: "シフト表から追加"
        )
        context.insert(workplace)
        created[key] = workplace
        return workplace
    }

    private func normalize(_ text: String) -> String {
        TextNormalizer.fold(text).replacingOccurrences(of: " ", with: "").lowercased()
    }
}

extension ShiftOverlap {
    static func span(from shift: WorkShift, calendar: Calendar = tokyo) -> Span {
        span(
            id: String(describing: shift.persistentModelID),
            name: shift.workplace?.name ?? "シフト",
            workplace: shift.workplace?.uuid ?? UUID(),
            day: shift.date,
            start: shift.startMinutes,
            end: shift.endMinutes,
            calendar: calendar,
            cancelled: shift.isDeleted
        )
    }
}

struct ShiftEditorView: View {
    var route: EditorRoute
    var onSaved: ((Date) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]
    @Query private var shifts: [WorkShift]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]

    @State private var workplaceID: UUID?
    @State private var date = Date()
    @State private var startMinutes = 10 * 60
    @State private var endMinutes = 15 * 60
    @State private var breakMinutes = 0
    @State private var breakFollowsRules = false
    @State private var notes = ""
    @State private var customText = ""
    @State private var adjustmentText = ""
    @State private var adjustmentNote = ""
    @State private var error = ""
    @State private var confirmDelete = false
    @State private var showWorkplaceCreator = false
    @State private var showDateEditor = false
    @State private var draftDate = Date()
    @State private var userEditedDate = false
    @State private var loaded = false
    @State private var overlap: [ShiftOverlap.Hit] = []
    @State private var overlapSheet = false
    @AppStorage("settings.travelMinutes") private var travelMinutes = 30
    @State private var chosenPart: UUID?
    @State private var copyNote = ""
    @State private var destinationName = ""
    @State private var destinationPlace = ""
    @FocusState private var typing: Bool

    private var existing: WorkShift? { shifts.first { $0.uuid == route.shiftID } }
    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }
    private var selectedWorkplace: Workplace? { workplaces.first { $0.uuid == workplaceID } }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                if workplaces.isEmpty {
                    EmptyState(
                        systemImage: "building.2",
                        message: "シフトを入れる前に、勤務先を1件登録してください。",
                        actionTitle: "勤務先を追加",
                        actionIdentifier: "editor.workplace.add"
                    ) {
                        showWorkplaceCreator = true
                    }
                    .padding(.top, Space.xs)
                } else {
                    if !workplaceParts.isEmpty {
                        SectionHeader(title: "パターンから入れる", detail: "選ぶと、そのパターンの時間と休憩を入れます。")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Space.xs) {
                                ChipButton(title: "なし", selected: chosenPart == nil, identifier: "editor.pattern.none") { chosenPart = nil }
                                ForEach(workplaceParts) { part in
                                    ChipButton(title: part.name, selected: chosenPart == part.uuid, identifier: "editor.pattern.\(part.name)") {
                                        chosenPart = part.uuid
                                        startMinutes = part.startMinute
                                        endMinutes = part.endMinute
                                        applyPartBreak(part)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    SectionHeader(title: "勤務先と日付")
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("勤務先")
                                .font(AppFont.label)
                                .foregroundStyle(Theme.ink)
                            if existing != nil {
                                Text(selectedWorkplace?.name ?? "なし")
                                    .font(AppFont.rowTitle)
                                    .foregroundStyle(Theme.ink)
                                InfoNote(text: "保存したシフトの勤務先は変えられません。別の勤務先にするときは、このシフトを消して入れ直してください。")
                            } else {
                                workplaceChoice
                            }
                        }
                        RowDivider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("日付")
                                .font(AppFont.label)
                                .foregroundStyle(Theme.ink)
                                .accessibilityHidden(true)
                            HStack(spacing: Space.xs) {
                                dayStepButton("chevron.left", label: "前の日", delta: -1)
                                Button {
                                    draftDate = date
                                    showDateEditor = true
                                } label: {
                                    HStack {
                                        Text(Formatters.longDay(date))
                                            .font(AppFont.rowTitle)
                                            .foregroundStyle(Theme.ink)
                                        Spacer(minLength: 0)
                                        Image(systemName: "calendar")
                                            .foregroundStyle(Theme.signalInk)
                                            .accessibilityHidden(true)
                                    }
                                    .padding(.horizontal, Space.s)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("日付")
                                .accessibilityValue(Formatters.longDay(date))
                                .accessibilityHint("押すとカレンダーから選べます")
                                dayStepButton("chevron.right", label: "次の日", delta: 1)
                            }
                        }
                    }

                    SectionHeader(title: "時間", detail: "大きなボタンを押すと時刻を変えられます。日付は変わりません。")
                    Card {
                        HStack(alignment: .top, spacing: Space.xs) {
                            MinutesTimePicker(title: "開始", minutes: $startMinutes)
                            MinutesTimePicker(title: "終了", minutes: $endMinutes)
                        }
                        if !clocksMatch, ShiftDatePolicy.clockMinutes(endMinutes) < ShiftDatePolicy.clockMinutes(startMinutes) {
                            InfoNote(text: "終了が開始より前なので、翌日の\(Formatters.clock(endMinutes))までの勤務として数えます。")
                        }
                        durationChips
                        ForEach(liveOverlap) { hit in
                            InfoNote(text: ShiftOverlap.row(hit), tone: .warning)
                        }
                        if let existing, existing.clockedInAt != nil || existing.clockedOutAt != nil {
                            InfoNote(text: clockStamp(existing))
                            if let payable = punchLine(existing) {
                                InfoNote(text: payable)
                            }
                        }
                    }

                    SectionHeader(title: "休憩")
                    Card {
                        if selectedWorkplace?.payIsDaily == true {
                            InfoNote(text: "日給の勤務先では、休憩で給料は減りません。")
                        } else {
                            ToggleRow(
                                title: "勤務先の決まりで休憩を入れる",
                                helper: breakFollowsRules
                                    ? BreakRules.summary(
                                        customBreaks: selectedWorkplace?.customBreaks ?? false,
                                        rules: selectedWorkplace?.breakRules ?? []
                                    ) + "時刻を変えると、休憩も合わせて変わります。"
                                    : "手で入れた休憩です。時刻を変えても、この休憩は変わりません。",
                                isOn: breakFollowsBinding,
                                identifier: "editor.breakRules"
                            )
                            RowDivider()
                            BreakMinutesControl(minutes: breakEntryBinding, range: 0...600)
                            ValueRow(title: "働く時間", value: Formatters.hours(draftMinutes), emphasized: true)
                        }
                    }

                    SectionHeader(title: "給料の調整", detail: "ふだんは空のままで大丈夫です。")
                    Card {
                        YenField(
                            label: "このシフトの給料（決まっているとき）",
                            text: $customText,
                            prompt: "空なら時給から計算",
                            helper: "入れると、時給や割増の代わりにこの金額を使います。",
                            identifier: "editor.customPay"
                        )
                        YenField(
                            label: "天引・手当",
                            text: $adjustmentText,
                            prompt: "例：-500 または 1000",
                            helper: "マイナスは天引、プラスは手当です。",
                            signed: true,
                            identifier: "editor.adjustment"
                        )
                        LabeledField(label: "天引・手当の内容（任意）", text: $adjustmentNote, prompt: "例：まかない代", identifier: "editor.adjustmentNote")
                    }
                    if let workplace = selectedWorkplace {
                        let amount = PayMath.quote(
                            workplace: workplace,
                            day: date,
                            start: startMinutes,
                            end: endMinutes,
                            breakMinutes: shownBreak,
                            customPay: parsedCustom,
                            adjustment: parsedAdjustment,
                            includeTransport: includeTransport
                        )
                        Card {
                            HStack(alignment: .firstTextBaseline) {
                                Text("このシフトの見込み")
                                    .font(AppFont.body)
                                    .foregroundStyle(Theme.ink)
                                Spacer(minLength: Space.xs)
                                DotoText("¥" + Formatters.yenDigits(amount), size: 26, spoken: "\(amount)円")
                                    .accessibilityIdentifier("editor.estimate")
                            }
                            Text(includeTransport ? "交通費と天引・手当を含みます。" : "天引・手当を含みます。交通費は含みません（設定で変えられます）。")
                                .font(AppFont.helper)
                                .foregroundStyle(Theme.ink2)
                        }
                    }

                    SectionHeader(title: "メモと行き先")
                    Card {
                        LabeledField(label: "メモ（任意）", text: $notes, prompt: "持ち物・連絡など", identifier: "editor.notes", multiline: true)
                        LabeledField(
                            label: "行き先の名前（任意）",
                            text: $destinationName,
                            prompt: "例：本店",
                            helper: "勤務先とは別の場所に行く日に入れます。空のときは勤務先に向かいます。",
                            identifier: "editor.destination"
                        )
                        LabeledField(label: "行き先の住所（任意）", text: $destinationPlace, prompt: "例：架空県南窓町3-4", identifier: "editor.destinationPlace")
                    }

                    if let existing {
                        SectionHeader(title: "このシフトをコピー", detail: "同じ勤務先・時間がすでにある日には足しません。")
                        Card {
                            HStack(spacing: Space.xs) {
                                SecondaryButton(title: "翌日へ", systemImage: "doc.on.doc", identifier: "editor.copy.day") {
                                    copyShift(existing, days: 1)
                                }
                                SecondaryButton(title: "来週の同じ曜日へ", systemImage: "doc.on.doc", identifier: "editor.copy.week") {
                                    copyShift(existing, days: 7)
                                }
                            }
                            if !copyNote.isEmpty {
                                Text(copyNote)
                                    .font(AppFont.label)
                                    .foregroundStyle(Theme.ink)
                                    .accessibilityIdentifier("editor.copy.note")
                            }
                        }
                    }

                    if !shownError.isEmpty {
                        InfoNote(text: shownError, tone: .error)
                    }

                    if existing != nil {
                        DestructiveButton(title: "このシフトを削除", identifier: "editor.delete") {
                            confirmDelete = true
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !workplaces.isEmpty {
                    PrimaryButton(title: existing == nil ? "このシフトを追加" : "変更を保存", identifier: "editor.save") { save() }
                        .disabled(!canSave)
                        .padding(.horizontal, Space.gutter)
                        .padding(.vertical, Space.xs)
                        .background(Theme.paper)
                }
            }
            .background(Theme.paper)
            .navigationTitle(existing == nil ? "シフトを追加" : "シフトの詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .foregroundStyle(Theme.signalInk)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        typing = false
                        Keyboard.dismiss()
                    }
                    .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onAppear(perform: load)
            .onChange(of: workplaces.map(\.uuid)) { _, ids in
                if let workplaceID, ids.contains(workplaceID) { return }
                self.workplaceID = workplaces.last?.uuid
            }
            .alert("このシフトは確認が必要です", isPresented: overlapAlert) {
                Button("このまま保存") {
                    overlap = []
                    save(force: true)
                }
                Button("やめる", role: .cancel) {
                    overlap = []
                }
            } message: {
                Text(ShiftOverlap.confirmMessage(overlap))
            }
            .sheet(isPresented: $overlapSheet) {
                ShiftOverlapList(hits: overlap, onSave: {
                    overlapSheet = false
                    overlap = []
                    save(force: true)
                }, onCancel: {
                    overlapSheet = false
                    overlap = []
                })
            }
            .alert("このシフトを削除しますか？", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) { deleteShift() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("元に戻せません。")
            }
            .sheet(isPresented: $showWorkplaceCreator) {
                WorkplaceEditorView(existingID: nil)
            }
            .sheet(isPresented: $showDateEditor) {
                NavigationStack {
                    DatePicker("日付", selection: $draftDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                        .tint(Theme.signalInk)
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Theme.paper)
                        .navigationTitle("日付を選ぶ")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("キャンセル") { showDateEditor = false }
                                    .foregroundStyle(Theme.signalInk)
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("決定") {
                                    date = Calendar.current.startOfDay(for: draftDate)
                                    userEditedDate = true
                                    showDateEditor = false
                                }
                                .foregroundStyle(Theme.signalInk)
                            }
                        }
                        .darkSheet()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            workplaceID = existing.workplace?.uuid
            date = existing.date
            startMinutes = existing.startMinutes
            endMinutes = existing.endMinutes
            breakFollowsRules = existing.breakFollowsRules
            breakMinutes = existing.breakMinutes
            notes = existing.notes
            destinationName = existing.destinationName
            destinationPlace = existing.destinationPlace
            chosenPart = existing.partID
            customText = existing.customPay.map(String.init) ?? ""
            adjustmentText = existing.adjustmentYen == 0 ? "" : String(existing.adjustmentYen)
            adjustmentNote = existing.adjustmentNote
        } else {
            workplaceID = route.workplaceID ?? workplaces.first?.uuid
            date = route.date
            breakFollowsRules = true
        }
    }

    private func clockStamp(_ shift: WorkShift) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "ja_JP")
        clock.dateFormat = "H:mm"
        var parts: [String] = []
        if let start = shift.clockedInAt { parts.append("出勤 \(clock.string(from: start))") }
        if let end = shift.clockedOutAt { parts.append("退勤 \(clock.string(from: end))") }
        return parts.joined(separator: "  ") + "（予定の時刻と給料は変わりません）"
    }

    private func punchLine(_ shift: WorkShift) -> String? {
        guard let clockIn = shift.clockedInAt, let clockOut = shift.clockedOutAt, let place = shift.workplace else { return nil }
        let calendar = ShiftOverlap.tokyo
        let day = calendar.startOfDay(for: shift.date)
        let planned = calendar.date(byAdding: .minute, value: shift.startMinutes, to: day) ?? day
        let payable = PunchPay.payable(
            plannedStart: planned,
            clockIn: clockIn,
            clockOut: clockOut,
            unitMinutes: place.roundingUnitMinutes,
            start: InOutRecovered.RoundingDirection.resolved(place.roundingStartRaw),
            end: InOutRecovered.RoundingDirection.resolved(place.roundingEndRaw),
            earlyCountsFromPlan: place.earlyClockCountsFromPlan,
            calendar: calendar
        )
        return PunchPay.line(clockIn: clockIn, clockOut: clockOut, payable: payable, calendar: calendar)
    }

    private var overlapAlert: Binding<Bool> {
        Binding(get: { overlap.count == 1 && !overlapSheet }, set: { if !$0 { overlap = [] } })
    }

    private var liveOverlap: [ShiftOverlap.Hit] {
        guard let workplace = selectedWorkplace else { return [] }
        if ShiftDatePolicy.clockMinutes(startMinutes) == ShiftDatePolicy.clockMinutes(endMinutes) { return [] }
        let calendar = ShiftOverlap.tokyo
        let proposed = ShiftOverlap.span(
            id: existing.map { String(describing: $0.persistentModelID) } ?? "new",
            name: workplace.name,
            workplace: workplace.uuid,
            day: date,
            start: startMinutes,
            end: endMinutes,
            calendar: calendar
        )
        return ShiftOverlap.conflicts(
            of: proposed,
            among: shifts.map { ShiftOverlap.span(from: $0, calendar: calendar) },
            travelMinutes: travelMinutes,
            calendar: calendar
        )
    }

    /// Up to four workplaces are one tap each; more fall back to a menu.
    @ViewBuilder private var workplaceChoice: some View {
        if workplaces.count <= 4 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(workplaces) { workplace in
                        patternChip(workplace.name, selected: workplaceID == workplace.uuid) {
                            workplaceID = workplace.uuid
                            chosenPart = nil
                        }
                    }
                }
            }
        } else {
            Picker("勤務先", selection: $workplaceID) {
                ForEach(workplaces) { workplace in
                    Text(workplace.name).tag(Optional(workplace.uuid))
                }
            }
            .tint(Theme.accentText)
        }
    }

    private func dayStepButton(_ symbol: String, label: String, delta: Int) -> some View {
        Button {
            if let next = Calendar.current.date(byAdding: .day, value: delta, to: date) {
                date = Calendar.current.startOfDay(for: next)
                userEditedDate = true
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    /// Sets the end from the start so a usual shift takes two taps.
    private var durationChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("開始からの長さで終了を決める")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    ForEach([3, 4, 5, 6, 8], id: \.self) { hours in
                        ChipButton(title: "\(hours)時間", selected: false, identifier: "editor.duration.\(hours)") {
                            endMinutes = ShiftDatePolicy.clockMinutes(startMinutes + hours * 60)
                        }
                        .accessibilityLabel("終了を開始の\(hours)時間後にする")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var workplaceParts: [ShiftPart] {
        parts.filter { $0.workplaceUUID == workplaceID && !$0.hidden }
    }

    /// A pattern that sets no break (older ones) leaves the break as it is.
    private func applyPartBreak(_ part: ShiftPart) {
        guard part.breakModeRaw != PatternBreakMode.fixed.rawValue || part.breakMinutes > 0 else { return }
        let resolved = PatternBreak.resolve(
            modeRaw: part.breakModeRaw,
            fixedMinutes: part.breakMinutes,
            customRulesRaw: part.breakRulesRaw,
            startMinutes: ShiftPartPlace.clock(part.startMinute).minutes,
            endMinutes: ShiftPartPlace.clock(part.endMinute).minutes,
            workplace: selectedWorkplace
        )
        breakMinutes = resolved.minutes
        breakFollowsRules = resolved.followsRules
    }

    private func patternChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        ChipButton(title: title, selected: selected, action: action)
    }

    private func save(force: Bool = false) {
        guard let workplace = selectedWorkplace else {
            error = "勤務先を選んでください"
            return
        }
        let follows = breakFollowsRules && !workplace.payIsDaily
        let storedBreak = shownBreak
        let minutes = PayMath.workedMinutes(start: startMinutes, end: endMinutes, breakMinutes: storedBreak)
        guard workplace.payIsDaily || minutes > 0 else {
            error = "開始と終了を異なる時刻にしてください。"
            return
        }
        let storedDate = ShiftDatePolicy.dateToStore(
            existing: existing?.date,
            draft: date,
            userEditedDate: userEditedDate
        )
        if ShiftDatePolicy.clockMinutes(startMinutes) == ShiftDatePolicy.clockMinutes(endMinutes) {
            error = "開始と終了が同じです。保存できません。"
            return
        }
        if !force {
            let found = liveOverlap
            if found.count == 1 {
                overlap = found
                overlapSheet = false
                return
            }
            if ShiftOverlap.usesSheet(found) {
                overlap = found
                overlapSheet = true
                return
            }
        }
        if let existing {
            existing.date = storedDate
            existing.startMinutes = startMinutes
            existing.endMinutes = endMinutes
            existing.breakMinutes = storedBreak
            existing.breakFollowsRules = follows
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.destinationName = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.destinationPlace = destinationPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.customPay = parsedCustom
            existing.adjustmentYen = parsedAdjustment
            existing.adjustmentNote = adjustmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let shift = WorkShift(
                date: storedDate,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                breakMinutes: storedBreak,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                customPay: parsedCustom,
                adjustmentYen: parsedAdjustment,
                adjustmentNote: adjustmentNote.trimmingCharacters(in: .whitespacesAndNewlines),
                breakFollowsRules: follows,
                workplace: workplace,
                destinationName: destinationName.trimmingCharacters(in: .whitespacesAndNewlines),
                destinationPlace: destinationPlace.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(shift)
        }
        do {
            try context.save()
        } catch {
            self.error = "保存できませんでした。もう一度試してください。"
            return
        }
        onSaved?(storedDate)
        dismiss()
    }

    private var shownBreak: Int {
        guard let workplace = selectedWorkplace else { return breakMinutes }
        return BreakRules.minutesForEditor(
            payIsDaily: workplace.payIsDaily,
            followsRules: breakFollowsRules,
            manualMinutes: breakMinutes,
            start: startMinutes,
            end: endMinutes,
            customBreaks: workplace.customBreaks,
            rules: workplace.breakRules
        )
    }

    private var breakFollowsBinding: Binding<Bool> {
        Binding(
            get: { breakFollowsRules },
            set: { on in
                if on {
                    breakFollowsRules = true
                } else {
                    breakMinutes = shownBreak
                    breakFollowsRules = false
                }
            }
        )
    }

    private var breakEntryBinding: Binding<Int> {
        Binding(
            get: { shownBreak },
            set: { newValue in
                breakFollowsRules = false
                breakMinutes = newValue
            }
        )
    }

    private var draftMinutes: Int {
        PayMath.workedMinutes(
            start: startMinutes,
            end: endMinutes,
            breakMinutes: shownBreak
        )
    }

    private var clocksMatch: Bool {
        ShiftDatePolicy.clockMinutes(startMinutes) == ShiftDatePolicy.clockMinutes(endMinutes)
    }

    private var canSave: Bool {
        guard selectedWorkplace != nil else { return false }
        if clocksMatch { return false }
        if selectedWorkplace?.payIsDaily == true { return true }
        return draftMinutes > 0
    }

    private var shownError: String {
        if !error.isEmpty { return error }
        guard selectedWorkplace != nil else { return workplaces.isEmpty ? "" : "勤務先を選んでください" }
        if clocksMatch { return "開始と終了が同じです。保存できません。" }
        if selectedWorkplace?.payIsDaily != true, draftMinutes == 0 {
            return "開始と終了を異なる時刻にしてください。"
        }
        return ""
    }

    private var parsedCustom: Int? {
        let digits = customText.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private var parsedAdjustment: Int {
        let trimmed = adjustmentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        let negative = trimmed.hasPrefix("-") || trimmed.hasPrefix("−")
        let digits = trimmed.filter(\.isNumber)
        let value = Int(digits) ?? 0
        return negative ? -value : value
    }

    /// Copies a saved shift to another day. A day that already has the same
    /// workplace and times is left alone.
    private func copyShift(_ source: WorkShift, days: Int) {
        let calendar = Calendar.current
        guard let workplace = source.workplace,
              let moved = calendar.date(byAdding: .day, value: days, to: source.date) else { return }
        let day = calendar.startOfDay(for: moved)
        let duplicate = shifts.contains { other in
            other.uuid != source.uuid
                && calendar.isDate(other.date, inSameDayAs: day)
                && other.workplace?.uuid == workplace.uuid
                && other.startMinutes == source.startMinutes
                && other.endMinutes == source.endMinutes
        }
        if duplicate {
            copyNote = "\(Formatters.longDay(day))には、同じシフトがすでにあります。"
            return
        }
        context.insert(WorkShift(
            date: day,
            startMinutes: source.startMinutes,
            endMinutes: source.endMinutes,
            breakMinutes: source.breakMinutes,
            notes: source.notes,
            customPay: source.customPay,
            adjustmentYen: source.adjustmentYen,
            adjustmentNote: source.adjustmentNote,
            breakFollowsRules: source.breakFollowsRules,
            partID: source.partID,
            patternEndOnNextDay: source.patternEndOnNextDay,
            todosRaw: ShiftTodoCodec.encode(source.todos.map { ShiftTodoCodec.Item(id: UUID(), title: $0.title, done: false) }),
            workplace: workplace,
            destinationName: source.destinationName,
            destinationPlace: source.destinationPlace
        ))
        do {
            try context.save()
            copyNote = "\(Formatters.longDay(day))にコピーしました。"
        } catch {
            copyNote = "コピーできませんでした。もう一度試してください。"
        }
    }

    private func deleteShift() {
        if let existing { context.delete(existing) }
        do {
            try context.save()
        } catch {
            self.error = "削除できませんでした。もう一度試してください。"
            return
        }
        dismiss()
    }
}

/// The large time button. Opens a sheet that changes only the clock time.
struct MinutesTimePicker: View {
    var title: String
    @Binding var minutes: Int
    @State private var draft = 0
    @State private var showSheet = false

    var body: some View {
        Button {
            draft = ShiftDatePolicy.clockMinutes(minutes)
            showSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                DotoText(Formatters.clock(minutes), size: 30, spoken: Formatters.spokenClock(minutes), maxScale: 1.3)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Formatters.spokenClock(minutes))
        .accessibilityHint("時刻を変えます。日付は変わりません。")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showSheet) {
            TimeAdjustSheet(
                title: title,
                minutes: $draft,
                onCommit: {
                    minutes = ShiftDatePolicy.minutesAfterDismiss(original: minutes, draft: draft, committed: true)
                    showSheet = false
                },
                onCancel: { showSheet = false }
            )
        }
    }
}

struct TimeAdjustSheet: View {
    var title: String
    @Binding var minutes: Int
    var onCommit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    DotoText(Formatters.clock(minutes), size: 64, spoken: "\(title) \(Formatters.spokenClock(minutes))", maxScale: 1.2)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Space.xs)
                    VStack(spacing: Space.xs) {
                        stepRow(amount: 60, unit: "1時間")
                        stepRow(amount: 15, unit: "15分")
                    }
                    Card {
                        Text("ホイールで選ぶ")
                            .font(AppFont.label)
                            .foregroundStyle(Theme.ink)
                        DatePicker(title, selection: wheelBinding, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .accessibilityLabel(title)
                    }
                    InfoNote(text: "変わるのは時刻だけです。終了が開始より前のときは、日付を動かさず、翌日までの勤務として数えます。")
                }
                .padding(Space.m)
            }
            .background(Theme.paper)
            .navigationTitle("\(title)の時刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("time.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定", action: onCommit)
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
        }
        .presentationDetents([.large])
    }

    private var wheelBinding: Binding<Date> {
        Binding {
            ShiftDatePolicy.clockDate(minutes: minutes)
        } set: { newValue in
            minutes = ShiftDatePolicy.clockMinutes(from: newValue)
        }
    }

    private func stepRow(amount: Int, unit: String) -> some View {
        HStack(spacing: Space.xs) {
            stepButton("\(unit)前", delta: -amount)
            stepButton("\(unit)後", delta: amount)
        }
    }

    private func stepButton(_ label: String, delta: Int) -> some View {
        Button {
            minutes = ShiftDatePolicy.clockMinutes(minutes + delta)
        } label: {
            Text(label)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.signal, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Break minutes with a visible label and ±15 / ±1 buttons.
struct BreakMinutesControl: View {
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 0...600

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("休憩の長さ")
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: Space.xs)
                Text(minutes == 0 ? "なし" : Formatters.hours(minutes))
                    .font(AppFont.value.weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("休憩")
            .accessibilityValue(minutes == 0 ? "なし" : Formatters.hours(minutes))
            HStack(spacing: Space.xs) {
                nudge("15分減らす", delta: -15, title: "−15分")
                nudge("15分増やす", delta: 15, title: "+15分")
                nudge("1分減らす", delta: -1, title: "−1分")
                nudge("1分増やす", delta: 1, title: "+1分")
            }
        }
    }

    private func nudge(_ label: String, delta: Int, title: String) -> some View {
        Button {
            minutes = ShiftDatePolicy.clampedBreak(minutes + delta, range: range)
        } label: {
            Text(title)
                .font(AppFont.label.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Shown before saving when the new shift overlaps others or leaves too little travel time.
struct ShiftOverlapList: View {
    var hits: [ShiftOverlap.Hit]
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.s) {
                InfoNote(text: "次のシフトと重なるか、移動の時間が足りません。このまま保存するか、編集に戻って時間を直してください。", tone: .warning)
                    .padding(.top, Space.xs)
                Card(spacing: Space.xs) {
                    ForEach(hits) { hit in
                        Text(ShiftOverlap.row(hit))
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RowDivider()
                    }
                }
                PrimaryButton(title: "このまま保存", identifier: "overlap.save", action: onSave)
                SecondaryButton(title: "編集に戻る", identifier: "overlap.cancel", action: onCancel)
            }
            .background(Theme.paper)
            .navigationTitle("このシフトは確認が必要です")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("戻る", action: onCancel)
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
        }
        .presentationDetents([.medium, .large])
    }
}
