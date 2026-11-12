import CoreLocation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 設定. Every group is a white card under a section header; every control
/// has a visible label and a line that says what it changes.
struct SettingsScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @State private var goalText = ""
    @State private var monthGoalText = ""
    @State private var wageText = ""
    @State private var transportText = ""
    @FocusState private var focused: Bool
    @State private var sheet: SettingsSheet?
    @State private var locationStatus = LocationPrompt.shared.status
    @State private var noticeNote = ""
    @State private var mirrorNote = ""
    @AppStorage("settings.travelMinutes") private var travelMinutes = 30
    @AppStorage(ShiftNoticeRefresh.beforeKey) private var notifyBefore = false
    @AppStorage(ShiftNoticeRefresh.endKey) private var notifyAtEnd = false
    @AppStorage(ShiftMirrorRefresh.calendarKey) private var mirrorCalendar = false
    @AppStorage(ShiftMirrorRefresh.reminderKey) private var mirrorReminders = false

    private enum SettingsSheet: String, Identifiable {
        case messages, license, help
        var id: String { rawValue }
    }

    var body: some View {
        if let settings = settingsRows.first {
            form(settings)
        } else {
            Theme.paper
        }
    }

    private func form(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return ScreenScroll(spacing: Space.m) {
            ScreenHeader(title: "設定") {
                HelpButton { sheet = .help }
            }

            SectionHeader(title: "通知", detail: "この端末からだけ知らせます。オンにしたときに許可を求めます。")
            Card(spacing: Space.s) {
                ToggleRow(
                    title: "シフトの前に知らせる",
                    helper: "開始の30分前に通知します。",
                    isOn: $notifyBefore,
                    identifier: "settings.notifyBefore"
                )
                RowDivider()
                ToggleRow(
                    title: "勤務の終わりに知らせる",
                    helper: "終了の時刻に、働いた時間と休憩の確認をうながします。",
                    isOn: $notifyAtEnd,
                    identifier: "settings.notifyEnd"
                )
                if !noticeNote.isEmpty {
                    InfoNote(text: noticeNote, tone: .error)
                    SecondaryButton(title: "設定アプリを開く", systemImage: "arrow.up.forward.app", identifier: "settings.notices.open") {
                        openSystemSettings()
                    }
                }
            }
            .onChange(of: notifyAtEnd) { _, _ in Task { await updateNotices() } }
            .onChange(of: notifyBefore) { _, _ in Task { await updateNotices() } }
            .sensoryFeedback(.selection, trigger: notifyAtEnd)
            .sensoryFeedback(.selection, trigger: notifyBefore)

            SectionHeader(title: "カレンダーとリマインダー", detail: "「しふとらっく」という名前のカレンダーとリストだけを作って更新します。ほかの予定やリマインダーは変えません。")
            Card(spacing: Space.s) {
                ToggleRow(
                    title: "シフトをカレンダーに書き出す",
                    helper: "シフトを予定として入れ、時間を直すと予定も直します。",
                    isOn: $mirrorCalendar,
                    identifier: "settings.calendar"
                )
                RowDivider()
                ToggleRow(
                    title: "やることをリマインダーに書き出す",
                    helper: "シフトのやることを、開始の時刻のリマインダーにします。",
                    isOn: $mirrorReminders,
                    identifier: "settings.reminders"
                )
                if !mirrorNote.isEmpty {
                    InfoNote(text: mirrorNote, tone: .error)
                    SecondaryButton(title: "設定アプリを開く", systemImage: "arrow.up.forward.app", identifier: "settings.mirror.open") {
                        openSystemSettings()
                    }
                }
            }
            .onChange(of: mirrorCalendar) { _, on in Task { await updateCalendar(on) } }
            .onChange(of: mirrorReminders) { _, on in Task { await updateReminders(on) } }
            .sensoryFeedback(.selection, trigger: mirrorCalendar)
            .sensoryFeedback(.selection, trigger: mirrorReminders)

            SectionHeader(title: "連絡メッセージ", detail: "ホームと勤務先の「メッセージ」ボタンで、遅れるときの連絡に使う文章です。")
            Card(spacing: Space.xs) {
                Button {
                    sheet = .messages
                } label: {
                    NavRow(systemImage: "text.bubble", title: "メッセージのひな形", subtitle: "宛名・理由・遅れる時間が入る文章を直せます")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("settings.messages")
                VStack(alignment: .leading, spacing: 4) {
                    Text("いまのひな形で作ると")
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                    Text(MessageTemplate.preview(MessageTemplate.current))
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .accessibilityIdentifier("settings.messages.preview")
                }
            }

            SectionHeader(title: "シフトの重なり")
            Card {
                StepperRow(
                    label: "勤務先の移動にかかる時間",
                    valueText: travelMinutes == 0 ? "見ない" : "\(travelMinutes)分",
                    value: $travelMinutes,
                    range: 0...180,
                    step: 5,
                    helper: "違う勤務先のシフトの間がこれより短いと、保存の前に知らせます。0分にすると間隔は見ません。時間が重なるときは、いつも知らせます。",
                    identifier: "settings.travel"
                )
            }
            .sensoryFeedback(.selection, trigger: travelMinutes)

            SectionHeader(title: "カレンダーの表示")
            Card(spacing: Space.s) {
                ToggleRow(
                    title: "週の始まりを月曜にする",
                    helper: "オフのときは日曜から始まります。",
                    isOn: $settings.weekStartsOnMonday,
                    identifier: "settings.weekStartsOnMonday"
                )
                RowDivider()
                ToggleRow(
                    title: "給料日をカレンダーに出す",
                    helper: "給料日の日付に「給」と出します。",
                    isOn: $settings.showPaydayOnCalendar,
                    identifier: "settings.showPayday"
                )
            }

            SectionHeader(title: "給料の計算", detail: "金額はすべて目安です。税金や社会保険は計算していません。")
            Card(spacing: Space.s) {
                ToggleRow(
                    title: "交通費を給料に含める",
                    helper: "オンにすると、シフトごとに勤務先の交通費を足して見込みを出します。",
                    isOn: $settings.includeTransport,
                    identifier: "settings.includeTransport"
                )
                RowDivider()
                YenField(
                    label: "月の目標",
                    text: $monthGoalText,
                    helper: "5,000円以上、100万円未満。給料タブで月ごとに変えた金額があれば、そちらを使います。",
                    error: rangeError(monthGoalText, range: 5_000..<1_000_000, text: "5,000円以上、100万円未満で入れてください。"),
                    identifier: "settings.goal.month"
                )
                YenField(
                    label: "年の目標",
                    text: $goalText,
                    helper: "1万円以上、1,000万円未満。",
                    error: rangeError(goalText, range: 10_000..<10_000_000, text: "1万円以上、1,000万円未満で入れてください。"),
                    identifier: "settings.goal.year"
                )
            }

            SectionHeader(title: "新しい勤務先の初期値", detail: "シフト表の取り込みで、知らない勤務先名から勤務先を作るときに使います。")
            Card(spacing: Space.s) {
                YenField(
                    label: "時給",
                    text: $wageText,
                    error: rangeError(wageText, range: 0..<100_001, text: "10万円以下で入れてください。"),
                    identifier: "settings.default.wage"
                )
                YenField(
                    label: "交通費（1回あたり）",
                    text: $transportText,
                    error: rangeError(transportText, range: 0..<100_001, text: "10万円以下で入れてください。"),
                    identifier: "settings.default.transport"
                )
            }
            .onAppear { syncFields(settings) }
            .onChange(of: goalText) { _, new in
                commit(new, range: 10_000..<10_000_000) { value in
                    if settings.annualIncomeGoal != value { settings.annualIncomeGoal = value }
                }
            }
            .onChange(of: monthGoalText) { _, new in
                commit(new, range: 5_000..<1_000_000) { value in
                    if settings.monthlyIncomeGoal != value { settings.monthlyIncomeGoal = value }
                }
            }
            .onChange(of: wageText) { _, new in
                commit(new, range: 0..<100_001) { value in
                    if settings.defaultHourlyWage != value { settings.defaultHourlyWage = value }
                }
            }
            .onChange(of: transportText) { _, new in
                commit(new, range: 0..<100_001) { value in
                    if settings.defaultTransportAllowance != value { settings.defaultTransportAllowance = value }
                }
            }
            .onChange(of: settings.weekStartsOnMonday) { _, _ in persist() }
            .onChange(of: settings.showPaydayOnCalendar) { _, _ in persist() }
            .onChange(of: settings.includeTransport) { _, _ in persist() }
            .onChange(of: settings.annualIncomeGoal) { _, new in rewrite(new, into: $goalText) }
            .onChange(of: settings.monthlyIncomeGoal) { _, new in rewrite(new, into: $monthGoalText) }

            SectionHeader(title: "位置情報", detail: "勤務先の住所を、今いる場所から入れるときだけ使います。")
            Card(spacing: Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("いまの状態")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: Space.xs)
                    StatusChip(text: Self.locationLabel(locationStatus), emphasized: Self.locationAllowed(locationStatus))
                }
                .accessibilityElement(children: .combine)
                SecondaryButton(
                    title: locationStatus == .notDetermined ? "位置情報を許可する" : "設定アプリを開く",
                    systemImage: locationStatus == .notDetermined ? "location" : "arrow.up.forward.app",
                    identifier: "settings.location"
                ) {
                    if locationStatus == .notDetermined {
                        LocationPrompt.shared.onChange = {
                            locationStatus = LocationPrompt.shared.status
                        }
                        LocationPrompt.shared.request()
                    } else {
                        openSystemSettings()
                    }
                }
                if locationStatus != .notDetermined {
                    InfoNote(text: "許可を変えるときは、設定アプリの「しふとらっく」→「位置情報」で選びます。")
                }
            }

            SectionHeader(title: "Siri とショートカット")
            Card {
                Text("「しふとらっくでシフト表を取り込む」と話しかけると、シフト表の取り込みが開きます。ショートカット App の「シフト表の画像を取り込む」に画像を渡すこともできます。読み取りはこの端末の中で行い、保存の前に確認できます。")
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionHeader(title: "このアプリについて")
            Card(spacing: Space.xs) {
                ValueRow(title: "バージョン", value: Self.versionText)
                RowDivider()
                Text("勤務先、シフト、設定はこの端末の中だけに保存します。サーバーには送りません。金額はすべて目安です。")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Space.xxs)
                RowDivider()
                Button {
                    sheet = .license
                } label: {
                    NavRow(systemImage: "textformat", title: "フォントのライセンス", subtitle: "Doto（SIL Open Font License 1.1）")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("settings.license")
            }
        }
        .background(Theme.paper)
        .focused($focused)
        .onAppear {
            locationStatus = LocationPrompt.shared.status
        }
        .animation(reduceMotion ? nil : Motion.layout, value: noticeNote)
        .animation(reduceMotion ? nil : Motion.layout, value: mirrorNote)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .messages:
                MessageTemplateEditor()
            case .license:
                LicenseSheet()
            case .help:
                HelpSheet(title: "設定について", paragraphs: HelpCopy.settings)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    focused = false
                    Keyboard.dismiss()
                }
            }
        }
    }

    // MARK: Labels

    static func locationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return "許可しています"
        case .denied, .restricted:
            return "許可していません"
        case .notDetermined:
            return "まだ選んでいません"
        @unknown default:
            return "まだ選んでいません"
        }
    }

    static func locationAllowed(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways || status == .authorizedWhenInUse
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version)（\(build)）"
    }

    // MARK: Actions

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func updateNotices() async {
        if notifyBefore || notifyAtEnd {
            let allowed = await SettingsAccess.requestNotifications()
            if !allowed {
                notifyBefore = false
                notifyAtEnd = false
                noticeNote = "通知が許可されていないため、オンにできませんでした。設定アプリの「しふとらっく」→「通知」で許可できます。"
                await ShiftNoticeRefresh.apply(shifts: shifts)
                return
            }
        }
        noticeNote = ""
        await ShiftNoticeRefresh.apply(shifts: shifts)
    }

    private func updateCalendar(_ on: Bool) async {
        if on {
            let allowed = await ExternalMirror.shared.requestEvents()
            guard allowed else {
                mirrorCalendar = false
                mirrorNote = "カレンダーへのアクセスが許可されていないため、オンにできませんでした。"
                return
            }
            do {
                try ExternalMirror.shared.syncEvents(mirrorEvents())
                mirrorNote = ""
            } catch {
                mirrorCalendar = false
                mirrorNote = "この端末にはカレンダーを追加できませんでした。"
            }
        } else {
            try? ExternalMirror.shared.clearEvents()
            mirrorNote = ""
        }
    }

    private func updateReminders(_ on: Bool) async {
        if on {
            let allowed = await ExternalMirror.shared.requestReminders()
            guard allowed else {
                mirrorReminders = false
                mirrorNote = "リマインダーへのアクセスが許可されていないため、オンにできませんでした。"
                return
            }
            do {
                try await ExternalMirror.shared.syncReminders(mirrorRemindersList())
                mirrorNote = ""
            } catch {
                mirrorReminders = false
                mirrorNote = "この端末にはリマインダーを追加できませんでした。"
            }
        } else {
            try? await ExternalMirror.shared.clearReminders()
            mirrorNote = ""
        }
    }

    private func mirrorEvents() -> [ShiftMirrorPlan.Event] {
        let rows = shifts.map { shift -> (ShiftNotice.Input, String) in
            let span = ShiftNotices.interval(
                day: shift.date,
                startMinutes: shift.startMinutes,
                endMinutes: shift.endMinutes,
                calendar: .current
            )
            return (
                ShiftNotice.Input(id: shift.uuid, name: shift.workplace?.name ?? "勤務", start: span.start, end: span.end),
                shift.workplace?.place ?? ""
            )
        }
        return ShiftMirrorPlan.events(
            rows.map(\.0),
            places: Dictionary(uniqueKeysWithValues: rows.map { ($0.0.id, $0.1) }),
            now: .now
        )
    }

    private func mirrorRemindersList() -> [ShiftMirrorPlan.Reminder] {
        let items = shifts.flatMap { shift in
            let span = ShiftNotices.interval(
                day: shift.date,
                startMinutes: shift.startMinutes,
                endMinutes: shift.endMinutes,
                calendar: .current
            )
            return shift.todos.map { (id: $0.id, title: $0.title, due: span.start, done: $0.done) }
        }
        return ShiftMirrorPlan.reminders(items, now: .now)
    }

    // MARK: Fields

    private func rangeError(_ raw: String, range: Range<Int>, text: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        guard let value = Int(digits), range.contains(value) else { return text }
        return nil
    }

    private func syncFields(_ settings: AppSettings) {
        goalText = String(settings.annualIncomeGoal)
        monthGoalText = String(settings.monthlyIncomeGoal)
        wageText = String(settings.defaultHourlyWage)
        transportText = String(settings.defaultTransportAllowance)
    }

    private func commit(_ raw: String, range: Range<Int>, apply: (Int) -> Void) {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits), range.contains(value) else { return }
        apply(value)
        persist()
    }

    private func persist() {
        try? context.save()
    }

    private func rewrite(_ value: Int, into text: Binding<String>) {
        let current = Int(text.wrappedValue.filter(\.isNumber)) ?? 0
        if current != value {
            text.wrappedValue = String(value)
        }
    }
}
