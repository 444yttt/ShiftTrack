import SwiftData
import SwiftUI

struct PatternListView: View {
    var onlyWorkplaceID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShiftPattern.createdAt) private var patterns: [ShiftPattern]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @State private var editor: PatternRoute?
    @State private var apply: PatternRoute?

    private var visiblePatterns: [ShiftPattern] {
        guard let onlyWorkplaceID else { return patterns }
        return patterns.filter { $0.workplaceUUID == onlyWorkplaceID }
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: "曜日の型です。型を保存してもシフトは増えません。「この曜日に入れる」で期間を選ぶと、空いている日だけシフトになります。")
                    .padding(.top, Space.xs)
                    .accessibilityIdentifier("patterns.heading")
                if visiblePatterns.isEmpty {
                    EmptyState(systemImage: "repeat", message: "曜日の型はまだありません")
                } else {
                    ForEach(visiblePatterns) { pattern in
                        patternCard(pattern)
                    }
                }
                PrimaryButton(title: "型を作る", systemImage: "plus", identifier: "patterns.add") {
                    editor = PatternRoute(patternID: nil)
                }
                .disabled(workplaces.isEmpty)
                if workplaces.isEmpty {
                    InfoNote(text: "先に勤務先を1件登録してください。", tone: .warning)
                }
            }
            .background(Theme.paper)
            .navigationTitle("曜日でまとめて入れる")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("patterns.close")
                }
            }
            .darkSheet()
            .sheet(item: $editor) { route in
                PatternEditorView(patternID: route.patternID)
            }
            .sheet(item: $apply) { route in
                if let patternID = route.patternID {
                    PatternApplyView(patternID: patternID)
                }
            }
        }
    }

    private func patternCard(_ pattern: ShiftPattern) -> some View {
        let workplace = workplaces.first { $0.uuid == pattern.workplaceUUID }
        return Card(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(workplace?.color ?? Theme.signal)
                    .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(pattern.name)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            Text("\(workplace?.name ?? "勤務先なし")・\(ShiftPatternPlan.weekdayLabel(pattern.weekdays))・\(Formatters.clock(pattern.startMinutes))–\(Formatters.clock(pattern.endMinutes))")
                .font(AppFont.helper.monospacedDigit())
                .foregroundStyle(Theme.ink2)
            Text(PatternBreak.summary(modeRaw: pattern.breakModeRaw, fixedMinutes: pattern.breakMinutes, customRulesRaw: pattern.breakRulesRaw))
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
            HStack(spacing: Space.xs) {
                SecondaryButton(title: "編集", systemImage: "pencil", fillWidth: false, identifier: "patterns.edit.\(pattern.name)") {
                    editor = PatternRoute(patternID: pattern.uuid)
                }
                PrimaryButton(title: "この曜日に入れる", identifier: "patterns.apply.\(pattern.name)") {
                    apply = PatternRoute(patternID: pattern.uuid)
                }
                .disabled(workplace == nil)
            }
        }
    }
}

struct PatternRoute: Identifiable {
    var id: String { patternID?.uuidString ?? "new" }
    var patternID: UUID?
}

