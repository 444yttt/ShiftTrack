import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Screens that are not in the reference photos.
/// Copy is limited to strings a recovered function reads.
/// Layout, type size, and color are not from a screenshot.

struct PayPeriodsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]

    private var months: [Date] {
        let calendar = Calendar.current
        let days = Set(shifts.map { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date })
        return days.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                if months.isEmpty {
                    Text("この期間のシフトはありません")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(months, id: \.self) { month in
                    NavigationLink {
                        PayPeriodDetailView(month: month)
                    } label: {
                        Text(Formatters.monthTitle(month))
                    }
                }
                NavigationLink("内訳") {
                    PayBreakdownView()
                }
            }
            .navigationTitle("今月の支給見込み")
            .toolbar {
                Button("閉じる") { dismiss() }
            }
        }
    }
}

struct PayPeriodDetailView: View {
    var month: Date
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @State private var savedNote = false

    private var totals: IncomeEngine.Totals {
        let includeTransport = settingsRows.first?.includeTransport ?? true
        let snapshots = ShiftMapping.snapshots(shifts, includeTransport: includeTransport)
        guard let interval = IncomeEngine.monthInterval(month) else { return IncomeEngine.Totals() }
        return IncomeEngine.totals(shifts: snapshots, from: interval.0, until: interval.1, now: .now)
    }

    var body: some View {
        ScreenScroll {
            Text(Formatters.monthTitle(month))
                .font(.system(size: 22, weight: .black))
            Text(Formatters.yen(totals.forecastYen))
                .font(.doto(36))
            Text("差引支給額の差")
                .font(.system(size: 15, weight: .bold))
            Text("手当と控除の式は未回収です。差の数字は出しません。保存済みのシフトは書き換えません。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            Button("明細の金額を保存") {
                savedNote = true
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.ink)
            .clipShape(Capsule())
            if savedNote {
                Text("金額の保存先は未回収です。シフトと見込は変えていません。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.background)
        .navigationTitle("明細")
    }
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
    var onEdit: () -> Void
    @State private var showSave = false

    var body: some View {
        ScreenScroll {
            Text(shift.workplace?.name ?? "勤務先")
                .font(.system(size: 22, weight: .black))
            Text("計算に使う時間")
                .font(.system(size: 15, weight: .bold))
            Text("\(Formatters.clock(shift.startMinutes))–\(Formatters.clock(shift.endMinutes))")
                .font(.doto(28))
            Text("休憩 \(shift.breakMinutes)分")
            Text("休憩の時間帯を入れる")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            Text("休憩の開始と終了の帯は未回収です。分数だけを表示しています。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Button("この日のシフトを編集", action: onEdit)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.cardRaised)
                .clipShape(Capsule())
            Button("このまま保存") { showSave = true }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.ink)
                .clipShape(Capsule())
        }
        .background(Theme.background)
        .navigationTitle("シフト確認")
        .sheet(isPresented: $showSave) {
            VStack(alignment: .leading, spacing: 12) {
                Text("このまま保存")
                    .font(.system(size: 22, weight: .black))
                Text("衝突のあとに確定する命令は未回収です。このボタンは保存済みのシフトを書き換えません。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(20)
            .presentationDetents([.medium])
        }
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
