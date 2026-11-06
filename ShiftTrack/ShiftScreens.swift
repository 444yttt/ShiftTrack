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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkShift.date, order: .reverse) private var shifts: [WorkShift]
    @State private var editor: EditorRoute?

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

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text(Formatters.longDay(day))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LimeCapsuleButton(title: "新規にシフトを入力する", fillWidth: true) {
                    editor = EditorRoute(shiftID: nil, date: day, workplaceID: workplaceID)
                }
                .padding(.top, 8)
                Text("履歴から追加")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                if history.isEmpty {
                    Text("まだ履歴がありません。新しく入力すると、次から日付を選ぶだけで追加できます。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 10) {
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
            }
            .background(Theme.background)
            .navigationTitle("シフトを追加")
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

    private func add(_ source: WorkShift) {
        guard let workplace = source.workplace else { return }
        let shift = WorkShift(
            date: day,
            startMinutes: source.startMinutes,
            endMinutes: source.endMinutes,
            breakMinutes: source.breakMinutes,
            workplace: workplace
        )
        context.insert(shift)
        try? context.save()
        dismiss()
    }
}

struct ShiftEditorView: View {
    var route: EditorRoute
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
                        labeled("日付") {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "ja_JP"))
                        }
                        divider
                        HStack {
                            labeled("開始") { MinutesTimePicker(minutes: $startMinutes) }
                            labeled("終了") { MinutesTimePicker(minutes: $endMinutes) }
                        }
                        if selectedWorkplace?.payIsDaily == true {
                            Text("日給の勤務先では、休憩時間は給料から引きません。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        } else {
                            divider
                            Stepper(value: $breakMinutes, in: 0...600, step: 1) {
                                Text("休憩 \(breakMinutes)分")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .tint(Theme.lime)
                        }
                    }
                    formCard {
                        labeled("給料の個別設定") {
                            TextField("空欄なら自動計算", text: $customText)
                                .keyboardType(.numberPad)
                                .font(.system(size: 16, weight: .bold))
                        }
                        divider
                        labeled("天引・手当") {
                            TextField("天引はマイナス", text: $adjustmentText)
                                .keyboardType(.numbersAndPunctuation)
                                .font(.system(size: 16, weight: .bold))
                        }
                        TextField("天引・手当の詳細", text: $adjustmentNote)
                            .font(.system(size: 14))
                        divider
                        TextField("メモ", text: $notes, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
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
                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.behind)
                    }
                    LimeCapsuleButton(title: existing == nil ? "完了する" : "保存する", fillWidth: true) { save() }
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
            }
            .darkSheet()
            .onAppear(perform: load)
            .alert("このシフトを削除しますか？", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) { deleteShift() }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(isPresented: $showWorkplaceCreator) {
                WorkplaceEditorView(existingID: nil)
            }
        }
    }

    private func load() {
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
        if let existing {
            existing.date = Calendar.current.startOfDay(for: date)
            existing.startMinutes = startMinutes
            existing.endMinutes = endMinutes
            existing.breakMinutes = storedBreak
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.customPay = parsedCustom
            existing.adjustmentYen = parsedAdjustment
            existing.adjustmentNote = adjustmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let shift = WorkShift(
                date: date,
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
        try? context.save()
        dismiss()
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
        try? context.save()
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
    @Binding var minutes: Int

    var body: some View {
        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "ja_JP"))
    }

    private var dateBinding: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { newValue in
            let calendar = Calendar.current
            minutes = calendar.component(.hour, from: newValue) * 60 + calendar.component(.minute, from: newValue)
        }
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

    private var existing: Workplace? { workplaces.first { $0.uuid == existingID } }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                formCard {
                    field("勤務先", text: $name)
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
                        }
                    }
                    Picker("締日", selection: $closingDay) {
                        Text("月末").tag(0)
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    .tint(Theme.lime)
                    Picker("給料日の月", selection: $paydayOffset) {
                        Text("当月").tag(0)
                        Text("翌月").tag(1)
                        Text("翌々月").tag(2)
                    }
                    .tint(Theme.lime)
                    Picker("給料日", selection: $paydayDay) {
                        Text("月末").tag(0)
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    .tint(Theme.lime)
                    Picker("給料", selection: $payIsDaily) {
                        Text("時給").tag(false)
                        Text("日給").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if payIsDaily {
                        field("日給（円）", text: $dailyText, number: true)
                    } else {
                        field("時給（円）", text: $wageText, number: true)
                    }
                    field("交通費（円）", text: $transportText, number: true)
                    Toggle("休日給料", isOn: $holidayOn).tint(Theme.lime)
                    if holidayOn {
                        field("休日給料（円）", text: $holidayText, number: true)
                        weekdayPicker
                    }
                    if !payIsDaily {
                        Toggle("深夜給料", isOn: $nightOn).tint(Theme.lime)
                        if nightOn {
                            field("深夜給料（円）", text: $nightText, number: true)
                            HStack {
                                MinutesTimePicker(minutes: $nightStart)
                                Text("から").foregroundStyle(Theme.muted)
                                MinutesTimePicker(minutes: $nightEnd)
                            }
                        }
                        if holidayOn {
                            Toggle("休日深夜給料", isOn: $holidayNightOn).tint(Theme.lime)
                            if holidayNightOn {
                                field("休日深夜給料（円）", text: $holidayNightText, number: true)
                                HStack {
                                    MinutesTimePicker(minutes: $holidayNightStart)
                                    Text("から").foregroundStyle(Theme.muted)
                                    MinutesTimePicker(minutes: $holidayNightEnd)
                                }
                            }
                        }
                    }
                    Toggle("残業手当", isOn: $overtimeOn).tint(Theme.lime)
                    if overtimeOn {
                        Stepper(value: $overtimeHours, in: 1...16) {
                            Text("適応時間 \(overtimeHours)時間")
                                .foregroundStyle(.white)
                        }
                        Picker("金額の単位", selection: $overtimePerHour) {
                            Text("1時間あたり").tag(true)
                            Text("1シフトあたり").tag(false)
                        }
                        .tint(Theme.lime)
                        field("追加金額（円）", text: $overtimeText, number: true)
                    }
                    field("メモ", text: $notes)
                }
                if !error.isEmpty {
                    Text(error).font(.system(size: 13)).foregroundStyle(Theme.behind)
                }
                LimeCapsuleButton(title: existing == nil ? "完了する" : "保存する", fillWidth: true) { save() }
                if existing != nil {
                    Button("この勤務先を削除") { confirmDelete = true }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.behind)
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
            }
            .darkSheet()
            .onAppear(perform: load)
            .alert("この勤務先と、入っているシフトを削除しますか？", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) {
                    if let existing { context.delete(existing) }
                    try? context.save()
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

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "名前を入力してください"
            return
        }
        let wage = min(100_000, max(0, Int(wageText.filter(\.isNumber)) ?? 0))
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
        workplace.dailyWage = min(100_000, max(0, Int(dailyText.filter(\.isNumber)) ?? 0))
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
        try? context.save()
        dismiss()
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
            TextField(title, text: text)
                .keyboardType(number ? .numberPad : .default)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
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