struct PatternEditorView: View {
    var patternID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ShiftPattern.createdAt) private var patterns: [ShiftPattern]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var shifts: [WorkShift]

    @State private var name = ""
    @State private var workplaceID: UUID?
    @State private var startMinutes = 9 * 60
    @State private var endMinutes = 18 * 60
    @State private var breakMinutes = 60
    @State private var breakModeRaw = PatternBreakMode.fixed.rawValue
    @State private var breakRules: [InOutRecovered.BreakRule] = []
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var error = ""
    @State private var confirmDelete = false
    @State private var overlap: [ShiftOverlap.Hit] = []
    @State private var overlapSheet = false
    @AppStorage("settings.travelMinutes") private var travelMinutes = 30

    private var existing: ShiftPattern? { patterns.first { $0.uuid == patternID } }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: "これは型です。保存しても、入っているシフトの時間と休憩は変わりません。")
                    .padding(.top, Space.xs)
                Card {
                    LabeledField(label: "型の名前（必須）", text: $name, prompt: "例：早番", identifier: "field.型の名前")
                    PickerRow(label: "勤務先", selection: $workplaceID, identifier: "template.workplace") {
                        Text("選んでください").tag(UUID?.none)
                        ForEach(workplaces) { workplace in
                            Text(workplace.name).tag(Optional(workplace.uuid))
                        }
                    }
                    WeekdayPicker(label: "入れる曜日", days: $weekdays)
                }
                SectionHeader(title: "時間")
                Card {
                    HStack(alignment: .top, spacing: Space.xs) {
                        MinutesTimePicker(title: "開始", minutes: $startMinutes)
                        MinutesTimePicker(title: "終了", minutes: $endMinutes)
                    }
                    ForEach(liveOverlap) { hit in
                        InfoNote(text: ShiftOverlap.row(hit), tone: .warning)
                    }
                }
                SectionHeader(title: "休憩")
                Card {
                    PatternBreakEditor(modeRaw: $breakModeRaw, fixedMinutes: $breakMinutes, rules: $breakRules)
                }
                if !error.isEmpty {
                    InfoNote(text: error, tone: .error)
                }
                PrimaryButton(title: existing == nil ? "型を保存" : "変更を保存", identifier: "template.save") { save() }
                if existing != nil {
                    DestructiveButton(title: "この型を削除", identifier: "template.delete") { confirmDelete = true }
                    InfoNote(text: "削除しても、すでに入っているシフトは残ります。")
                }
            }
            .background(Theme.paper)
            .navigationTitle(existing == nil ? "曜日の型を作る" : "曜日の型を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onAppear(perform: load)
            .alert("この型を削除しますか？", isPresented: $confirmDelete) {
                Button("削除", role: .destructive, action: deletePattern)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("入っているシフトは削除しません。")
            }
            .alert("このシフトは確認が必要です", isPresented: overlapAlert) {
                Button("このまま保存") {
                    overlap = []
                    save(force: true)
                }
                Button("やめる", role: .cancel) { overlap = [] }
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
        }
    }

    private var overlapAlert: Binding<Bool> {
        Binding(get: { overlap.count == 1 && !overlapSheet }, set: { if !$0 { overlap = [] } })
    }

    private var liveOverlap: [ShiftOverlap.Hit] {
        guard let workplaceID else { return [] }
        let calendar = ShiftOverlap.tokyo
        let workplace = workplaces.first { $0.uuid == workplaceID }
        let proposed = ShiftOverlap.upcoming(weekdays: weekdays, from: .now, calendar: calendar).enumerated().map { index, day in
            ShiftOverlap.span(
                id: "template-\(index)",
                name: workplace?.name ?? "シフト",
                workplace: workplaceID,
                day: day,
                start: startMinutes,
                end: endMinutes,
                calendar: calendar
            )
        }
        return ShiftOverlap.conflicts(
            batch: proposed,
            existing: shifts.map { ShiftOverlap.span(from: $0, calendar: calendar) },
            travelMinutes: travelMinutes,
            calendar: calendar
        )
    }

    private func load() {
        guard let existing else {
            workplaceID = workplaces.first?.uuid
            return
        }
        name = existing.name
        workplaceID = existing.workplaceUUID
        startMinutes = existing.startMinutes
        endMinutes = existing.endMinutes
        breakMinutes = existing.breakMinutes
        breakModeRaw = existing.breakModeRaw
        breakRules = BreakRules.decode(existing.breakRulesRaw)
        weekdays = existing.weekdays
    }

    private func save(force: Bool = false) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "名前を入力してください"
            return
        }
        guard let workplaceID else {
            error = "勤務先を選んでください"
            return
        }
        guard !weekdays.isEmpty else {
            error = "曜日を1つ選んでください"
            return
        }
        let workplace = workplaces.first { $0.uuid == workplaceID }
        if workplace?.payIsDaily != true, ShiftDatePolicy.clockMinutes(startMinutes) == ShiftDatePolicy.clockMinutes(endMinutes) {
            error = "開始と終了が同じです。日給の勤務先以外は保存できません。"
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
        error = ""
        if let existing {
            existing.name = trimmed
            existing.workplaceUUID = workplaceID
            existing.startMinutes = startMinutes
            existing.endMinutes = endMinutes
            existing.breakMinutes = breakMinutes
            existing.breakModeRaw = breakModeRaw
            existing.breakRulesRaw = BreakRules.encode(breakRules)
            existing.weekdays = weekdays
        } else {
            context.insert(ShiftPattern(
                name: trimmed,
                workplaceUUID: workplaceID,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                breakMinutes: breakMinutes,
                weekdays: weekdays,
                breakModeRaw: breakModeRaw,
                breakRulesRaw: BreakRules.encode(breakRules)
            ))
        }
        do {
            try context.save()
        } catch {
            self.error = "保存できませんでした。もう一度試してください。"
            return
        }
        dismiss()
    }

    private func deletePattern() {
        guard let existing else { return }
        context.delete(existing)
        try? context.save()
        dismiss()
    }
}

