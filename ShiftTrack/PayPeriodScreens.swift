import SwiftData
import SwiftUI

/// Pay periods (支給の見込み), one period's detail with the pay-slip check,
/// and the attendance check (勤務の確認).

struct PayWindow: Hashable {
    var start: Date
    var end: Date
    var payday: Date
}

enum PayWindows {
    static func phrase(_ workplace: Workplace) -> String {
        switch workplace.payCycle {
        case .week:
            let names = ["", "日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
            let day = names.indices.contains(workplace.payWeekday) ? names[workplace.payWeekday] : ""
            return day.isEmpty ? "週払い" : "週払い・毎週\(day)"
        case .day:
            return "日払い"
        case .month:
            let close = workplace.closingDay == 0 ? "末日締め" : "\(workplace.closingDay)日締め"
            let offset = ["当月", "翌月", "翌々月"][min(2, max(0, workplace.paydayMonthOffset))]
            let pay = workplace.paydayDay == 0 ? "末日払い" : "\(workplace.paydayDay)日払い"
            return "月払い・\(close)・\(offset)\(pay)"
        }
    }

    /// Week pay with no weekday. Month-end (`paydayDay == 0`) stays a real payday.
    static func needsPaydaySetup(_ workplace: Workplace) -> Bool {
        workplace.payCycle == .week && workplace.payWeekday == 0
    }

    static func recent(_ workplace: Workplace, now: Date = .now, count: Int = 6, calendar: Calendar = .current) -> [PayWindow] {
        var windows: [PayWindow] = []
        var cursor = now
        for _ in 0..<count {
            let window = covering(cursor, workplace: workplace, calendar: calendar)
            if windows.contains(where: { calendar.isDate($0.start, inSameDayAs: window.start) }) { break }
            windows.append(window)
            cursor = calendar.date(byAdding: .day, value: -1, to: window.start) ?? window.start
        }
        return windows
    }

    /// Work dates in the closing window. Not a recovered grouping formula.
    static func covering(_ day: Date, workplace: Workplace, calendar: Calendar = .current) -> PayWindow {
        let day = calendar.startOfDay(for: day)
        if workplace.payCycle != .month || workplace.closingDay == 0 {
            let start = calendar.dateInterval(of: .month, for: day)?.start ?? day
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let payMonth = calendar.date(byAdding: .month, value: max(0, min(2, workplace.paydayMonthOffset)), to: start) ?? start
            return PayWindow(start: start, end: end, payday: PayMath.payday(in: payMonth, workplace: workplace, calendar: calendar))
        }
        let close = min(31, max(1, workplace.closingDay))
        let dayNumber = calendar.component(.day, from: day)
        let anchor = dayNumber <= close ? day : (calendar.date(byAdding: .month, value: 1, to: day) ?? day)
        let monthStart = calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor
        let end = calendar.date(byAdding: .day, value: close, to: monthStart) ?? monthStart
        let previous = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let start = calendar.date(byAdding: .day, value: close, to: previous) ?? previous
        let payMonth = calendar.date(byAdding: .month, value: max(0, min(2, workplace.paydayMonthOffset)), to: monthStart) ?? monthStart
        return PayWindow(start: start, end: end, payday: PayMath.payday(in: payMonth, workplace: workplace, calendar: calendar))
    }

    static func rangeTitle(_ window: PayWindow, calendar: Calendar = .current) -> String {
        let start = calendar.dateComponents([.month, .day], from: window.start)
        let last = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end
        let end = calendar.dateComponents([.month, .day], from: last)
        return "\(start.month ?? 0)/\(start.day ?? 0)〜\(end.month ?? 0)/\(end.day ?? 0)"
    }
}

struct PayPeriodsView: View {
    var workplaceID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]

