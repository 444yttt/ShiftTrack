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
            ScreenScroll {
                Text("パターン")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .accessibilityIdentifier("patterns.heading")
                Text("パターンは曜日のひな形です。ここを保存してもシフトは増えません。入れると、空いている日だけシフトになります。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if visiblePatterns.isEmpty {
                    Text("パターンはまだありません。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    VStack(spacing: 10) {
                        ForEach(visiblePatterns) { pattern in
                            patternCard(pattern)
                        }
                    }
                    .padding(.top, 8)
                }

                LimeCapsuleButton(title: "パターンを作る", fillWidth: true) {
                    editor = PatternRoute(patternID: nil)
                }
                .padding(.top, 8)
                .disabled(workplaces.isEmpty)
                if workplaces.isEmpty {
                    Text("先に勤務先を1件追加してください。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .background(Theme.background)
            .navigationTitle("パターン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.lime)
                        .accessibilityIdentifier("patterns.close")
                }
            }
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(workplace?.color ?? Theme.lime)
                    .frame(width: 10, height: 10)
                Text(pattern.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            Text("\(workplace?.name ?? "勤務先なし")  \(ShiftPatternPlan.weekdayLabel(pattern.weekdays))  \(Formatters.clock(pattern.startMinutes))–\(Formatters.clock(pattern.endMinutes))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 16) {
                Button("編集") { editor = PatternRoute(patternID: pattern.uuid) }
                    .foregroundStyle(Theme.lime)
                Button("この曜日に入れる") { apply = PatternRoute(patternID: pattern.uuid) }
                    .foregroundStyle(Theme.lime)
                    .disabled(workplace == nil)
            }
            .font(.system(size: 13, weight: .bold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var error = ""
    @State private var confirmDelete = false
    @State private var overlap: [ShiftOverlap.Hit] = []
    @State private var overlapSheet = false
    @AppStorage("settings.travelMinutes") private var travelMinutes = 30

    private var existing: ShiftPattern? { patterns.first { $0.uuid == patternID } }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("これはひな形です。保存しても、入っているシフトの時間と休憩は変わりません。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                field
                Picker("勤務先", selection: $workplaceID) {
                    Text("選ぶ").tag(UUID?.none)
                    ForEach(workplaces) { workplace in
                        Text(workplace.name).tag(Optional(workplace.uuid))
                    }
                }
                .tint(Theme.lime)
                HStack(alignment: .top, spacing: 10) {
                    MinutesTimePicker(title: "開始", minutes: $startMinutes)
                    MinutesTimePicker(title: "終了", minutes: $endMinutes)
                }
                Stepper(value: $breakMinutes, in: 0...300) {
                    Text("休憩 \(breakMinutes)分")
                        .foregroundStyle(Theme.ink)
                }
                Text("入れる曜日")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                WeekdaySelector(days: $weekdays)
                ForEach(liveOverlap) { hit in
                    Text(ShiftOverlap.row(hit))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.behind)
                }
                LimeCapsuleButton(title: existing == nil ? "パターンを保存" : "変更を保存", fillWidth: true) { save() }
                if existing != nil {
                    Button("パターンを削除") { confirmDelete = true }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity)
                    Text("削除しても、すでに入っているシフトは残ります。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .background(Theme.background)
            .navigationTitle(existing == nil ? "パターンを作る" : "パターンを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
            }
            .onAppear(perform: load)
            .alert("このパターンを削除しますか？入っているシフトは削除しません。", isPresented: $confirmDelete) {
                Button("削除", role: .destructive, action: deletePattern)
                Button("キャンセル", role: .cancel) {}
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

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("名前")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("早番", text: $name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
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
            existing.weekdays = weekdays
        } else {
            context.insert(ShiftPattern(
                name: trimmed,
                workplaceUUID: workplaceID,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                breakMinutes: breakMinutes,
                weekdays: weekdays
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
            ScreenScroll {
                Text(pattern?.name ?? "パターン")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("選んだ期間の、パターンの曜日だけを見ます。同じ勤務先のシフトが既にある日は作りません。時間も休憩も書き換えません。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DatePicker("開始日", selection: $start, displayedComponents: .date)
                    .tint(Theme.lime)
                DatePicker("終了日", selection: $end, displayedComponents: .date)
                    .tint(Theme.lime)
                Text(summary(result))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("作ったシフトは給料の見込に入ります。希望ではありません。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.behind)
                }
                if let savedCount {
                    Text("\(savedCount)件入れました。")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.lime)
                }
                LimeCapsuleButton(title: "空いている日に入れる", fillWidth: true) {
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
            .background(Theme.background)
            .navigationTitle("曜日に入れる")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
            }
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
            breakMinutes: pattern.breakMinutes,
            from: start,
            through: end,
            weekdays: pattern.weekdays,
            occupied: occupied,
            allowEqualClock: workplace.payIsDaily
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
                breakFollowsRules: false,
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
    @State private var error = ""
    @State private var showPlanner = false

    init(route: RequestRoute) {
        self.route = route
        _date = State(initialValue: Calendar.current.startOfDay(for: route.date))
    }

    private var existing: ShiftRequest? { requests.first { $0.uuid == route.requestID } }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("希望はシフトではありません。給料の見込にも、今日の予定全体の時給分にも入りません。シフトにするまで金額は動きません。")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DatePicker("日付", selection: $date, displayedComponents: .date)
                    .tint(Theme.lime)
                Picker("勤務先", selection: $workplaceID) {
                    Text("未定").tag(UUID?.none)
                    ForEach(workplaces) { workplace in
                        Text(workplace.name).tag(Optional(workplace.uuid))
                    }
                }
                .tint(Theme.lime)
                HStack(alignment: .top, spacing: 10) {
                    MinutesTimePicker(title: "開始", minutes: $startMinutes)
                    MinutesTimePicker(title: "終了", minutes: $endMinutes)
                }
                Stepper(value: $breakMinutes, in: 0...300) {
                    Text("休憩 \(breakMinutes)分")
                        .designFont(16, weight: .bold)
                        .foregroundStyle(Theme.ink)
                }
                TextField("メモ", text: $note)
                    .designFont(16)
                    .foregroundStyle(Theme.ink)
                if !error.isEmpty {
                    Text(error)
                        .designFont(13)
                        .foregroundStyle(Theme.behind)
                }
                Text(note.isEmpty ? "予定はありません" : note)
                    .designFont(20)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text("出勤")
                    Text("休み")
                    Text("時間指定")
                }
                .designFont(16, weight: .bold)
                Button("クリア") {
                    note = ""
                    startMinutes = 9 * 60
                    endMinutes = 17 * 60
                }
                .designFont(13, weight: .bold)
                Button("テキスト生成") { showPlanner = true }
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.lime)
                    .clipShape(Capsule())
                LimeCapsuleButton(title: "希望を保存", fillWidth: true, designSize: 16, action: save)
                if existing?.isOpen == true {
                    LimeCapsuleButton(title: "シフトにする", fillWidth: true, designSize: 16, action: accept)
                    Button("希望を見送る") { decline() }
                        .designFont(13, weight: .bold)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            .background(Theme.background)
            .navigationTitle("希望")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showPlanner) {
                RequestPlannerView(month: date)
            }
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
            if existing.statusRaw.isEmpty { existing.statusRaw = ShiftRequestStatus.open }
        } else {
            context.insert(ShiftRequest(
                date: day,
                startMinutes: startMinutes,
                endMinutes: endMinutes,
                breakMinutes: breakMinutes,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                workplaceUUID: workplaceID
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

struct WeekdaySelector: View {
    @Binding var days: Set<Int>

    var body: some View {
        let names = ["", "日", "月", "火", "水", "木", "金", "土"]
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
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
                .accessibilityLabel(names[day])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
