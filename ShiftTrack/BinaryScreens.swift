import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Screens that are not in the reference photos.
/// Copy is limited to strings a recovered function reads.
/// Layout, type size, and color are not from a screenshot.

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
            List {
                if shown.isEmpty {
                    Text("勤務先はまだ登録されていません")
                }
                if shown.contains(where: PayWindows.needsPaydaySetup) {
                    Text("支払日が未設定です。「支払い」で設定すると、支給日が出ます。")
                }
                ForEach(shown) { workplace in
                    Section(workplace.name) {
                        ForEach(PayWindows.recent(workplace), id: \.self) { window in
                            NavigationLink {
                                PayPeriodDetailView(workplaceID: workplace.uuid, window: window)
                            } label: {
                                PayPeriodRow(workplace: workplace, window: window)
                            }
                        }
                    }
                }
            }
            .navigationTitle("支給の見込み")
            .toolbar {
                Button("閉じる") { dismiss() }
            }
        }
    }
}

private struct PayPeriodRow: View {
    var workplace: Workplace
    var window: PayWindow
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]

    private var mine: [WorkShift] {
        shifts.filter { shift in
            shift.workplace?.uuid == workplace.uuid && shift.date >= window.start && shift.date < window.end
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(PayWindows.rangeTitle(window))
                .designFont(13, weight: .bold)
            Text("支給日 \(Self.dayText(window.payday))")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            let open = mine.filter(\.needsAttendanceCheck).count
            if open > 0 {
                Text("未確認の勤務 \(open)件")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
            Text(Formatters.yen(mine.reduce(0) { $0 + $1.estimatedYen(includeTransport: true) }))
                .font(.doto(18))
        }
    }

    static func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        return String(format: "%04d/%d/%d", calendar.component(.year, from: date), calendar.component(.month, from: date), calendar.component(.day, from: date))
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

    private var workplace: Workplace? { workplaces.first { $0.uuid == workplaceID } }
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
            switch ScheduledPay.evaluate(
                day: shift.date,
                start: shift.startMinutes,
                end: shift.endMinutes,
                breakMinutes: shift.breakMinutes,
                workplace: workplace,
                customPay: shift.customPay
            ) {
            case .amount(let amount):
                base += Int(amount.base.rounded())
                premium += Int(amount.premium.rounded())
            default:
                base += PayMath.quote(
                    workplace: workplace,
                    day: shift.date,
                    start: shift.startMinutes,
                    end: shift.endMinutes,
                    breakMinutes: shift.breakMinutes,
                    customPay: shift.customPay,
                    adjustment: 0,
                    includeTransport: false
                )
            }
            allowance += max(0, shift.adjustmentYen)
            if includeTransport {
                transport += max(0, workplace.transportAllowance)
            }
        }
        return (base, premium, allowance, transport)
    }
    private var forecast: Int { parts.base + parts.premium + parts.allowance + parts.transport }
    private var minutes: Int { mine.reduce(0) { $0 + $1.workedMinutes } }
    private var storageKey: String { "slip.\(workplaceID.uuidString).\(window.start.timeIntervalSince1970)" }

    var body: some View {
        ScreenScroll {
            Text(PayWindows.rangeTitle(window))
                .designFont(22, weight: .black)
            Text("支給日 \(PayPeriodRow.dayText(window.payday))")
            Text("支給の見込み \(Formatters.yen(forecast))")
                .font(.doto(28))
            Text("内訳")
                .designFont(15, weight: .bold)
                .padding(.top, 8)
            Text("基本給 \(Formatters.yen(parts.base))（\(Formatters.hours(minutes))）")
            Text("割増 \(Formatters.yen(parts.premium))")
            Text("手当 \(Formatters.yen(parts.allowance))")
            Text("交通費 \(Formatters.yen(parts.transport))")
            Text("お給料（交通費の前） \(Formatters.yen(parts.base + parts.premium + parts.allowance))")
            Text("支給の見込み \(Formatters.yen(forecast))")
            Text("税金・社会保険は計算していません。")
                .designFont(12)
                .foregroundStyle(Theme.muted)
            group("確認済み", mine.filter { $0.attendanceConfirmed && $0.hasEnded() })
            group("未確認", mine.filter(\.needsAttendanceCheck))
            group("これからのシフト", mine.filter { !$0.hasEnded() })
            Text("おつかれさまでした、は「確認していない勤務」から開きます。勤務が終わったときは振動だけで、ここからは開きません。")
                .designFont(12)
                .foregroundStyle(Theme.muted)
            Text("給与明細と照らし合わせる")
                .designFont(16, weight: .bold)
                .padding(.top, 8)
            slipField("総支給額", text: $gross)
            slipField("差引支給額", text: $net)
            TextField("メモ", text: $memo)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let grossValue = yen(gross) {
                Text("総支給額の差 \(Formatters.yen(grossValue - forecast))（明細 − 見込み）")
            }
            if let netValue = yen(net) {
                Text("差引支給額の差 \(Formatters.yen(netValue - forecast))（明細 − 見込み）")
            }
            Text("差は明細 − 見込みです。税金・社会保険は計算しません。未入力では保存できません。シフトは書き換えません。")
                .designFont(12)
                .foregroundStyle(Theme.muted)
            Button("明細の金額を保存") { storeSlip() }
                .designFont(16, weight: .bold)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canStore ? Theme.ink : Theme.muted)
                .clipShape(Capsule())
                .disabled(!canStore)
            if saved {
                Text("この端末に明細の金額を残しました。シフトは変えていません。")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
            NavigationLink("内訳を見る") {
                PayBreakdownScreen()
            }
        }
        .background(Theme.background)
        .navigationTitle(PayWindows.rangeTitle(window))
        .onAppear(perform: loadSlip)
    }

    private var canStore: Bool {
        yen(gross) != nil && yen(net) != nil
    }

    private func yen(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private func group(_ title: String, _ rows: [WorkShift]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) \(rows.count)件")
                .designFont(14, weight: .bold)
            ForEach(rows) { shift in
                Text("\(Formatters.longDay(shift.date)) \(Formatters.clock(shift.startMinutes))〜\(Formatters.clock(shift.endMinutes))")
                    .designFont(14, weight: .medium)
                    .foregroundStyle(shift.needsAttendanceCheck || !shift.hasEnded() ? Theme.muted : Theme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func slipField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("円", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

struct PayBreakdownView: View {
    var body: some View {
        ScreenScroll {
            Text("締め日に支給")
            Text("勤務日に支給")
            Text("お給料（交通費の前）")
            Text("分単位（開始は")
        }
        .background(Theme.background)
        .navigationTitle("内訳")
    }
}

struct PayTermsNote: View {
    var body: some View {
        ScreenScroll {
            Text("締め日と支払日")
                .designFont(13, weight: .black)
            Text("締めと支払日")
            Text("締めの曜日までの7日間が1回分です。0日は締め日に支払います。")
                .foregroundStyle(Theme.muted)
            Text("決まりの変更を追加")
            Text("この時間を超えたら")
            Text("1分（丸めない）")
            Text("時間帯の時給を追加")
            Text("交通費を追加")
            Text("交通費を削除")
            Text("入力そのものは勤務先の編集にあります。ここから保存しても、入っているシフトは再計算しません。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
        .background(Theme.background)
        .navigationTitle("締めと支払")
    }
}

struct PayScheduleNote: View {
    var body: some View {
        ScreenScroll {
            Text("土日の支払日")
                .designFont(22, weight: .black)
            Text("締め日から支払日まで")
            Text("支払日は、勤務先で選んだ曜日と日を使います。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
        .background(Theme.background)
        .navigationTitle("支払日")
    }
}

struct CalendarAccessView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("カレンダーの許可")
                .designFont(20, weight: .black)
            Text("カレンダーへの追加は、設定のスイッチから行います。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            Button("入力を続ける") { dismiss() }
                .designFont(16, weight: .bold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.cardRaised)
                .clipShape(Capsule())
            Button("設定アプリを開く") { openSettings() }
                .designFont(16, weight: .bold)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.ink)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(20)
        .background(Theme.background)
    }

    private func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

struct LocationNoteView: View {
    @Binding var place: String
    /// Stays 0 until the person asks for the current location. The request
    /// runs only while this is nonzero.
    @State private var locationFlag = 0

    var body: some View {
        ScreenScroll {
            Text("住所・位置（任意）")
                .designFont(16, weight: .black)
            TextField("住所", text: $place)
                .padding(14)
                .background(Theme.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button("現在地を使う") {
                locationFlag = 1
                WhenInUseLocation.requestWhenInUse(flag: locationFlag)
            }
            .designFont(16, weight: .bold)
            .foregroundStyle(Theme.ink)
            Text("住所が空のときだけ、現在地から入れます。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
        .background(Theme.background)
        .navigationTitle("位置")
        .onAppear {
            WhenInUseLocation.requestWhenInUse(flag: locationFlag)
        }
    }
}

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("しふとらっくについて")
                    .designFont(22, weight: .black)
                Text("シフトと給与の見込みを、この端末に残します。")
                    .designFont(15)
                    .foregroundStyle(Theme.muted)
            }
            .background(Theme.background)
            .toolbar {
                Button("閉じる") { dismiss() }
            }
        }
    }
}

struct LateTemplateList: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("文章を直す") {
                        LateMessageComposer()
                    }
                    Button("最初の文章に戻す") {
                        UserDefaults.standard.removeObject(forKey: LateMessageFill.templateKey)
                        UserDefaults.standard.removeObject(forKey: LateMessageComposer.storageKey)
                    }
                }
                Section("勤務先") {
                    if workplaces.isEmpty {
                        Text("勤務先はまだ登録されていません")
                    }
                    ForEach(workplaces) { workplace in
                        NavigationLink(workplace.name) {
                            LateMessageComposer(addressee: workplace.name)
                        }
                    }
                }
            }
            .designFont(16)
            .navigationTitle("メッセージの文章")
            .toolbar {
                Button("閉じる") { dismiss() }
            }
        }
    }
}

struct LateMessageComposer: View {
    static let storageKey = "late.message.draft"

    private static let reasons = [
        "電車の遅延のため",
        "電車の遅延で",
        "寝坊してしまって",
        "寝坊してしまい",
        "体調が優れないため",
        "体調が悪くて",
        "例：家の用事で"
    ]
    private static let endings = ["分ほど遅れます", "分くらい遅れます", "ごろになります"]

    @State private var reason = "電車の遅延のため"
    @State private var minutes = 15
    @State private var ending = "分ほど遅れます"
    @State private var template = LateMessageFill.polite
    @State private var saved = false

    var addressee: String = ""

    /// Each section can be omitted on its own. All four are shown until a branch hides one.
    var hiddenSections: Set<LateMessageSection> = []

    var body: some View {
        ScreenScroll {
            let shown = LateMessageLayout.sections(hidden: hiddenSections)
            if shown.contains(.reason) {
                Text(LateMessageSection.reason.rawValue)
                    .designFont(16, weight: .bold)
                Picker("理由", selection: $reason) {
                    ForEach(Self.reasons, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.inline)
            }
            if shown.contains(.delay) {
                Text(LateMessageSection.delay.rawValue)
                    .designFont(16, weight: .bold)
                Stepper("\(minutes)分", value: $minutes, in: 0...180)
            }
            if shown.contains(.tone) {
                Text(LateMessageSection.tone.rawValue)
                    .designFont(16, weight: .bold)
                Picker("結び", selection: $ending) {
                    ForEach(Self.endings, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if shown.contains(.note) {
                Text(LateMessageSection.note.rawValue)
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
            Text(LateMessageFill.explanation)
                .designFont(13)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("宛名")
                .designFont(16, weight: .bold)
            Text(addressee.isEmpty ? "宛名なし" : addressee)
                .designFont(16)
                .accessibilityIdentifier("late.addressee")
            TextField("文章の型", text: $template, axis: .vertical)
                .designFont(16)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("late.template")
            Text(draft)
                .designFont(16, weight: .bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("late.preview")
            Text("選んだ理由と分数を、この文章にします。送信はしません。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Button("申し訳ありません。") { template = LateMessageFill.polite }
                Button("すみません。") { template = LateMessageFill.casual }
            }
            .designFont(13, weight: .bold)
            Button("保存") {
                UserDefaults.standard.set(template, forKey: LateMessageFill.templateKey)
                UserDefaults.standard.set(draft, forKey: Self.storageKey)
                saved = true
            }
            .designFont(16, weight: .bold)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.lime)
            .clipShape(Capsule())
            if saved {
                Text("型を保存しました")
                    .designFont(16, weight: .bold)
                Text("この端末に下書きを残しました。送信はしていません。")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.background)
        .navigationTitle("遅刻の連絡")
        .onAppear {
            if let stored = UserDefaults.standard.string(forKey: LateMessageFill.templateKey), !stored.isEmpty {
                template = stored
            }
        }
    }

    private var delayText: String {
        if ending == "ごろになります" {
            return "\(minutes)分後\(ending)"
        }
        return "\(minutes)\(ending)"
    }

    private var draft: String {
        LateMessageFill.apply(template: template, addressee: addressee, reason: reason, delay: delayText)
    }
}

struct ShiftCheckView: View {
    var shift: WorkShift
    var onEdit: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsRows: [AppSettings]
    @State private var breakMinutes = 0
    @State private var loaded = false

    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }
    private var minutes: Int {
        PayMath.workedMinutes(start: shift.startMinutes, end: shift.endMinutes, breakMinutes: breakMinutes)
    }
    private var wageOnly: Int {
        guard let workplace = shift.workplace else { return 0 }
        return PayMath.quote(
            workplace: workplace,
            day: shift.date,
            start: shift.startMinutes,
            end: shift.endMinutes,
            breakMinutes: breakMinutes,
            customPay: shift.customPay,
            adjustment: shift.adjustmentYen,
            includeTransport: false
        )
    }

    private var yen: Int {
        guard let workplace = shift.workplace else { return 0 }
        return PayMath.quote(
            workplace: workplace,
            day: shift.date,
            start: shift.startMinutes,
            end: shift.endMinutes,
            breakMinutes: breakMinutes,
            customPay: shift.customPay,
            adjustment: shift.adjustmentYen,
            includeTransport: includeTransport
        )
    }

    var body: some View {
        ScreenScroll {
            Text("おつかれさまでした")
                .designFont(20, weight: .black)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(shift.workplace?.name ?? "勤務先") の勤務時間はこのとおりでしたか？違っていたら押して直せます。")
                .designFont(16)
            Text("\(shift.workplace?.name ?? "勤務先") - \(Formatters.longDay(shift.date))")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                clockCard("IN", shift.startMinutes)
                clockCard("OUT", shift.endMinutes)
            }
            HStack {
                Text("休憩 \(breakMinutes)分")
                    .designFont(16, weight: .bold)
                Spacer()
                Button("−") { breakMinutes = max(0, breakMinutes - 15) }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .background(Theme.cardRaised)
                    .clipShape(Circle())
                Button("+") { breakMinutes = min(600, breakMinutes + 15) }
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .background(Theme.cardRaised)
                    .clipShape(Circle())
            }
            Text("休憩は分数で入れます。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 8) {
                Text("働いた時間 \(Formatters.hours(minutes))")
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Color.white)
                Text("\(yenBody(yen))円")
                    .font(.doto(32))
                    .foregroundStyle(Theme.lime)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            NavigationLink("内訳を見る") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("お給料（交通費の前）")
                    Text(Formatters.yen(wageOnly))
                    Text("税金・社会保険は計算していません。")
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.background)
                .navigationTitle("内訳")
            }
            if let onEdit {
                Button("この日のシフトを編集", action: onEdit)
                    .designFont(13, weight: .bold)
                    .foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.background)
        .navigationTitle("おつかれさまでした")
        .safeAreaInset(edge: .bottom) {
            Button("このとおり", action: confirm)
                .designFont(16, weight: .bold)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.ink)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .onAppear {
            if !loaded {
                breakMinutes = shift.breakMinutes
                loaded = true
            }
        }
    }

    private func clockCard(_ title: String, _ minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .designFont(13, weight: .bold)
                .foregroundStyle(Theme.muted)
            Text(Formatters.clock(minutes))
                .font(.doto(28))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func confirm() {
        // ShiftCheckView's recovered function does not write a confirmed flag.
        // This mark is ShiftTrack's own, so the row can leave the unconfirmed list.
        shift.breakMinutes = breakMinutes
        shift.breakFollowsRules = false
        shift.attendanceConfirmed = true
        try? context.save()
        dismiss()
    }

    private func yenBody(_ value: Int) -> String {
        let body = Formatters.yen(value)
        return body.hasPrefix("¥") ? String(body.dropFirst()) : body
    }
}

struct RequestPlannerView: View {
    var month: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ShiftRequest.date) private var requests: [ShiftRequest]
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScreenScroll {
                HStack(spacing: 8) {
                    Image(systemName: ConfirmedSymbols.planner)
                        .foregroundStyle(Theme.ink)
                    Text("テキスト生成")
                        .designFont(22, weight: .black)
                }
                Button("月の希望をすべて消す") { confirmDelete = true }
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ink)
                    .clipShape(Capsule())
                Text("この月の希望をまとめて消します。シフトは残します。")
                    .designFont(12)
                    .foregroundStyle(Theme.muted)
            }
            .background(Theme.background)
            .navigationTitle("シフト希望")
            .toolbar {
                Button("閉じる") { dismiss() }
            }
            .alert("月の希望をすべて消す", isPresented: $confirmDelete) {
                Button("消す", role: .destructive) { deleteMonth() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この月の希望だけを消します。シフトは残します。")
            }
        }
    }

    private func deleteMonth() {
        let calendar = Calendar.current
        for request in requests where calendar.isDate(request.date, equalTo: month, toGranularity: .month) {
            context.delete(request)
        }
        try? context.save()
    }
}

struct HoursStockSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("時間のストック")
                    .designFont(22, weight: .black)
            }
            .background(Theme.background)
            .navigationTitle("時間のストック")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: ConfirmedSymbols.hoursStockClose)
                    }
                    .accessibilityLabel("閉じる")
                }
            }
        }
    }
}