    private var shown: [Workplace] {
        if let workplaceID, let match = workplaces.first(where: { $0.uuid == workplaceID }) {
            return [match]
        }
        return workplaces
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: "締めの期間ごとに、その期間に働いた分と支給日を出しています。期間を選ぶと内訳と、給与明細との照らし合わせができます。")
                    .padding(.top, Space.xs)
                if shown.isEmpty {
                    EmptyState(systemImage: "building.2", message: "勤務先はまだ登録されていません")
                }
                if shown.contains(where: PayWindows.needsPaydaySetup) {
                    InfoNote(text: "週払いの曜日が決まっていない勤務先があります。勤務先の編集の「締め日と給料日」で選ぶと、支給日が出ます。", tone: .warning)
                }
                ForEach(shown) { workplace in
                    SectionHeader(title: workplace.name, detail: PayWindows.phrase(workplace))
                    Card(spacing: 0) {
                        let windows = PayWindows.recent(workplace)
                        ForEach(Array(windows.enumerated()), id: \.element) { index, window in
                            NavigationLink {
                                PayPeriodDetailView(workplaceID: workplace.uuid, window: window)
                            } label: {
                                PayPeriodRow(workplace: workplace, window: window)
                            }
                            .buttonStyle(RowButtonStyle())
                            if index < windows.count - 1 {
                                RowDivider()
                            }
                        }
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle("支給の見込み")
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

private struct PayPeriodRow: View {
    var workplace: Workplace
    var window: PayWindow
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]

    private var mine: [WorkShift] {
        shifts.filter { shift in
            shift.workplace?.uuid == workplace.uuid && shift.date >= window.start && shift.date < window.end
        }
    }

    var body: some View {
        let includeTransport = settingsRows.first?.includeTransport ?? true
        let total = mine.reduce(0) { $0 + $1.estimatedYen(includeTransport: includeTransport) }
        let open = mine.filter(\.needsAttendanceCheck).count
        HStack(alignment: .center, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(PayWindows.rangeTitle(window)) に働いた分")
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text("支給日 \(Self.dayText(window.payday))・\(mine.count)回")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
                if open > 0 {
                    Text("確認していない勤務 \(open)件")
                        .font(AppFont.helper.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            Spacer(minLength: Space.xs)
            Text(Formatters.yen(total))
                .font(AppFont.value.weight(.bold))
                .foregroundStyle(Theme.ink)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink2)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.year, from: date))年\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }
}

struct PayPeriodDetailView: View {
    var workplaceID: UUID
    var window: PayWindow
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @State private var gross = ""
    @State private var net = ""
    @State private var memo = ""
    @State private var saved = false

    private var mine: [WorkShift] {
        shifts.filter { $0.workplace?.uuid == workplaceID && $0.date >= window.start && $0.date < window.end }
    }
    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }
    private var parts: (base: Int, premium: Int, allowance: Int, transport: Int) {
        var base = 0
        var premium = 0
        var allowance = 0
        var transport = 0
        for shift in mine {
            guard let workplace = shift.workplace else { continue }
            // Same engine as the monthly totals. Empty wage history uses the
            // hourly wage stored on the workplace.
            let wage = PayMath.wageParts(shift)
            base += wage.base
            premium += wage.premium
            allowance += shift.adjustmentYen
            if includeTransport {
                transport += max(0, workplace.transportAllowance)
            }
        }
        return (base, premium, allowance, transport)
    }
    private var forecast: Int { max(0, parts.base + parts.premium + parts.allowance + parts.transport) }
    private var minutes: Int { mine.reduce(0) { $0 + $1.workedMinutes } }
    private var storageKey: String { "slip.\(workplaceID.uuidString).\(window.start.timeIntervalSince1970)" }

    var body: some View {
        ScreenScroll(spacing: Space.m) {
            Card(spacing: Space.xs) {
                Text("\(PayWindows.rangeTitle(window)) に働いた分・支給日 \(PayPeriodRow.dayText(window.payday))")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                DotoText("¥" + Formatters.yenDigits(forecast), size: 36, spoken: "支給の見込み \(forecast)円")
                ValueRow(title: "勤務時間", value: Formatters.hours(minutes))
            }
            .padding(.top, Space.xs)
            SectionHeader(title: "内訳")
            Card(spacing: Space.xxs) {
                ValueRow(title: "基本の給料", value: Formatters.yen(parts.base))
                ValueRow(title: "割増（深夜・休日・残業）", value: Formatters.yen(parts.premium))
                ValueRow(title: "天引・手当", value: (parts.allowance < 0 ? "−" : "") + Formatters.yen(abs(parts.allowance)))
                ValueRow(title: includeTransport ? "交通費" : "交通費（含めない設定）", value: Formatters.yen(parts.transport))
                RowDivider()
                ValueRow(title: "支給の見込み", value: Formatters.yen(forecast), emphasized: true)
                InfoNote(text: "税金・社会保険は計算していません。")
            }
            group("確認済みの勤務", mine.filter { $0.attendanceConfirmed && $0.hasEnded() })
            group("確認していない勤務", mine.filter(\.needsAttendanceCheck))
            group("これからの勤務", mine.filter { !$0.hasEnded() })
            SectionHeader(title: "給与明細と照らし合わせる", detail: "明細の金額を入れると、見込みとの差を出します。この端末にだけ残り、シフトは変えません。")
            Card {
                YenField(label: "総支給額（明細）", text: $gross, identifier: "slip.gross")
                YenField(label: "差引支給額（明細）", text: $net, identifier: "slip.net")
                LabeledField(label: "メモ（任意）", text: $memo, prompt: "例：手当の内容", identifier: "slip.memo")
                PrimaryButton(title: "明細の金額を残す", identifier: "slip.save") { storeSlip() }
                    .disabled(!canStore)
                if !canStore {
                    InfoNote(text: "2つの金額を入れると残せます。")
                }
                if saved {
                    InfoNote(text: "この端末に残しました。", systemImage: "checkmark.circle")
                }
            }
            if let grossValue = yen(gross), let netValue = yen(net) {
                SectionHeader(title: "見込みとの差", detail: "プラスは明細の方が多い、マイナスは見込みの方が多い、という意味です。税金や社会保険は見込みに入っていません。")
                Card(spacing: Space.xs) {
                    slipDelta(title: "総支給額", slip: grossValue)
                    slipDelta(title: "差引支給額", slip: netValue)
                }
            }
        }
        .background(Theme.paper)
        .navigationTitle(PayWindows.rangeTitle(window))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadSlip)
    }

