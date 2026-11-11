import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @State private var goalText = ""
    @State private var monthGoalText = ""
    @State private var wageText = ""
    @State private var transportText = ""
    @FocusState private var focused: Bool
    @State private var showGuide = false
    @State private var showAboutBubble = false
    @State private var cover: SettingsCover?
    @AppStorage("settings.travelMinutes") private var travelMinutes = 30

    private enum SettingsCover: Identifiable {
        case messages, calendarAccess, about
        var id: String {
            switch self {
            case .messages: "messages"
            case .calendarAccess: "calendar"
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
            .buttonStyle(.plain)

            settingsNoticeCard

            VStack(alignment: .leading, spacing: 10) {
                Text("シフトの重なり")
                    .designFont(16, weight: .bold)
                Stepper("勤務先の移動にかかる時間  \(travelMinutes)分", value: $travelMinutes, in: 0...180, step: 5)
                Text("シフトの時間が重なったときや、違う勤務先の間がこの時間より短いときに、保存の前に確認します。0分にすると、間隔は見ません。")
                    .designFont(16)
                    .foregroundStyle(Theme.muted)
            }
            .padding(ScreenInsets.settings)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, ScreenInsets.settingsOptional)

            VStack(alignment: .leading, spacing: 10) {
                Text("位置情報の許可")
                    .designFont(16, weight: .bold)
                HStack {
                    Text("未設定")
                    Spacer()
                    Button("位置情報を許可する") { openSystemSettings() }
                        .designFont(16, weight: .bold)
                }
            }
            .padding(ScreenInsets.settings)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, ScreenInsets.settingsOptional)

            Button {
                cover = .calendarAccess
            } label: {
                settingsRow("カレンダー・リマインダー")
            }
            .buttonStyle(.plain)
            Button("カレンダーの全件を許可する") {
                Task { _ = await SettingsAccess.requestFullCalendar() }
            }
            .designFont(16, weight: .bold)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, ScreenInsets.settingsOptional)

            aboutRow

            VStack(alignment: .leading, spacing: 10) {
                Text("広告")
                    .designFont(16, weight: .bold)
                HStack {
                    Text("広告")
                    Spacer()
                    Text("非表示")
                        .foregroundStyle(Theme.muted)
                }
                Text("このアプリに広告 SDK はありません。")
                    .designFont(16)
                    .foregroundStyle(Theme.muted)
            }
            .padding(ScreenInsets.settings)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, ScreenInsets.settingsOptional)

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
                .tint(Theme.lime)
                .padding(.vertical, 14)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle(isOn: $settings.showPaydayOnCalendar) {
                    Text("給料日の表示")
                        .designFont(16, weight: .medium)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.lime)
                .padding(.vertical, 14)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle(isOn: $settings.includeTransport) {
                    Text("交通費を給料に含める")
                        .designFont(16, weight: .medium)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.lime)
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
            if !GuideMemory.suppressed && !GuideMemory.seen("settings") {
                showGuide = true
            }
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
                LateTemplateList()
            case .calendarAccess:
                CalendarAccessView()
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
            Text("IN/OUT について")
                .designFont(16, weight: .bold)
            Button {
                showAboutBubble.toggle()
            } label: {
                Text("?")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Theme.lime)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("IN/OUT についての説明")
            Spacer()
            Button {
                cover = .about
            } label: {
                Image(systemName: "arrow.up.right")
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("IN/OUT について")
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

    private var settingsNoticeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("通知")
                .designFont(16, weight: .bold)
                .foregroundStyle(Color.white)
            Text("勤務の終わりに確認")
                .foregroundStyle(Color.white)
            Text("シフトの前に通知")
                .foregroundStyle(Color.white)
            Text("許可はアラート、サウンド、バッジをまとめて求めます。通知の配信はまだ繋いでいません。")
                .designFont(16)
                .foregroundStyle(Color.white.opacity(0.7))
            Button("通知を許可する") {
                Task { _ = await SettingsAccess.requestNotifications() }
            }
            .designFont(16, weight: .bold)
            .foregroundStyle(Theme.lime)
        }
        .padding(ScreenInsets.settings)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, ScreenInsets.settingsOptional)
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
                .foregroundStyle(Theme.lime)
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
