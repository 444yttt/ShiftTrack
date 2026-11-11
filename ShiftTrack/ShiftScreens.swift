import SwiftData
import SwiftUI

struct ShiftListScreen: View {
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @State private var router = ImportRouter.shared
    @State private var showUpcoming = true
    @State private var editor: EditorRoute?

    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }

    var body: some View {
        ScreenScroll {
            HStack(alignment: .center) {
                Text("シフト")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Theme.ink)
                Spacer()
                LimeCapsuleButton(title: "+ 追加") {
                    editor = EditorRoute(shiftID: nil, date: Date(), workplaceID: nil)
                }
            }
            .padding(.top, 8)

            Button {
                router.presentChooser()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 14, weight: .bold))
                    Text("シフト表から取り込む")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .foregroundStyle(Theme.lime)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            if router.stagedCount > 0 {
                Button {
                    if let pending = PendingImportStore.load() {
                        router.presentReview(pending)
                    }
                } label: {
                    Text("確認待ちの候補が \(router.stagedCount) 件あります")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.lime)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }

            HStack(spacing: 6) {
                segment("これから", on: showUpcoming) { showUpcoming = true }
                segment("過去", on: !showUpcoming) { showUpcoming = false }
            }
            .padding(.top, 12)

            if visible.isEmpty {
                Text(showUpcoming ? "これからのシフトはありません" : "過去のシフトはありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 28)
            } else {
                VStack(spacing: 10) {
                    ForEach(visible) { shift in
                        Button {
                            editor = EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid)
                        } label: {
                            ShiftCard(shift: shift, includeTransport: includeTransport)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
            }
        }
        .background(Theme.background)
        .onAppear { router.refreshCount() }
        .sheet(item: $editor) { route in
            ShiftEditorView(route: route)
        }
    }

    private var visible: [WorkShift] {
        let now = Date()
        let filtered = shifts.filter { showUpcoming ? !$0.hasEnded(now: now) : $0.hasEnded(now: now) }
        return filtered.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return showUpcoming ? lhs.date < rhs.date : lhs.date > rhs.date
            }
            return showUpcoming ? lhs.startMinutes < rhs.startMinutes : lhs.startMinutes > rhs.startMinutes
        }
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(on ? Theme.ink : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(on ? Theme.lime : Theme.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EditorRoute: Identifiable {
    var id: String { "\(shiftID?.uuidString ?? "new")-\(date.timeIntervalSinceReferenceDate)" }
    var shiftID: UUID?
    var date: Date
    var workplaceID: UUID?
}

struct DayDetailSheet: View {
    var day: Date
    var workplaceID: UUID?
    @Query(sort: \WorkShift.startMinutes) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @Environment(\.dismiss) private var dismiss
    @State private var editor: EditorRoute?

    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }
    private var dayShifts: [WorkShift] {
        shifts.filter { shift in
            Calendar.current.isDate(shift.date, inSameDayAs: day)
                && (workplaceID == nil || shift.workplace?.uuid == workplaceID)
        }
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                if dayShifts.isEmpty {
                    Text("この日のシフトはありません")
                        .designFont(20)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                } else {
                    VStack(spacing: 10) {
                        ForEach(dayShifts) { shift in
                            Button {
                                editor = EditorRoute(shiftID: shift.uuid, date: shift.date, workplaceID: shift.workplace?.uuid)
                            } label: {
                                ShiftCard(shift: shift, includeTransport: includeTransport)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
                LimeCapsuleButton(title: "+ この日に追加", fillWidth: true, designSize: 20) {
                    editor = EditorRoute(shiftID: nil, date: day, workplaceID: workplaceID)
                }
                .padding(.top, 16)
            }
            .background(Theme.background)
            .navigationTitle(Formatters.longDay(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
            }
            .darkSheet()
            .sheet(item: $editor) { route in
                ShiftEditorView(route: route)
            }
        }
    }
}

struct ShiftAddChooser: View {
    var day: Date
    var workplaceID: UUID?
    var onSaved: ([Date]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \WorkShift.date, order: .reverse) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @State private var editor: EditorRoute?
    @State private var tableText = ""
    @State private var tableError = ""
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

    private var drafts: [ShiftTextParser.Draft] {
        ShiftTextParser.parse(
            text: tableText,
            knownNames: workplaces.map(\.name),
            fallbackDate: day,
            defaultWorkplace: assumedWorkplace?.name ?? ""
        )
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
            ScreenScroll {
                Text(Formatters.longDay(day))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                tableSection
                manualSection
                historySection
            }
            .background(Theme.background)
            .navigationTitle("シフトを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { tableFocused = false }
                        .foregroundStyle(Theme.lime)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("シフト表")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(tableHint)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $tableText)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(8)
                    .focused($tableFocused)
                if tableText.isEmpty {
                    Text(tablePlaceholder)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onChange(of: tableText) { _, _ in tableError = "" }
            if !tableProblem.isEmpty {
                Text(tableProblem)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.behind)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !drafts.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(drafts.prefix(6))) { draft in
                        draftRow(draft)
                    }
                    if drafts.count > 6 {
                        Text("ほか \(drafts.count - 6) 件")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            LimeCapsuleButton(title: "シフト表に追加", fillWidth: true) {
                commitTable()
            }
            .disabled(drafts.isEmpty)
            .opacity(drafts.isEmpty ? 0.4 : 1)
        }
        .padding(.top, 12)
    }

    private var tablePlaceholder: String {
        if let name = assumedWorkplace?.name {
            return "10:00-15:00\n18:00-23:00 休憩60分\n11/9 \(name) 9:00-13:00"
        }
        return "11/8 カフェA 10:00-15:00\n11/9 18:00-23:00 休憩60分"
    }

    private var manualSection: some View {
        Button {
            editor = EditorRoute(shiftID: nil, date: day, workplaceID: workplaceID ?? assumedWorkplace?.uuid)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("1件ずつ入力")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("勤務先と時刻を画面で選びます")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("履歴から追加")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if history.isEmpty {
                Text("まだ履歴がありません。追加すると、次から同じ時間を選べます。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(history) { shift in
                    Button {
                        add(shift)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(shift.workplace?.color ?? Theme.lime)
                                .frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shift.workplace?.name ?? "勤務先")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                Text("\(Formatters.clock(shift.startMinutes))–\(Formatters.clock(shift.endMinutes))  休憩\(shift.breakMinutes)分")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private func draftRow(_ draft: ShiftTextParser.Draft) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(for: draft.workplaceName))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.workplaceName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(draftCaption(draft))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            guard let date = draft.date() else { continue }
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
                    && Calendar.current.isDate(shift.date, inSameDayAs: date)
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
    @State private var destinationName = ""
    @State private var destinationPlace = ""
    @FocusState private var typing: Bool

    private var existing: WorkShift? { shifts.first { $0.uuid == route.shiftID } }
    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }
    private var selectedWorkplace: Workplace? { workplaces.first { $0.uuid == workplaceID } }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Group {
                if workplaces.isEmpty {
                    Text("先に勤務先を追加してください。")
                        .designFont(13)
                        .foregroundStyle(Theme.muted)
                    LimeCapsuleButton(title: "勤務先を追加", fillWidth: true, designSize: 16) {
                        showWorkplaceCreator = true
                    }
                    .padding(.top, 12)
                } else {
                    Text("\(Formatters.monthDayWeekday(date))のシフト")
                        .designFont(16, weight: .black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !workplaceParts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                patternChip("なし", selected: chosenPart == nil) { chosenPart = nil }
                                ForEach(workplaceParts) { part in
                                    patternChip(part.name, selected: chosenPart == part.uuid) {
                                        chosenPart = part.uuid
                                        startMinutes = part.startMinute
                                        endMinutes = part.endMinute
                                    }
                                }
                            }
                        }
                    }
                    formCard {
                        labeled("勤務先") {
                            if existing != nil {
                                Text(selectedWorkplace?.name ?? "なし")
                                    .designFont(16, weight: .bold)
                            } else {
                                Picker("勤務先", selection: $workplaceID) {
                                    ForEach(workplaces) { workplace in
                                        Text(workplace.name).tag(Optional(workplace.uuid))
                                    }
                                }
                                .tint(Theme.lime)
                            }
                        }
                        divider
                        Button {
                            draftDate = date
                            showDateEditor = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("日付")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.muted)
                                Text(Formatters.longDay(date))
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(Theme.ink)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.cardRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("日付")
                        .accessibilityValue(Formatters.longDay(date))
                        .accessibilityHint("日付を変えるときだけ開きます")
                        HStack(alignment: .top, spacing: 10) {
                            MinutesTimePicker(title: "開始", minutes: $startMinutes)
                            MinutesTimePicker(title: "終了", minutes: $endMinutes)
                        }
                        ForEach(liveOverlap) { hit in
                            Text(ShiftOverlap.row(hit))
                                .designFont(13)
                                .foregroundStyle(Theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let existing, existing.clockedInAt != nil || existing.clockedOutAt != nil {
                            Text(clockStamp(existing))
                                .designFont(13)
                                .foregroundStyle(Theme.muted)
                        }
                        if selectedWorkplace?.payIsDaily == true {
                            Text("日給の勤務先では、休憩時間は給料から引きません。")
                                .designFont(13)
                                .foregroundStyle(Theme.muted)
                        } else {
                            Toggle("休憩を規則から入れる", isOn: breakFollowsBinding)
                                .tint(Theme.lime)
                            Text(breakFollowsRules
                                 ? BreakRules.summary(
                                    customBreaks: selectedWorkplace?.customBreaks ?? false,
                                    rules: selectedWorkplace?.breakRules ?? []
                                 ) + "時刻を変えるとこの休憩も変わります。"
                                 : "手入力です。時刻を変えても、この休憩は残します。")
                                .designFont(13)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            BreakMinutesControl(minutes: breakEntryBinding, range: 0...600)
                            Text("実働 \(Formatters.hours(draftMinutes))")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.lime)
                        }
                    }
                    formCard {
                        labeled("給料の個別設定") {
                            yenField("空欄なら自動計算", text: $customText)
                        }
                        divider
                        labeled("天引・手当") {
                            yenField("天引はマイナス", text: $adjustmentText, signed: true)
                        }
                        TextField("天引・手当の詳細", text: $adjustmentNote)
                            .designFont(16)
                            .focused($typing)
                        divider
                        TextField("メモ", text: $notes, axis: .vertical)
                            .designFont(16)
                            .foregroundStyle(Theme.ink)
                            .focused($typing)
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
                        Text("給料 \(Formatters.yen(amount))")
                            .designFont(16, weight: .bold)
                            .foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !shownError.isEmpty {
                        Text(shownError)
                            .designFont(13)
                            .foregroundStyle(Theme.behind)
                    }
                    formCard {
                        Text("行き先")
                            .designFont(16, weight: .bold)
                        Text("マップで探す")
                            .designFont(16, weight: .bold)
                        Text("検索結果は未回収です。")
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                        TextField("名前", text: $destinationName)
                            .padding(12)
                            .background(Theme.cardRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        TextField("住所", text: $destinationPlace)
                            .padding(12)
                            .background(Theme.cardRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("空のときは勤務先に向かいます")
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                    }
                    LimeCapsuleButton(title: existing == nil ? "完了する" : "保存する", fillWidth: true, designSize: 16) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.4)
                        .padding(.top, 8)
                    if existing != nil {
                        Button("削除する") { confirmDelete = true }
                            .designFont(16, weight: .bold)
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                }
                .padding(ScreenInsets.shiftEditor)
            }
            .background(Theme.background)
            .navigationTitle(existing == nil ? "シフトを追加" : "シフトの詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { typing = false }
                        .foregroundStyle(Theme.lime)
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
                        .tint(Theme.lime)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Theme.background)
                        .navigationTitle("日付を変更")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("キャンセル") { showDateEditor = false }
                                    .foregroundStyle(Theme.lime)
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("決定") {
                                    date = Calendar.current.startOfDay(for: draftDate)
                                    userEditedDate = true
                                    showDateEditor = false
                                }
                                .foregroundStyle(Theme.lime)
                            }
                        }
                        .darkSheet()
                }
                .presentationDetents([.medium])
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

    private var workplaceParts: [ShiftPart] {
        parts.filter { $0.workplaceUUID == workplaceID && !$0.hidden }
    }

    private func patternChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .designFont(16, weight: .bold)
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Theme.ink : Theme.cardRaised)
            .clipShape(Capsule())
            .buttonStyle(.plain)
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

    private func yenField(_ prompt: String, text: Binding<String>, signed: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text("¥")
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.muted)
            TextField(prompt, text: text)
                .keyboardType(signed ? .numbersAndPunctuation : .numberPad)
                .designFont(16, weight: .bold)
                .focused($typing)
        }
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

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 10)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .designFont(13, weight: .medium)
                .foregroundStyle(Theme.muted)
            content()
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.muted)
                Text(Formatters.clock(minutes))
                    .font(.title.weight(.black))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Formatters.clock(minutes))
        .accessibilityHint("時刻を変更します。日付は変わりません。")
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
            VStack(alignment: .leading, spacing: 16) {
                Text(Formatters.clock(minutes))
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(title)
                    .accessibilityValue(Formatters.clock(minutes))

                VStack(spacing: 10) {
                    stepRow(amount: 60, unit: "1時間")
                    stepRow(amount: 15, unit: "15分")
                }

                DatePicker(title, selection: wheelBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel(title)

                Text("変えるのは時刻だけです。終了が開始より前のときは、日付を動かさず翌日にまたぐ勤務として計算します。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle("\(title)の時刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                        .foregroundStyle(Theme.lime)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定", action: onCommit)
                        .foregroundStyle(Theme.lime)
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
        HStack(spacing: 10) {
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
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.vertical, 8)
                .background(Theme.lime)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct BreakMinutesControl: View {
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 0...600

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("休憩")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.muted)
            Text(Formatters.hours(minutes))
                .font(.title3.weight(.black))
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("休憩")
                .accessibilityValue(Formatters.hours(minutes))
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    nudge("15分減らす", delta: -15, title: "−15分")
                    nudge("15分増やす", delta: 15, title: "+15分")
                }
                HStack(spacing: 8) {
                    nudge("1分減らす", delta: -1, title: "−1分")
                    nudge("1分増やす", delta: 1, title: "+1分")
                }
            }
        }
    }

    private func nudge(_ label: String, delta: Int, title: String) -> some View {
        Button {
            minutes = ShiftDatePolicy.clampedBreak(minutes + delta, range: range)
        } label: {
            Text(title)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.lime)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct WorkplaceEditorView: View {
    var existingID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]

    @State private var name = ""
    @State private var colorHex = Theme.palette[0]
    @State private var wageText = "1200"
    @State private var dailyText = "8000"
    @State private var transportText = "500"
    @State private var notes = ""
    @State private var genre = ""
    @State private var place = ""
    @State private var phone = ""
    @State private var openingHours = ""
    @State private var officialURL = ""
    @State private var closingDay = 0
    @State private var paydayOffset = 0
    @State private var paydayDay = 0
    @State private var payCycle: PayCycle = .month
    @State private var payWeekday = 0
    @State private var payIsDaily = false
    @State private var holidayOn = false
    @State private var holidayText = "0"
    @State private var holidayDays: Set<Int> = [1]
    @State private var nightOn = false
    @State private var nightText = "0"
    @State private var nightStart = 22 * 60
    @State private var nightEnd = 5 * 60
    @State private var holidayNightOn = false
    @State private var holidayNightText = "0"
    @State private var holidayNightStart = 22 * 60
    @State private var holidayNightEnd = 5 * 60
    @State private var overtimeOn = false
    @State private var overtimeHours = 8
    @State private var overtimePerHour = true
    @State private var overtimeText = "0"
    @State private var customBreaks = false
    @State private var roundingUnit = 1
    @State private var roundingStart = 0
    @State private var roundingEnd = 0
    @State private var nightRate = 0
    @State private var overtimeRate = 0
    @State private var holidayRates = Array(repeating: 0, count: 7)
    @State private var wageHistory: [Workplace.WageHistoryEntry] = []
    @State private var payRuleDates: [Date] = []
    @State private var payRuleDate = Date()
    @State private var wageBands: [Workplace.WageBandEntry] = []
    @State private var bandStart = 22 * 60
    @State private var bandEnd = 5 * 60
    @State private var bandWage = "1000"
    @State private var bandIncludesNight = false
    @State private var breakRules: [InOutRecovered.BreakRule] = []
    @State private var error = ""
    @State private var confirmDelete = false
    @FocusState private var typing: Bool

    private var existing: Workplace? { workplaces.first { $0.uuid == existingID } }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                formCard {
                    sectionTitle("勤務先")
                    field("名前", text: $name)
                    field("ジャンル", text: $genre)
                    field("場所", text: $place)
                    field("電話番号", text: $phone)
                    field("営業時間", text: $openingHours)
                    field("公式サイト", text: $officialURL)
                    Text("カレンダーでの表示色")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    HStack(spacing: 10) {
                        ForEach(Theme.palette, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hexString: hex))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if colorHex == hex {
                                            Circle().stroke(Theme.lime, lineWidth: 2).padding(-3)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("表示色")
                            .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                        }
                    }
                }
                NavigationLink {
                    LocationNoteView(place: $place)
                } label: {
                    editorLink("住所・位置（任意）")
                }
                NavigationLink {
                    LateMessageComposer()
                } label: {
                    editorLink("遅刻連絡の文章の型")
                }
                NavigationLink {
                    PayTermsNote()
                } label: {
                    editorLink("締め日と支払日")
                }
                NavigationLink {
                    PayScheduleNote()
                } label: {
                    editorLink("土日の支払日")
                }
                formCard {
                    sectionTitle("締めと給料日")
                    dayPicker("締日", selection: $closingDay)
                    Picker("給料日の月", selection: $paydayOffset) {
                        Text("当月").tag(0)
                        Text("翌月").tag(1)
                        Text("翌々月").tag(2)
                    }
                    .tint(Theme.lime)
                    dayPicker("給料日", selection: $paydayDay)
                    Picker("支払周期", selection: $payCycle) {
                        ForEach(PayCycle.allCases) { cycle in
                            Text(cycle.title).tag(cycle)
                        }
                    }
                    .tint(Theme.lime)
                    if payCycle == .week {
                        Picker("支払う曜日", selection: $payWeekday) {
                            Text("未選択").tag(0)
                            Text("日曜").tag(1)
                            Text("月曜").tag(2)
                            Text("火曜").tag(3)
                            Text("水曜").tag(4)
                            Text("木曜").tag(5)
                            Text("金曜").tag(6)
                            Text("土曜").tag(7)
                        }
                        .tint(Theme.lime)
                    }
                    Text("月払いは、今までと同じ締め日と給料日です。週払いと日払いは、ここで選んだときだけ入金日が変わります。時給・日給の金額計算は変わりません。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                formCard {
                    sectionTitle("給料")
                    Picker("給料", selection: $payIsDaily) {
                        Text("時給").tag(false)
                        Text("日給").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if payIsDaily {
                        field("日給", text: $dailyText, number: true)
                    } else {
                        field("時給", text: $wageText, number: true)
                    }
                    field("交通費", text: $transportText, number: true)
                    DatePicker("適用開始日", selection: $payRuleDate, displayedComponents: .date)
                        .tint(Theme.lime)
                    ForEach(Array(payRuleDates.enumerated()), id: \.offset) { index, day in
                        HStack {
                            Text(Formatters.longDay(day))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("削除") { payRuleDates.remove(at: index) }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.destructive)
                        }
                    }
                    Button("お給料の決まりの適用開始日を足す") {
                        payRuleDates.append(payRuleDate)
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lime)
                }
                formCard {
                    sectionTitle("休日・深夜・残業")
                    Toggle("休日給料", isOn: $holidayOn).tint(Theme.lime)
                    if holidayOn {
                        VStack(alignment: .leading, spacing: 10) {
                            field("休日給料", text: $holidayText, number: true)
                            weekdayPicker
                        }
                    }
                    if !payIsDaily {
                        nightFields
                    }
                    Toggle("残業手当", isOn: $overtimeOn).tint(Theme.lime)
                    if overtimeOn {
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper(value: $overtimeHours, in: 1...16) {
                                Text("適応時間 \(overtimeHours)時間")
                                    .foregroundStyle(Theme.ink)
                            }
                            Picker("金額の単位", selection: $overtimePerHour) {
                                Text("1時間あたり").tag(true)
                                Text("1シフトあたり").tag(false)
                            }
                            .tint(Theme.lime)
                            field("追加金額", text: $overtimeText, number: true)
                            Stepper(value: $overtimeRate, in: 0...100) {
                                Text("割増 \(overtimeRate)%")
                                    .foregroundStyle(Theme.ink)
                            }
                            Text("予定全体の時給分では、しきい値を超えた分にこの割合を足します。このシフトより前の分数は未確定なので足しません。今の見込の追加金額とは別です。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                formCard {
                    sectionTitle("休憩")
                    Toggle("この勤務先の規則を使う", isOn: $customBreaks)
                        .tint(Theme.lime)
                    if customBreaks {
                        Text("勤務時間が閾値を超えたとき、超えた中でいちばん長い閾値の休憩を入れます。保存済みのシフトは、ここでは書き換わりません。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if breakRules.isEmpty {
                            Text("規則がないので、自動の休憩は0分です。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        BreakRuleEditor(rules: $breakRules)
                    } else {
                        Text("法律で決まった休憩で計算します（6時間を超えたら45分、8時間を超えたら60分）。保存済みのシフトは変わりません。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                formCard {
                    sectionTitle("開始と終了の丸め")
                    Text("保存したシフトの時刻も、入っている給料の見込も、この設定だけでは変わりません。単位が2分未満か、向きがそのままのときは、その時刻を動かしません。参考アプリの丸めの再構成で、金額の式ではありません。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker("単位", selection: $roundingUnit) {
                        ForEach(roundingUnits, id: \.self) { unit in
                            Text(unit < 2 ? "\(unit)分（動かさない）" : "\(unit)分").tag(unit)
                        }
                    }
                    .tint(Theme.lime)
                    roundingDirectionPicker("開始", selection: $roundingStart)
                    roundingDirectionPicker("終了", selection: $roundingEnd)
                    Text(roundingPreview)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                formCard {
                    sectionTitle("時給の履歴と時間帯")
                    Text("予定全体の時給分は、履歴の末尾から適用日がシフトの日以前の行を使います。空なら0です。全部がシフト日より後のときは未確定で、円を出しません。並び順は検査していないので、日付で並べ替えません。時間帯の境界はまだ合計へ入れていません。上の時給欄は、今月の見込みだけが使います。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(wageHistory.enumerated()), id: \.offset) { index, entry in
                        HStack {
                            Text("\(Formatters.longDay(entry.at))  \(Formatters.yen(entry.hourlyWage))")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("削除") { wageHistory.remove(at: index) }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.destructive)
                        }
                    }
                    Button("今の時給を履歴に足す") {
                        wageHistory.append(.init(at: .now, hourlyWage: yen(wageText)))
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lime)
                    ForEach(Array(wageBands.enumerated()), id: \.offset) { index, band in
                        HStack {
                            Text("\(Formatters.clock(band.startMinutes))–\(Formatters.clock(band.endMinutes)) \(Formatters.yen(band.hourlyWage))")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("削除") { wageBands.remove(at: index) }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.destructive)
                        }
                    }
                    HStack(alignment: .top, spacing: 10) {
                        MinutesTimePicker(title: "帯の開始", minutes: $bandStart)
                        MinutesTimePicker(title: "帯の終了", minutes: $bandEnd)
                    }
                    field("帯の時給", text: $bandWage, number: true)
                    Toggle("この帯は深夜割増を含む", isOn: $bandIncludesNight).tint(Theme.lime)
                    Button("時間帯を足す") {
                        wageBands.append(.init(
                            startMinutes: bandStart,
                            endMinutes: bandEnd,
                            hourlyWage: yen(bandWage),
                            includesNightPremium: bandIncludesNight
                        ))
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.lime)
                    let names = ["日", "月", "火", "水", "木", "金", "土"]
                    ForEach(0..<7, id: \.self) { index in
                        Stepper(value: $holidayRates[index], in: 0...100) {
                            Text("\(names[index])の休日割増 \(holidayRates[index])%")
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    Text("休日の割合は曜日番号から1を引いた位置です。0%はその曜日に足しません。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                formCard {
                    sectionTitle("メモ")
                    field("メモ", text: $notes)
                }
                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.behind)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                LimeCapsuleButton(title: existing == nil ? "完了する" : "保存する", fillWidth: true) { save() }
                if existing != nil {
                    Button("この勤務先を削除") { confirmDelete = true }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .background(Theme.background)
            .navigationTitle(existing == nil ? "勤務先を追加" : "勤務先を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { typing = false }
                        .foregroundStyle(Theme.lime)
                }
            }
            .darkSheet()
            .onAppear(perform: load)
            .onChange(of: customBreaks) { _, on in
                if on, breakRules.isEmpty {
                    breakRules = InOutRecovered.legalBreakRules
                }
            }
            .alert("この勤務先と、入っているシフトを削除しますか？", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) {
                    if let existing { context.delete(existing) }
                    do {
                        try context.save()
                    } catch {
                        self.error = "削除できませんでした。もう一度試してください。"
                        return
                    }
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }

    private func load() {
        if let existing {
            name = existing.name
            colorHex = existing.colorHex
            wageText = String(existing.hourlyWage)
            dailyText = String(existing.dailyWage)
            transportText = String(existing.transportAllowance)
            notes = existing.notes
            genre = existing.genre
            place = existing.place
            phone = existing.phone
            openingHours = existing.openingHours
            officialURL = existing.officialURL
            closingDay = existing.closingDay
            paydayOffset = existing.paydayMonthOffset
            paydayDay = existing.paydayDay
            payCycle = existing.payCycle
            payWeekday = existing.payWeekday
            payIsDaily = existing.payIsDaily
            holidayOn = existing.holidayPayEnabled
            holidayText = String(existing.holidayWage)
            holidayDays = existing.holidayWeekdays.isEmpty ? [1] : existing.holidayWeekdays
            nightOn = existing.nightPayEnabled
            nightText = String(existing.nightWage)
            nightStart = existing.nightStartMinutes
            nightEnd = existing.nightEndMinutes
            holidayNightOn = existing.holidayNightEnabled
            holidayNightText = String(existing.holidayNightWage)
            holidayNightStart = existing.holidayNightStartMinutes
            holidayNightEnd = existing.holidayNightEndMinutes
            overtimeOn = existing.overtimeEnabled
            overtimeHours = max(1, existing.overtimeAfterMinutes / 60)
            overtimePerHour = existing.overtimePerHour
            overtimeText = String(existing.overtimeExtra)
            customBreaks = existing.customBreaks
            breakRules = existing.breakRules
            roundingUnit = existing.roundingUnitMinutes
            roundingStart = existing.roundingStartRaw
            roundingEnd = existing.roundingEndRaw
            nightRate = existing.nightRatePercent
            overtimeRate = existing.overtimeRatePercent
            holidayRates = existing.holidayRatePercents
            wageHistory = existing.wageHistory
            payRuleDates = existing.payRuleDates
            wageBands = existing.wageBands
        } else if let settings = settingsRows.first {
            wageText = String(settings.defaultHourlyWage)
            transportText = String(settings.defaultTransportAllowance)
            let used = Set(workplaces.map(\.colorHex))
            colorHex = Theme.palette.first { !used.contains($0) } ?? Theme.palette[0]
        }
    }

    private var nightFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("深夜給料", isOn: $nightOn).tint(Theme.lime)
            if nightOn {
                field("深夜給料", text: $nightText, number: true)
                Stepper(value: $nightRate, in: 0...100) {
                    Text("深夜の割増 \(nightRate)%")
                        .foregroundStyle(Theme.ink)
                }
                Text("予定全体の時給分では、深夜の時間の基本給にこの割合を足します。0%なら足しません。上の深夜給料は、今の見込が時給を置き換える金額です。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    MinutesTimePicker(title: "深夜の開始", minutes: $nightStart)
                    MinutesTimePicker(title: "深夜の終了", minutes: $nightEnd)
                }
            }
            if holidayOn {
                Toggle("休日深夜給料", isOn: $holidayNightOn).tint(Theme.lime)
                if holidayNightOn {
                    field("休日深夜給料", text: $holidayNightText, number: true)
                    HStack(alignment: .top, spacing: 10) {
                        MinutesTimePicker(title: "休日深夜の開始", minutes: $holidayNightStart)
                        MinutesTimePicker(title: "休日深夜の終了", minutes: $holidayNightEnd)
                    }
                }
            }
        }
    }

    private var roundingUnits: [Int] {
        var units = [1, 5, 10, 15, 30, 60]
        if !units.contains(roundingUnit) {
            units.append(roundingUnit)
            units.sort()
        }
        return units
    }

    private func roundingDirectionPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("そのまま").tag(0)
            Text("切り上げ").tag(1)
            Text("切り捨て").tag(2)
            Text("近い方").tag(3)
        }
        .tint(Theme.lime)
    }

    private var roundingPreview: String {
        let start = InOutRecovered.roundedSecondsFromStartOfDay(
            450,
            unitMinutes: roundingUnit,
            direction: InOutRecovered.RoundingDirection.resolved(roundingStart)
        )
        let end = InOutRecovered.roundedSecondsFromStartOfDay(
            450,
            unitMinutes: roundingUnit,
            direction: InOutRecovered.RoundingDirection.resolved(roundingEnd)
        )
        return "例: 0時7分30秒は、開始が\(roundingClock(start))、終了が\(roundingClock(end))です。1440分では巻きません。"
    }

    private func roundingClock(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "−" : ""
        let whole = Int(abs(seconds).rounded(.towardZero))
        return "\(sign)\(whole / 3600)時\((whole / 60) % 60)分\(whole % 60)秒"
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.ink)
    }

    private func editorLink(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dayPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            Text("月末").tag(0)
            ForEach(1...31, id: \.self) { day in
                Text("\(day)日").tag(day)
            }
        }
        .tint(Theme.lime)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let signedWage = WorkplaceEditorCheck.signedYen(wageText)
        if let message = WorkplaceEditorCheck.message(
            name: name,
            hourlyWage: payIsDaily ? nil : signedWage,
            wageDates: wageHistory.map(\.at),
            payRuleDates: payRuleDates,
            calendar: .current
        ) {
            error = message
            return
        }
        let wage = min(100_000, max(0, signedWage))
        let daily = min(100_000, max(0, Int(dailyText.filter(\.isNumber)) ?? 0))
        if payCycle == .week, !(1...7).contains(payWeekday) {
            error = "週払いの曜日を選んでください"
            return
        }
        if payIsDaily, daily == 0 {
            error = "日給を入力してください"
            return
        }
        if !payIsDaily, wage == 0 {
            error = "時給を入力してください"
            return
        }
        if holidayOn, holidayDays.isEmpty {
            error = "休日の曜日を1つ選んでください"
            return
        }
        if holidayOn, yen(holidayText) == 0 {
            error = "休日給料を入力してください"
            return
        }
        if nightOn, !payIsDaily, yen(nightText) == 0 {
            error = "深夜給料を入力してください"
            return
        }
        if holidayNightOn, holidayOn, !payIsDaily, yen(holidayNightText) == 0 {
            error = "休日深夜給料を入力してください"
            return
        }
        if overtimeOn, yen(overtimeText) == 0 {
            error = "残業手当の金額を入力してください"
            return
        }
        error = ""
        let transport = min(100_000, max(0, Int(transportText.filter(\.isNumber)) ?? 0))
        let workplace: Workplace
        if let existing {
            workplace = existing
            workplace.name = trimmed
            workplace.colorHex = colorHex
        } else {
            workplace = Workplace(
                name: trimmed,
                colorHex: colorHex,
                hourlyWage: wage,
                transportAllowance: transport,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(workplace)
        }
        workplace.hourlyWage = wage
        workplace.transportAllowance = transport
        workplace.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.openingHours = openingHours.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.officialURL = officialURL.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.closingDay = closingDay
        workplace.paydayMonthOffset = paydayOffset
        workplace.paydayDay = paydayDay
        workplace.payCycle = payCycle
        workplace.payWeekday = payWeekday
        workplace.payIsDaily = payIsDaily
        workplace.dailyWage = daily
        workplace.holidayPayEnabled = holidayOn
        workplace.holidayWage = min(100_000, max(0, Int(holidayText.filter(\.isNumber)) ?? 0))
        workplace.setHolidayWeekdays(holidayDays)
        workplace.nightPayEnabled = nightOn && !payIsDaily
        workplace.nightWage = min(100_000, max(0, Int(nightText.filter(\.isNumber)) ?? 0))
        workplace.nightStartMinutes = nightStart
        workplace.nightEndMinutes = nightEnd
        workplace.holidayNightEnabled = holidayNightOn && holidayOn && !payIsDaily
        workplace.holidayNightWage = min(100_000, max(0, Int(holidayNightText.filter(\.isNumber)) ?? 0))
        workplace.holidayNightStartMinutes = holidayNightStart
        workplace.holidayNightEndMinutes = holidayNightEnd
        workplace.overtimeEnabled = overtimeOn
        workplace.overtimeAfterMinutes = overtimeHours * 60
        workplace.overtimePerHour = overtimePerHour
        workplace.overtimeExtra = min(100_000, max(0, Int(overtimeText.filter(\.isNumber)) ?? 0))
        workplace.customBreaks = customBreaks
        workplace.breakRules = breakRules
        workplace.roundingUnitMinutes = roundingUnit
        workplace.roundingStartRaw = roundingStart
        workplace.roundingEndRaw = roundingEnd
        workplace.nightRatePercent = nightRate
        workplace.overtimeRatePercent = overtimeRate
        workplace.setHolidayRatePercents(holidayRates)
        workplace.wageHistory = wageHistory
        workplace.payRuleDates = payRuleDates
        workplace.wageBands = wageBands
        do {
            try context.save()
        } catch {
            self.error = "保存できませんでした。もう一度試してください。"
            return
        }
        dismiss()
    }

    private func yen(_ text: String) -> Int {
        min(100_000, max(0, Int(text.filter(\.isNumber)) ?? 0))
    }

    private var weekdayPicker: some View {
        let names = ["", "日", "月", "火", "水", "木", "金", "土"]
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = holidayDays.contains(day)
                Button {
                    if on { holidayDays.remove(day) } else { holidayDays.insert(day) }
                } label: {
                    Text(names[day])
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(on ? Theme.ink : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Theme.lime : Theme.cardRaised)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, number: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                if number {
                    Text("¥")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                TextField(title, text: text)
                    .keyboardType(number ? .numberPad : .default)
                    .accessibilityIdentifier("field.\(title)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .focused($typing)
            }
        }
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 12)
    }
}

struct ShiftOverlapList: View {
    var hits: [ShiftOverlap.Hit]
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("保存せず編集に戻ります")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(hits) { hit in
                    Text(ShiftOverlap.row(hit))
                        .designFont(16)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                LimeCapsuleButton(title: "このまま保存", fillWidth: true, designSize: 16, action: onSave)
                    .padding(.top, 8)
                Button("やめる", action: onCancel)
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .background(Theme.background)
            .navigationTitle("このシフトは確認が必要です")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる", action: onCancel)
                        .foregroundStyle(Theme.ink)
                }
            }
            .darkSheet()
        }
        .presentationDetents([.medium, .large])
    }
}
