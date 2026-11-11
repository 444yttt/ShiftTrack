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
                .font(.system(size: 16, weight: .bold))
            Text("支給日 \(Self.dayText(window.payday))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            let open = mine.filter(\.needsAttendanceCheck).count
            if open > 0 {
                Text("未確認の勤務 \(open)件")
                    .font(.system(size: 12))
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
    private var wageYen: Int { mine.reduce(0) { $0 + $1.estimatedYen(includeTransport: false) } }
    private var withTransport: Int { mine.reduce(0) { $0 + $1.estimatedYen(includeTransport: true) } }
    private var forecast: Int { includeTransport ? withTransport : wageYen }
    private var minutes: Int { mine.reduce(0) { $0 + $1.workedMinutes } }
    private var storageKey: String { "slip.\(workplaceID.uuidString).\(window.start.timeIntervalSince1970)" }

    var body: some View {
        ScreenScroll {
            Text(PayWindows.rangeTitle(window))
                .font(.system(size: 22, weight: .black))
            Text("支給日 \(PayPeriodRow.dayText(window.payday))")
            Text("支給の見込み \(Formatters.yen(forecast))")
                .font(.doto(28))
            Text("内訳")
                .font(.system(size: 15, weight: .bold))
                .padding(.top, 8)
            Text("時給 \(Formatters.yen(wageYen))（\(Formatters.hours(minutes))）")
            Text("交通費 \(Formatters.yen(max(0, withTransport - wageYen)))")
            Text("働いた時間 \(Formatters.hours(minutes))")
            Text("お給料（交通費の前） \(Formatters.yen(wageYen))")
            Text("支給の見込み \(Formatters.yen(forecast))")
            Text("税金・社会保険は計算していません。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            group("確認済み", mine.filter { $0.attendanceConfirmed && $0.hasEnded() })
            group("未確認", mine.filter(\.needsAttendanceCheck))
            group("これからのシフト", mine.filter { !$0.hasEnded() })
            Text("終わった勤務を押すと、時間・休憩を確認できます。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Text("給与明細と照らし合わせる")
                .font(.system(size: 16, weight: .bold))
                .padding(.top, 8)
            slipField("総支給額", text: $gross)
            slipField("差引支給額", text: $net)
            TextField("メモ", text: $memo)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let grossValue = Int(gross.filter(\.isNumber)), !gross.isEmpty {
                Text("見込みとの差 \(Formatters.yen(grossValue - forecast))")
            }
            if let grossValue = Int(gross.filter(\.isNumber)), let netValue = Int(net.filter(\.isNumber)), !gross.isEmpty, !net.isEmpty {
                Text("差引支給額の差 \(Formatters.yen(grossValue - netValue))")
            }
            Text("明細の金額を入れると、見込みとの差を出します。シフトの見込は書き換えません。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Button("明細の金額を保存") { storeSlip() }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canStore ? Theme.ink : Theme.muted)
                .clipShape(Capsule())
                .disabled(!canStore)
            if saved {
                Text("この端末に明細の金額を残しました。シフトは変えていません。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            NavigationLink("内訳の未回収の文言") { PayBreakdownView() }
        }
        .background(Theme.background)
        .navigationTitle(PayWindows.rangeTitle(window))
        .onAppear(perform: loadSlip)
    }

    private var canStore: Bool {
        !gross.filter(\.isNumber).isEmpty || !net.filter(\.isNumber).isEmpty
    }

    private func group(_ title: String, _ rows: [WorkShift]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) \(rows.count)件")
                .font(.system(size: 14, weight: .bold))
            ForEach(rows) { shift in
                NavigationLink {
                    ShiftCheckView(shift: shift)
                } label: {
                    Text("\(Formatters.longDay(shift.date)) \(Formatters.clock(shift.startMinutes))〜\(Formatters.clock(shift.endMinutes))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(shift.needsAttendanceCheck || !shift.hasEnded() ? Theme.muted : Theme.ink)
                }
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
            Text("この画面だけを呼ぶ関数は見つかっていません。近くの関数が読む文言だけを出します。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
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
                .font(.system(size: 22, weight: .black))
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
                .font(.system(size: 13))
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
                .font(.system(size: 22, weight: .black))
            Text("締め日から支払日まで")
            Text("支払日の移動規則は未回収です。勤務先の編集で選んだ曜日と日だけを使います。")
                .font(.system(size: 13))
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
                .font(.system(size: 22, weight: .black))
            Text("許可の分岐は未回収です。予定の読み取りはまだ繋いでいません。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            Button("入力を続ける") { dismiss() }
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.cardRaised)
                .clipShape(Capsule())
            Button("設定アプリを開く") { openSettings() }
                .font(.system(size: 16, weight: .bold))
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

    var body: some View {
        ScreenScroll {
            Text("住所・位置（任意）")
                .font(.system(size: 22, weight: .black))
            TextField("住所", text: $place)
                .padding(14)
                .background(Theme.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("時給の変更を追加")
                .font(.system(size: 15, weight: .bold))
            Text("この文言は位置の画面の関数が読みます。地図の検索結果は未回収なので出しません。時給の行は勤務先の編集にあります。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .background(Theme.background)
        .navigationTitle("位置")
    }
}

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("IN/OUT について")
                    .font(.system(size: 22, weight: .black))
                Text("しふとらっく")
                Text("App Store を開く")
                    .font(.system(size: 15, weight: .bold))
                Text("この文言は概要の専用関数の外にあります。ストアのページへは繋いでいません。")
                    .font(.system(size: 13))
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
                        UserDefaults.standard.removeObject(forKey: LateMessageComposer.storageKey)
                    }
                }
                Section("勤務先") {
                    if workplaces.isEmpty {
                        Text("勤務先はまだ登録されていません")
                    }
                    ForEach(workplaces) { workplace in
                        Text(workplace.name)
                    }
                }
            }
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
    @State private var saved = false

    var body: some View {
        ScreenScroll {
            Text("① 遅れる理由")
                .font(.system(size: 15, weight: .bold))
            Picker("理由", selection: $reason) {
                ForEach(Self.reasons, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.inline)
            Text("② 遅れる時間")
                .font(.system(size: 15, weight: .bold))
            Stepper("\(minutes)分", value: $minutes, in: 0...180)
            Text("③ 言葉づかい")
                .font(.system(size: 15, weight: .bold))
            Picker("結び", selection: $ending) {
                ForEach(Self.endings, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("文章はここで直せます。①〜③の答えを変えると作り直します。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            Text(draft)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("選び方の式は未回収です。上の文は、選んだ文言を並べただけです。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Button("保存") {
                UserDefaults.standard.set(draft, forKey: Self.storageKey)
                saved = true
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.lime)
            .clipShape(Capsule())
            if saved {
                Text("型を保存しました")
                    .font(.system(size: 15, weight: .bold))
                Text("この端末に下書きを残しました。送信はしていません。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.background)
        .navigationTitle("遅刻の連絡")
        .onAppear {
            if let stored = UserDefaults.standard.string(forKey: Self.storageKey), !stored.isEmpty {
                saved = false
            }
        }
    }

    private var draft: String {
        if ending == "ごろになります" {
            return "\(reason)、\(minutes)分後\(ending)"
        }
        return "\(reason)、\(minutes)\(ending)"
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
    @State private var showBandNote = false

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
                .font(.system(size: 28, weight: .black))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(shift.workplace?.name ?? "勤務先") - \(Formatters.longDay(shift.date))")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                clockCard("IN", shift.startMinutes)
                clockCard("OUT", shift.endMinutes)
            }
            HStack {
                Text("休憩 \(breakMinutes)分")
                    .font(.system(size: 16, weight: .bold))
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
            Button("+ 休憩の時間帯を入れる") { showBandNote = true }
                .font(.system(size: 14, weight: .bold))
            if showBandNote {
                Text("休憩の開始と終了の帯は未回収です。分数だけを変えています。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("働いた時間 \(Formatters.hours(minutes))")
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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.background)
        .navigationTitle("おつかれさまでした")
        .safeAreaInset(edge: .bottom) {
            Button("このとおり", action: confirm)
                .font(.system(size: 17, weight: .bold))
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
                .font(.system(size: 13, weight: .bold))
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
                Text("テキスト生成")
                    .font(.system(size: 22, weight: .black))
                Text("希望の文章を作る式は未回収です。文章は作りません。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                Button("月の希望をすべて消す") { confirmDelete = true }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ink)
                    .clipShape(Capsule())
                Text("の希望を消す")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Text("1件ずつ消す条件は未回収です。月の一括だけを、確認のあとに実行します。シフトは消しません。")
                    .font(.system(size: 12))
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