struct PatternApplyView: View {
    var patternID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ShiftPattern.createdAt) private var patterns: [ShiftPattern]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]

    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.date(byAdding: .day, value: 27, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var message = ""
    @State private var savedCount: Int?
    @State private var overlap: [ShiftOverlap.Hit] = []
    @State private var overlapSheet = false
    @AppStorage("settings.travelMinutes") private var travelMinutes = 30

    private var pattern: ShiftPattern? { patterns.first { $0.uuid == patternID } }
    private var workplace: Workplace? {
        guard let pattern else { return nil }
        return workplaces.first { $0.uuid == pattern.workplaceUUID }
    }

    var body: some View {
        let result = currentResult
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                Card {
                    Text(pattern?.name ?? "型")
                        .font(AppFont.screenTitle)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    InfoNote(text: "選んだ期間のうち、型の曜日だけを見ます。同じ勤務先のシフトがすでにある日は作りません。入っているシフトの時間や休憩は変えません。")
                }
                .padding(.top, Space.xs)
                SectionHeader(title: "期間")
                Card {
                    DatePicker(selection: $start, displayedComponents: .date) {
                        Text("最初の日")
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.signalInk)
                    .frame(minHeight: 44)
                    RowDivider()
                    DatePicker(selection: $end, displayedComponents: .date) {
                        Text("最後の日")
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.signalInk)
                    .frame(minHeight: 44)
                }
                Card {
                    Text(summary(result))
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    InfoNote(text: "作ったシフトは給料の見込みに入ります。希望ではありません。")
                }
                if !message.isEmpty {
                    InfoNote(text: message, tone: .error)
                }
                if let savedCount {
                    InfoNote(text: "\(savedCount)件入れました。", systemImage: "checkmark.circle")
                }
                PrimaryButton(title: "空いている日に入れる", identifier: "template.apply") {
                    apply(result)
                }
                .disabled(result.create.isEmpty)
            }
            .alert("このシフトは確認が必要です", isPresented: overlapAlert) {
                Button("このまま保存") {
                    let pending = overlap
                    overlap = []
                    if !pending.isEmpty { apply(currentResult, force: true) }
                }
                Button("やめる", role: .cancel) { overlap = [] }
            } message: {
                Text(ShiftOverlap.confirmMessage(overlap))
            }
            .sheet(isPresented: $overlapSheet) {
                ShiftOverlapList(hits: overlap, onSave: {
                    let pending = overlap
                    overlapSheet = false
                    overlap = []
                    if !pending.isEmpty { apply(currentResult, force: true) }
                }, onCancel: {
                    overlapSheet = false
                    overlap = []
                })
            }
            .background(Theme.paper)
            .navigationTitle("型を曜日に入れる")
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

    private var currentResult: ShiftPatternPlan.Result {
        guard let pattern, let workplace else {
            return ShiftPatternPlan.Result(create: [], skippedExisting: 0, blockedEqualClock: false)
        }
        let occupied = shifts.compactMap { shift -> ShiftPatternPlan.Occupied? in
            guard let id = shift.workplace?.uuid else { return nil }
            return ShiftPatternPlan.Occupied(day: shift.date, workplaceID: id)
        }
        return ShiftPatternPlan.proposals(
            workplaceID: workplace.uuid,
            startMinutes: pattern.startMinutes,
            endMinutes: pattern.endMinutes,
            breakMinutes: resolvedBreak?.minutes ?? pattern.breakMinutes,
            from: start,
            through: end,
            weekdays: pattern.weekdays,
            occupied: occupied,
            allowEqualClock: workplace.payIsDaily
        )
    }

    private var resolvedBreak: PatternBreak.Result? {
        guard let pattern else { return nil }
        return PatternBreak.resolve(
            modeRaw: pattern.breakModeRaw,
            fixedMinutes: pattern.breakMinutes,
            customRulesRaw: pattern.breakRulesRaw,
            startMinutes: pattern.startMinutes,
            endMinutes: pattern.endMinutes,
            workplace: workplace
        )
    }

    private func summary(_ result: ShiftPatternPlan.Result) -> String {
        if workplace == nil { return "勤務先がないので入れられません。" }
        if result.blockedEqualClock { return "開始と終了が同じなので入れられません。" }
        if ShiftPatternPlan.spanDays(from: start, through: end) == nil {
            return "期間は終了が開始以降で、366日以内にしてください。"
        }
        return "新しく\(result.create.count)件。既にあるので作らない日が\(result.skippedExisting)日。"
    }

    private var overlapAlert: Binding<Bool> {
        Binding(get: { overlap.count == 1 && !overlapSheet }, set: { if !$0 { overlap = [] } })
    }

    private func apply(_ result: ShiftPatternPlan.Result, force: Bool = false) {
        guard let workplace, !result.create.isEmpty else { return }
        if !force {
            let calendar = ShiftOverlap.tokyo
            let proposed = result.create.enumerated().map { index, proposal in
                ShiftOverlap.span(
                    id: "new-\(index)",
                    name: workplace.name,
                    workplace: workplace.uuid,
                    day: proposal.day,
                    start: proposal.startMinutes,
                    end: proposal.endMinutes,
                    calendar: calendar
                )
            }
            let found = ShiftOverlap.conflicts(
                batch: proposed,
                existing: shifts.map { ShiftOverlap.span(from: $0, calendar: calendar) },
                travelMinutes: travelMinutes,
                calendar: calendar
            )
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
        for proposal in result.create {
            context.insert(WorkShift(
                date: proposal.day,
                startMinutes: proposal.startMinutes,
                endMinutes: proposal.endMinutes,
                breakMinutes: proposal.breakMinutes,
                breakFollowsRules: resolvedBreak?.followsRules ?? false,
                workplace: workplace
            ))
        }
        do {
            try context.save()
        } catch {
            message = "保存できませんでした。もう一度試してください。"
            return
        }
        savedCount = result.create.count
        message = ""
    }
}

struct RequestRoute: Identifiable {
    var id: String { "\(requestID?.uuidString ?? "new")-\(date.timeIntervalSinceReferenceDate)" }
    var requestID: UUID?
    var date: Date
}

struct RequestEditorView: View {
    var route: RequestRoute
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ShiftRequest.date) private var requests: [ShiftRequest]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]

    @State private var date: Date
    @State private var workplaceID: UUID?
    @State private var startMinutes = 9 * 60
    @State private var endMinutes = 17 * 60
    @State private var breakMinutes = 60
    @State private var note = ""
    @State private var kind = ShiftRequestKind.hopedAttendance
    @State private var error = ""

    init(route: RequestRoute) {
        self.route = route
        _date = State(initialValue: Calendar.current.startOfDay(for: route.date))
    }

    private var existing: ShiftRequest? { requests.first { $0.uuid == route.requestID } }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: "シフト希望は、出したい希望を残しておくメモです。シフトではないので、「シフトにする」まで給料の見込みには入りません。")
                    .padding(.top, Space.xs)
                Card {
                    SegmentedRow(label: "希望の種類", selection: $kind, identifier: "request.kind") {
                        Text("出勤したい").tag(ShiftRequestKind.hopedAttendance)
                        Text("休みたい").tag(ShiftRequestKind.hopedRest)
                    }
                    DatePicker(selection: $date, displayedComponents: .date) {
                        Text("日付")
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.signalInk)
                    .frame(minHeight: 44)
                    PickerRow(label: "勤務先", selection: $workplaceID, identifier: "request.workplace") {
                        Text("未定").tag(UUID?.none)
                        ForEach(workplaces) { workplace in
                            Text(workplace.name).tag(Optional(workplace.uuid))
                        }
                    }
                }
                if kind == ShiftRequestKind.hopedAttendance {
                    SectionHeader(title: "入りたい時間")
                    Card {
                        HStack(alignment: .top, spacing: Space.xs) {
                            MinutesTimePicker(title: "開始", minutes: $startMinutes)
                            MinutesTimePicker(title: "終了", minutes: $endMinutes)
                        }
                        StepperRow(
                            label: "休憩",
                            valueText: breakMinutes == 0 ? "なし" : "\(breakMinutes)分",
                            value: $breakMinutes,
                            range: 0...300,
                            step: 15,
                            identifier: "request.break"
                        )
                    }
                }
                Card {
                    LabeledField(label: "メモ（任意）", text: $note, prompt: "例：午前だけなら入れます", identifier: "request.note", multiline: true)
                }
                monthLists
                if !error.isEmpty {
                    InfoNote(text: error, tone: .error)
                }
                PrimaryButton(title: "希望を保存", identifier: "request.save", action: save)
                if existing?.isOpen == true {
                    if kind == ShiftRequestKind.hopedAttendance {
                        SecondaryButton(title: "この希望をシフトにする", systemImage: "arrow.right.circle", identifier: "request.accept", action: accept)
                    }
                    DestructiveButton(title: kind == ShiftRequestKind.hopedRest ? "この希望を消す" : "この希望を見送る", identifier: "request.decline") { decline() }
                }
            }
            .background(Theme.paper)
            .navigationTitle("シフト希望")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let existing else { return }
        date = existing.date
        workplaceID = existing.workplaceUUID
        startMinutes = existing.startMinutes
        endMinutes = existing.endMinutes
        breakMinutes = existing.breakMinutes
        note = existing.note
        kind = existing.kindRaw
    }

    private var monthLists: some View {
        let calendar = Calendar.current
        let items = requests.map {
            ShiftRequestLists.Item(id: $0.uuid, date: $0.date, kind: $0.kindRaw)
        }
        let pair: ShiftRequestLists.Pair = {
            guard let month = ShiftRequestLists.month(containing: date, calendar: calendar) else {
                return ShiftRequestLists.Pair(attendance: [], rest: [])
            }
            return ShiftRequestLists.split(items, month: month)
        }()
        return Card(spacing: Space.xs) {
            Text("\(calendar.component(.month, from: date))月の希望")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
            ValueRow(title: "出勤したい", value: "\(pair.attendance.count)件")
            ValueRow(title: "休みたい", value: "\(pair.rest.count)件")
        }
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: date)
        if let existing {
            existing.date = day
            existing.workplaceUUID = workplaceID
            existing.startMinutes = startMinutes
            existing.endMinutes = endMinutes
            existing.breakMinutes = breakMinutes
            existing.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.kindRaw = kind
            if existing.statusRaw.isEmpty { existing.statusRaw = ShiftRequestStatus.open }
        } else {
            context.insert(ShiftRequest(
                date: day,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                breakMinutes: breakMinutes,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                workplaceUUID: workplaceID,
                kindRaw: kind
            ))
        }
        do {
            try context.save()
        } catch {
            self.error = "保存できませんでした。もう一度試してください。"
            return
        }
        dismiss()
    }

    private func accept() {
        guard let existing, existing.isOpen else { return }
        guard let workplaceID, let workplace = workplaces.first(where: { $0.uuid == workplaceID }) else {
            error = "勤務先を選んでください"
            return
        }
        let start = ShiftDatePolicy.clockMinutes(startMinutes)
        let end = ShiftDatePolicy.clockMinutes(endMinutes)
        if !workplace.payIsDaily, start == end {
            error = "開始と終了が同じです。シフトにはしていません。"
            return
        }
        let taken = shifts.contains { shift in
            shift.workplace?.uuid == workplace.uuid && Calendar.current.isDate(shift.date, inSameDayAs: date)
        }
        if taken {
            error = "この日には同じ勤務先のシフトがあります。既存のシフトは変えていません。"
            return
        }
        existing.date = Calendar.current.startOfDay(for: date)
        existing.workplaceUUID = workplace.uuid
        existing.startMinutes = start
        existing.endMinutes = end
        existing.breakMinutes = breakMinutes
        context.insert(WorkShift(
            date: existing.date,
            startMinutes: start,
            endMinutes: end,
            breakMinutes: min(24 * 60, max(0, breakMinutes)),
            notes: existing.note,
            breakFollowsRules: false,
            workplace: workplace
        ))
        existing.statusRaw = ShiftRequestStatus.accepted
        do {
            try context.save()
        } catch {
            self.error = "保存できませんでした。もう一度試してください。"
            return
        }
        dismiss()
    }

    private func decline() {
        guard let existing else { return }
        existing.statusRaw = ShiftRequestStatus.declined
        try? context.save()
        dismiss()
    }
}

/// Seven weekday chips, Sunday first (1...7). Selected chips are ink with white text.
struct WeekdaySelector: View {
    @Binding var days: Set<Int>

    var body: some View {
        let names = ["", "日", "月", "火", "水", "木", "金", "土"]
        HStack(spacing: Space.xxs) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(names[day])
                        .font(AppFont.label)
                        .foregroundStyle(on ? Color.white : Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.ink : Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? Theme.ink : Theme.stroke, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(names[day])曜日")
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}