    private var canStore: Bool {
        yen(gross) != nil && yen(net) != nil
    }

    private func slipDelta(title: String, slip: Int) -> some View {
        let delta = slip - forecast
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
                Text(delta == 0 ? "見込みと同じ" : (delta > 0 ? "明細の方が多い" : "見込みの方が多い"))
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: Space.xs)
            Text(signed(delta))
                .font(AppFont.value.weight(.bold))
                .foregroundStyle(delta == 0 ? Theme.signalInk : Theme.danger)
                .accessibilityIdentifier("slip.delta.\(title)")
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(Formatters.yen(value))" : (value < 0 ? "−\(Formatters.yen(-value))" : Formatters.yen(0))
    }

    private func yen(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    @ViewBuilder private func group(_ title: String, _ rows: [WorkShift]) -> some View {
        if !rows.isEmpty {
            SectionHeader(title: "\(title) \(rows.count)件")
            Card(spacing: Space.xxs) {
                ForEach(rows) { shift in
                    Text("\(Formatters.longDay(shift.date)) \(Formatters.clock(shift.startMinutes))〜\(Formatters.clock(shift.endMinutes))")
                        .font(AppFont.body.monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                }
            }
        }
    }

    private func loadSlip() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let draft = try? JSONDecoder().decode(SlipDraft.self, from: data) else { return }
        gross = draft.gross
        net = draft.net
        memo = draft.memo
    }

    private func storeSlip() {
        let draft = SlipDraft(gross: gross, net: net, memo: memo)
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        saved = true
    }
}

private struct SlipDraft: Codable {
    var gross: String
    var net: String
    var memo: String
}

