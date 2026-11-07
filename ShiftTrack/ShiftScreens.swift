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
                    .foregroundStyle(.white)
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
                        .font(.system(size: 14))
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
                LimeCapsuleButton(title: "+ この日に追加", fillWidth: true) {
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
        lines.append("追加すると、この画面を閉じてマイシフトに出します。")
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
                .foregroundStyle(.white)
            Text(tableHint)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $tableText)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
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
                        .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
                                    .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
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
        return "\(when)  \(Formatters.clock(draft.startMinutes))–\(Formatters.clock(draft.endMinutes))  休憩\(draft.breakMinutes)分"
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
            guard PayMath.workedMinutes(
                start: draft.startMinutes,
                end: draft.endMinutes,
                breakMinutes: draft.breakMinutes
            ) > 0 else { continue }
            guard let workplace = workplace(
                named: draft.workplaceName,
                wage: wage,
                transport: transport,
                created: &created
            ) else { continue }
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
                breakMinutes: draft.breakMinutes,
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

struct ShiftEditorView: View {
    var route: EditorRoute
    var onSaved: ((Date) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]
    @Query private var shifts: [WorkShift]

    @State private var workplaceID: UUID?
    @State private var date = Date()
    @State private var startMinutes = 10 * 60
    @State private var endMinutes = 15 * 60
    @State private var breakMinutes = 0
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
    @FocusState private var typing: Bool

    private var existing: WorkShift? { shifts.first { $0.uuid == route.shiftID } }
    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }
    private var selectedWorkplace: Workplace? { workplaces.first { $0.uuid == workplaceID } }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                if workplaces.isEmpty {
                    Text("先に勤務先を追加してください。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                    LimeCapsuleButton(title: "勤務先を追加", fillWidth: true) {
                        showWorkplaceCreator = true
                    }
                    .padding(.top, 12)
                } else {
                    formCard {
                        labeled("勤務先") {
                            if existing != nil {
                                Text(selectedWorkplace?.name ?? "なし")
                                    .font(.system(size: 16, weight: .bold))
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
                                    .foregroundStyle(.white)
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
                        if selectedWorkplace?.payIsDaily == true {
                            Text("日給の勤務先では、休憩時間は給料から引きません。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        } else {
                            BreakMinutesControl(minutes: $breakMinutes, range: 0...600)
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
                            .font(.system(size: 14))
                            .focused($typing)
                        divider
                        TextField("メモ", text: $notes, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .focused($typing)
                    }
                    if let workplace = selectedWorkplace {
                        let amount = PayMath.quote(
                            workplace: workplace,
                            day: date,
                            start: startMinutes,
                            end: endMinutes,
                            breakMinutes: selectedWorkplace?.payIsDaily == true ? 0 : breakMinutes,
                            customPay: parsedCustom,
                            adjustment: parsedAdjustment,
                            includeTransport: includeTransport
                        )
                        Text("給料 \(Formatters.yen(amount))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.lime)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !shownError.isEmpty {
                        Text(shownError)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.behind)
                    }
                    LimeCapsuleButton(title: existing == nil ? "完了する" : "保存する", fillWidth: true) { save() }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.4)
                        .padding(.top, 8)
                    if existing != nil {
                        Button("削除する") { confirmDelete = true }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(existing == nil ? "シフトを追加" : "シフトの詳細")
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
            .onChange(of: workplaces.map(\.uuid)) { _, ids in
                if let workplaceID, ids.contains(workplaceID) { return }
                self.workplaceID = workplaces.last?.uuid
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
            breakMinutes = existing.breakMinutes
            notes = existing.notes
            customText = existing.customPay.map(String.init) ?? ""
            adjustmentText = existing.adjustmentYen == 0 ? "" : String(existing.adjustmentYen)
            adjustmentNote = existing.adjustmentNote
        } else {
            workplaceID = route.workplaceID ?? workplaces.first?.uuid
            date = route.date
        }
    }

    private func save() {
        guard let workplace = selectedWorkplace else {
            error = "勤務先を選んでください"
            return
        }
        let storedBreak = workplace.payIsDaily ? 0 : breakMinutes
        let minutes = PayMath.workedMinutes(start: startMinutes, end: endMinutes, breakMinutes: storedBreak)
        guard workplace.payIsDaily || minutes > 0 else {
            error = "終了時刻が開始と同じにならないようにしてください"
            return
        }
        let storedDate = ShiftDatePolicy.dateToStore(
            existing: existing?.date,
            draft: date,
            userEditedDate: userEditedDate
        )
        if let existing {
            existing.date = storedDate
            existing.startMinutes = startMinutes
            existing.endMinutes = endMinutes
            existing.breakMinutes = storedBreak
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
                workplace: workplace
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

    private var draftMinutes: Int {
        PayMath.workedMinutes(
            start: startMinutes,
            end: endMinutes,
            breakMinutes: selectedWorkplace?.payIsDaily == true ? 0 : breakMinutes
        )
    }

    private var canSave: Bool {
        guard selectedWorkplace != nil else { return false }
        if selectedWorkplace?.payIsDaily == true { return true }
        return draftMinutes > 0
    }

    private var shownError: String {
        if !error.isEmpty { return error }
        guard selectedWorkplace != nil else { return workplaces.isEmpty ? "" : "勤務先を選んでください" }
        if selectedWorkplace?.payIsDaily != true, draftMinutes == 0 {
            return "終了時刻が開始と同じにならないようにしてください"
        }
        return ""
    }

    private func yenField(_ prompt: String, text: Binding<String>, signed: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text("¥")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.muted)
            TextField(prompt, text: text)
                .keyboardType(signed ? .numbersAndPunctuation : .numberPad)
                .font(.system(size: 16, weight: .bold))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            content()
                .foregroundStyle(.white)
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
                    .foregroundStyle(.white)
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
                    minutes = ShiftDatePolicy.clockMinutes(draft)
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
                    .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
            let next = minutes + delta
            minutes = min(range.upperBound, max(range.lowerBound, next))
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
    @State private var closingDay = 0
    @State private var paydayOffset = 0
    @State private var paydayDay = 0
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
                    Text("マイシフトでの表示色")
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
                    Text("給料は、働いた月ではなく給料日の月に集計されます。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
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
                                    .foregroundStyle(.white)
                            }
                            Picker("金額の単位", selection: $overtimePerHour) {
                                Text("1時間あたり").tag(true)
                                Text("1シフトあたり").tag(false)
                            }
                            .tint(Theme.lime)
                            field("追加金額", text: $overtimeText, number: true)
                        }
                    }
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
            closingDay = existing.closingDay
            paydayOffset = existing.paydayMonthOffset
            paydayDay = existing.paydayDay
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
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
        guard !trimmed.isEmpty else {
            error = "名前を入力してください"
            return
        }
        let wage = min(100_000, max(0, Int(wageText.filter(\.isNumber)) ?? 0))
        let daily = min(100_000, max(0, Int(dailyText.filter(\.isNumber)) ?? 0))
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
        workplace.closingDay = closingDay
        workplace.paydayMonthOffset = paydayOffset
        workplace.paydayDay = paydayDay
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
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
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
