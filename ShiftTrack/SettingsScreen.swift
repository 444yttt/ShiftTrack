import CoreLocation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var showGuide = false
    @State private var showAboutBubble = false
    @State private var cover: SettingsCover?
    @State private var locationStatus = LocationPrompt.label(LocationPrompt.shared.status)
    @State private var settingsNote = ""
    @AppStorage("settings.travelMinutes") private var travelMinutes = 30
    @AppStorage(ShiftNoticeRefresh.beforeKey) private var notifyBefore = false
    @AppStorage(ShiftNoticeRefresh.endKey) private var notifyAtEnd = false
    @AppStorage(ShiftMirrorRefresh.calendarKey) private var mirrorCalendar = false
    @AppStorage(ShiftMirrorRefresh.reminderKey) private var mirrorReminders = false

    private enum SettingsCover: Identifiable {
        case messages, about
        var id: String {
            switch self {
            case .messages: "messages"
            case .about: "about"
            }
        }
    }

    var body: some View {
        if let settings = settingsRows.first {
            form(settings)
        } else {
            Theme.background
        }
    }

    private func form(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        return ScreenScroll {
            HStack {
                Text("設定")
                    .designFont(16, weight: .black)
                    .foregroundStyle(Theme.ink)
                Spacer()
                HelpButton { showGuide = true }
            }
            .padding(.top, ScreenInsets.settingsOptional)

            Button {
                cover = .messages
            } label: {
                settingsRow("メッセージの文章")
            }
            .buttonStyle(SettingsPressStyle())
            .accessibilityIdentifier("settings.messages")

            noticeCard

            VStack(alignment: .leading, spacing: 10) {
                Text("シフトの重なり")
                    .designFont(16, weight: .bold)
                Stepper("勤務先の移動にかかる時間  \(travelMinutes)分", value: $travelMinutes, in: 0...180, step: 5)
                    .accessibilityIdentifier("settings.travel")
                Text("シフトの時間が重なったときや、違う勤務先の間がこの時間より短いときに、保存の前に確認します。0分にすると、間隔は見ません。")
                    .designFont(16)
                    .foregroundStyle(Theme.muted)
            }
            .padding(ScreenInsets.settings)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, ScreenInsets.settingsOptional)
            .sensoryFeedback(.selection, trigger: travelMinutes)

            locationCard
            mirrorCard
            if !settingsNote.isEmpty {
                Text(settingsNote)
                    .designFont(16)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, ScreenInsets.settingsOptional)
            }

            aboutRow

            Text("勤務先の追加とパターンは「勤務先」タブです。")
                .designFont(16)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ScreenInsets.settingsOptional)

            Text("給料の目標")
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ScreenInsets.settingsOptional)

            VStack(spacing: 0) {
                numberRow("月間目標", text: $monthGoalText)
                line
                numberRow("年間目標", text: $goalText)
                line
                numberRow("新しい勤務先の時給", text: $wageText)
                line
                numberRow("新しい勤務先の交通費", text: $transportText)
                Text("月間は5,000円以上100万円未満、年間は1万円以上1,000万円未満です。給料画面で月や年ごとに変えた金額が優先されます。")
                    .designFont(16)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                commit(new, range: 0...100_000) { value in
                    if settings.defaultHourlyWage != value { settings.defaultHourlyWage = value }
                }
            }
            .onChange(of: transportText) { _, new in
                commit(new, range: 0...100_000) { value in
                    if settings.defaultTransportAllowance != value { settings.defaultTransportAllowance = value }
                }
            }
            .onChange(of: settings.weekStartsOnMonday) { _, _ in persist() }
            .onChange(of: settings.showPaydayOnCalendar) { _, _ in persist() }
            .onChange(of: settings.includeTransport) { _, _ in persist() }
            .onChange(of: settings.annualIncomeGoal) { _, new in
                rewrite(new, into: $goalText)
            }

            Text("カレンダーの設定")
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ScreenInsets.settingsOptional)

            VStack(spacing: 0) {
                Toggle(isOn: $settings.weekStartsOnMonday) {
                    Text("週の始まりを月曜にする")
                        .designFont(16, weight: .medium)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accentText)
                .padding(.vertical, 14)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle(isOn: $settings.showPaydayOnCalendar) {
                    Text("給料日の表示")
                        .designFont(16, weight: .medium)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accentText)
                .padding(.vertical, 14)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle(isOn: $settings.includeTransport) {
                    Text("交通費を給料に含める")
                        .designFont(16, weight: .medium)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accentText)
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Siri / ショートカット")
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.ink)
                Text("「しふとらっくでシフト表を取り込む」と言うと、読み上げた内容から候補を作り、保存前に確認できます。画像はショートカットの「シフト表の画像を取り込む」に渡せます。どちらも端末内で処理します。")
                    .designFont(16)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, ScreenInsets.settingsOptional)
        }
        .background(Theme.background)
        .focused($focused)
        .onAppear {
            locationStatus = LocationPrompt.label(LocationPrompt.shared.status)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: cover?.id)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: notifyBefore)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: notifyAtEnd)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: mirrorCalendar)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: mirrorReminders)
        .onChange(of: showGuide) { _, on in
            ScreenDim.shared.isOn = on
        }
        .overlay {
            if showGuide {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    GuideCard(
                        page: 1,
                        total: GuideCopy.settings.count,
                        text: GuideCopy.settings[0],
                        onBack: nil,
                        onNext: {
                            GuideMemory.mark("settings")
                            showGuide = false
                        },
                        onClose: {
                            GuideMemory.mark("settings")
                            showGuide = false
                        }
                    )
                }
            }
        }
        .sheet(item: $cover) { destination in
            switch destination {
            case .messages:
                MessageTemplateEditor()
            case .about:
                AboutSheet()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focused = false }
            }
        }
    }

    private func settingsRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .designFont(16, weight: .bold)
            Spacer()
            Image(systemName: "arrow.up.right")
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.muted)
        }
        .padding(ScreenInsets.settings)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, ScreenInsets.settingsOptional)
    }

    private var aboutRow: some View {
        HStack(spacing: 8) {
            Text("しふとらっくについて")
                .designFont(16, weight: .bold)
            Button {
                showAboutBubble.toggle()
            } label: {
                Text("?")
                    .designFont(18, weight: .black)
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("しふとらっくについての説明")
            Spacer()
            Button {
                cover = .about
            } label: {
                Image(systemName: "arrow.up.right")
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("しふとらっくについて")
        }
        .padding(ScreenInsets.settings)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, ScreenInsets.settingsOptional)
        .zIndex(showAboutBubble ? 2 : 0)
        .overlay(alignment: .bottomLeading) {
            if showAboutBubble {
                Text(AboutBubble.body)
                    .designFont(13)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background {
                        SpeechTail(cornerRadius: ScreenInsets.aboutBubbleCorner)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.16), radius: 10, y: 3)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: -36)
                    .accessibilityIdentifier("about.bubble")
            }
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private var noticeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("通知")
                .designFont(16, weight: .bold)
                .foregroundStyle(Color.white)
            Toggle("勤務の終わりに確認", isOn: $notifyAtEnd)
                .tint(Theme.accentText)
                .accessibilityIdentifier("settings.notifyEnd")
            Text("終了時刻に、この端末から知らせます。")
                .designFont(16)
                .foregroundStyle(Color.white.opacity(0.7))
            Toggle("シフトの前に通知", isOn: $notifyBefore)
                .tint(Theme.accentText)
                .accessibilityIdentifier("settings.notifyBefore")
            Text("開始の30分前に知らせます。")
                .designFont(16)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(ScreenInsets.settings)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink)
        .foregroundStyle(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, ScreenInsets.settingsOptional)
        .onChange(of: notifyAtEnd) { _, _ in Task { await updateNotices() } }
        .onChange(of: notifyBefore) { _, _ in Task { await updateNotices() } }
        .sensoryFeedback(.selection, trigger: notifyAtEnd)
        .sensoryFeedback(.selection, trigger: notifyBefore)
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("位置情報の許可")
                .designFont(16, weight: .bold)
            Text(locationStatus)
                .foregroundStyle(Theme.muted)
            Text("勤務先の住所を、今いる場所から入れるときに使います。")
                .designFont(16)
                .foregroundStyle(Theme.muted)
            Button(locationStatus == "未設定" ? "位置情報を許可する" : "設定を開く") {
                if locationStatus == "未設定" {
                    LocationPrompt.shared.onChange = {
                        locationStatus = LocationPrompt.label(LocationPrompt.shared.status)
                    }
                    LocationPrompt.shared.request()
                } else {
                    openSystemSettings()
                }
            }
            .buttonStyle(SettingsPressStyle())
            .accessibilityIdentifier("settings.location")
        }
        .padding(ScreenInsets.settings)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, ScreenInsets.settingsOptional)
    }

    private var mirrorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カレンダーとリマインダー")
                .designFont(16, weight: .bold)
            Toggle("シフトをカレンダーに入れる", isOn: $mirrorCalendar)
                .tint(Theme.accentText)
                .accessibilityIdentifier("settings.calendar")
            Toggle("やることをリマインダーに入れる", isOn: $mirrorReminders)
                .tint(Theme.accentText)
                .accessibilityIdentifier("settings.reminders")
            Text("オンにすると「しふとらっく」というカレンダーとリマインダーだけを更新します。")
                .designFont(16)
                .foregroundStyle(Theme.muted)
        }
        .padding(ScreenInsets.settings)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, ScreenInsets.settingsOptional)
        .onChange(of: mirrorCalendar) { _, on in Task { await updateCalendar(on) } }
        .onChange(of: mirrorReminders) { _, on in Task { await updateReminders(on) } }
        .sensoryFeedback(.selection, trigger: mirrorCalendar)
        .sensoryFeedback(.selection, trigger: mirrorReminders)
    }

    private func updateNotices() async {
        if notifyBefore || notifyAtEnd {
            let allowed = await SettingsAccess.requestNotifications()
            if !allowed {
                notifyBefore = false
                notifyAtEnd = false
                settingsNote = "通知が許可されていません。設定アプリから変更できます。"
                await ShiftNoticeRefresh.apply(shifts: shifts)
                return
            }
        }
        settingsNote = ""
        await ShiftNoticeRefresh.apply(shifts: shifts)
    }

    private func updateCalendar(_ on: Bool) async {
        if on {
            let allowed = await ExternalMirror.shared.requestEvents()
            guard allowed else {
                mirrorCalendar = false
                settingsNote = "カレンダーが許可されていません。設定アプリから変更できます。"
                return
            }
            do {
                try ExternalMirror.shared.syncEvents(mirrorEvents())
                settingsNote = ""
            } catch {
                mirrorCalendar = false
                settingsNote = "この端末にはカレンダーを追加できませんでした。"
            }
        } else {
            try? ExternalMirror.shared.clearEvents()
            settingsNote = ""
        }
    }

    private func updateReminders(_ on: Bool) async {
        if on {
            let allowed = await ExternalMirror.shared.requestReminders()
            guard allowed else {
                mirrorReminders = false
                settingsNote = "リマインダーが許可されていません。設定アプリから変更できます。"
                return
            }
            do {
                try await ExternalMirror.shared.syncReminders(mirrorRemindersList())
                settingsNote = ""
            } catch {
                mirrorReminders = false
                settingsNote = "この端末にはリマインダーを追加できませんでした。"
            }
        } else {
            try? await ExternalMirror.shared.clearReminders()
            settingsNote = ""
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

    private var line: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private func numberRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .designFont(16, weight: .medium)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("¥")
                .foregroundStyle(Theme.muted)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.accentText)
                .frame(width: 110)
                .focused($focused)
        }
        .padding(.vertical, 14)
    }

    private func syncFields(_ settings: AppSettings) {
        goalText = String(settings.annualIncomeGoal)
        monthGoalText = String(settings.monthlyIncomeGoal)
        wageText = String(settings.defaultHourlyWage)
        transportText = String(settings.defaultTransportAllowance)
    }

    private func commit(_ raw: String, range: some RangeExpression<Int>, apply: (Int) -> Void) {
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

private struct SettingsPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduce && configuration.isPressed ? 0.98 : 1)
            .animation(reduce ? nil : .smooth(duration: 0.16), value: configuration.isPressed)
    }
}
