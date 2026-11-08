import SwiftData
import SwiftUI

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]
    @State private var goalText = ""
    @State private var monthGoalText = ""
    @State private var wageText = ""
    @State private var transportText = ""
    @FocusState private var focused: Bool

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
            Text("設定")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Text("勤務先の追加とパターンは「勤務先」タブです。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Text("給料の目標")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            VStack(spacing: 0) {
                numberRow("月間目標", text: $monthGoalText)
                line
                numberRow("年間目標", text: $goalText)
                line
                numberRow("新しい勤務先の時給", text: $wageText)
                line
                numberRow("新しい勤務先の交通費", text: $transportText)
                Text("月間は5,000円以上100万円未満、年間は1万円以上1,000万円未満です。給料画面で月や年ごとに変えた金額が優先されます。")
                    .font(.system(size: 12))
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            VStack(spacing: 0) {
                Toggle(isOn: $settings.weekStartsOnMonday) {
                    Text("週の始まりを月曜にする")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .tint(Theme.lime)
                .padding(.vertical, 14)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle(isOn: $settings.showPaydayOnCalendar) {
                    Text("給料日の表示")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .tint(Theme.lime)
                .padding(.vertical, 14)
                Rectangle().fill(Theme.line).frame(height: 1)
                Toggle(isOn: $settings.includeTransport) {
                    Text("交通費を給料に含める")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .tint(Theme.lime)
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Siri / ショートカット")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("「しふとらっくでシフト表を取り込む」と言うと、読み上げた内容から候補を作り、保存前に確認できます。画像はショートカットの「シフト表の画像を取り込む」に渡せます。どちらも端末内で処理します。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
        .background(Theme.background)
        .focused($focused)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") { focused = false }
            }
        }
    }

    private var line: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private func numberRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Text("¥")
                .foregroundStyle(Theme.muted)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .bold))
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