/// 勤務の確認: record the times actually worked. The scheduled start and end stay put.
struct ShiftCheckView: View {
    var shift: WorkShift
    var onEdit: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [AppSettings]
    @State private var breakMinutes = 0
    @State private var draftStart = 0
    @State private var draftEnd = 0
    @State private var editing: CheckClock? = nil
    @State private var loaded = false

    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }
    private var minutes: Int {
        PayMath.workedMinutes(start: draftStart, end: draftEnd, breakMinutes: breakMinutes)
    }

    private var yen: Int {
        guard let workplace = shift.workplace else { return 0 }
        return PayMath.quote(
            workplace: workplace,
            day: shift.date,
            start: draftStart,
            end: draftEnd,
            breakMinutes: breakMinutes,
            customPay: shift.customPay,
            adjustment: shift.adjustmentYen,
            includeTransport: includeTransport
        )
    }

    var body: some View {
        ScreenScroll(spacing: Space.m) {
            Card(spacing: Space.xs) {
                Text("\(shift.workplace?.name ?? "勤務先")・\(Formatters.longDay(shift.date))")
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                Text("この勤務は予定どおりでしたか？")
                    .font(AppFont.screenTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("開始と終了が違うときは、カードを押してここで直します。予定のシフトは変わりません。")
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.xs)
            HStack(alignment: .top, spacing: Space.xs) {
                clockCard(.start)
                clockCard(.end)
            }
            if let editing {
                clockAdjust(editing)
            }
            Card {
                BreakMinutesControl(minutes: $breakMinutes, range: 0...600)
                RowDivider()
                ValueRow(title: "働いた時間", value: Formatters.hours(minutes), emphasized: true)
                    .accessibilityIdentifier("check.worked")
                HStack(alignment: .firstTextBaseline) {
                    Text("この勤務の給料")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: Space.xs)
                    DotoText("¥" + Formatters.yenDigits(yen), size: 28, spoken: "\(yen)円")
                        .accessibilityIdentifier("check.yen")
                }
                InfoNote(text: includeTransport ? "交通費と天引・手当を含みます。税金・社会保険は計算していません。" : "天引・手当を含みます。交通費と税金・社会保険は含みません。")
            }
            if let onEdit {
                Button(action: onEdit) {
                    Text("予定のシフトを編集")
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.signalInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("check.edit")
            }
        }
        .background(Theme.paper)
        .navigationTitle("勤務の確認")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "この内容で確定", systemImage: "checkmark", identifier: "check.confirm", action: confirm)
                .padding(.horizontal, Space.gutter)
                .padding(.vertical, Space.xs)
                .background(Theme.paper)
        }
        .onAppear {
            if !loaded {
                breakMinutes = shift.breakMinutes
                draftStart = ShiftDatePolicy.clockMinutes(shift.actualStartMinutes ?? shift.startMinutes)
                draftEnd = ShiftDatePolicy.clockMinutes(shift.actualEndMinutes ?? shift.endMinutes)
                loaded = true
            }
        }
    }

    private func clockCard(_ field: CheckClock) -> some View {
        let scheduled = ShiftDatePolicy.clockMinutes(field == .start ? shift.startMinutes : shift.endMinutes)
        let current = field == .start ? draftStart : draftEnd
        let changed = current != scheduled
        return VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                editing = editing == field ? nil : field
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.title)
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink2)
                    DotoText(Formatters.clock(current), size: 28, spoken: "\(field.title) \(Formatters.spokenClock(current))")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier(field.identifier)
            .accessibilityHint("実際の時刻を直します。予定は変わりません。")
            if changed {
                Text("予定 \(Formatters.clock(scheduled))")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("check.changed.\(field.title)")
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func clockAdjust(_ field: CheckClock) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("\(field.title)の実際の時刻")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink2)
            HStack(spacing: Space.xs) {
                nudge(field, delta: -15, title: "−15分", label: "15分早める", id: "minus15")
                nudge(field, delta: 15, title: "+15分", label: "15分遅らせる", id: "plus15")
                nudge(field, delta: -1, title: "−1分", label: "1分早める", id: "minus1")
                nudge(field, delta: 1, title: "+1分", label: "1分遅らせる", id: "plus1")
            }
            DatePicker(
                field.title,
                selection: clockBinding(field),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .accessibilityIdentifier("\(field.identifier).picker")
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func nudge(_ field: CheckClock, delta: Int, title: String, label: String, id: String) -> some View {
        Button {
            let current = field == .start ? draftStart : draftEnd
            let next = ShiftDatePolicy.clockMinutes(current + delta)
            if field == .start {
                draftStart = next
            } else {
                draftEnd = next
            }
        } label: {
            Text(title)
                .font(AppFont.label.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(field.identifier).\(id)")
    }

    private func clockBinding(_ field: CheckClock) -> Binding<Date> {
        Binding {
            ShiftDatePolicy.clockDate(minutes: field == .start ? draftStart : draftEnd)
        } set: { newValue in
            let minutes = ShiftDatePolicy.clockMinutes(from: newValue)
            if field == .start {
                draftStart = minutes
            } else {
                draftEnd = minutes
            }
        }
    }

    /// Writes the actual clocks beside the schedule. Matching the schedule stores nil.
    private func confirm() {
        let start = ShiftDatePolicy.clockMinutes(draftStart)
        let end = ShiftDatePolicy.clockMinutes(draftEnd)
        shift.actualStartMinutes = start == ShiftDatePolicy.clockMinutes(shift.startMinutes) ? nil : start
        shift.actualEndMinutes = end == ShiftDatePolicy.clockMinutes(shift.endMinutes) ? nil : end
        shift.breakMinutes = breakMinutes
        shift.breakFollowsRules = false
        shift.attendanceConfirmed = true
        try? context.save()
        dismiss()
    }
}

private enum CheckClock: Equatable {
    case start, end

    var title: String {
        switch self {
        case .start: "開始"
        case .end: "終了"
        }
    }

    var identifier: String {
        switch self {
        case .start: "check.start"
        case .end: "check.end"
        }
    }
}
