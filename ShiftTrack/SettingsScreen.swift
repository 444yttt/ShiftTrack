import SwiftData
import SwiftUI

struct SettingsScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]
    @State private var editorID: UUID?
    @State private var showCreator = false
    @State private var confirmReset = false
    @State private var goalText = ""
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

            HStack {
                Text("勤務先")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                LimeCapsuleButton(title: "+ 追加") { showCreator = true }
            }
            .padding(.top, 8)

            VStack(spacing: 12) {
                ForEach(workplaces) { workplace in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(workplace.color)
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workplace.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                            Text("時給 \(Formatters.yen(workplace.hourlyWage))")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("編集") { editorID = workplace.uuid }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.lime)
                    }
                    .padding(14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Text("年収と時給")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            VStack(spacing: 0) {
                numberRow("年収目標", text: $goalText)
                line
                numberRow("新しい勤務先の時給", text: $wageText)
                line
                numberRow("新しい勤務先の交通費", text: $transportText)
            }
            .padding(.horizontal, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear { syncFields(settings) }
            .onChange(of: goalText) { _, new in
                let value = min(100_000_000, Int(new.filter(\.isNumber)) ?? 0)
                if settings.annualIncomeGoal != value { settings.annualIncomeGoal = value }
            }
            .onChange(of: wageText) { _, new in
                let value = min(100_000, Int(new.filter(\.isNumber)) ?? 0)
                if settings.defaultHourlyWage != value { settings.defaultHourlyWage = value }
            }
            .onChange(of: transportText) { _, new in
                let value = min(100_000, Int(new.filter(\.isNumber)) ?? 0)
                if settings.defaultTransportAllowance != value { settings.defaultTransportAllowance = value }
            }
            .onChange(of: settings.annualIncomeGoal) { _, new in
                rewrite(new, into: $goalText)
            }

            Text("表示")
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
                Toggle(isOn: $settings.includeTransport) {
                    Text("交通費を収入に含める")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .tint(Theme.lime)
                .padding(.vertical, 14)
            }
            .padding(.horizontal, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("データ")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Button {
                confirmReset = true
            } label: {
                Text("サンプルデータをリセット")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.destructive, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint("確認してから、勤務先とシフトをサンプルに戻します")

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
        .sheet(isPresented: $showCreator) {
            WorkplaceEditorView(existingID: nil)
        }
        .sheet(isPresented: Binding(
            get: { editorID != nil },
            set: { if !$0 { editorID = nil } }
        )) {
            WorkplaceEditorView(existingID: editorID)
        }
        .alert("サンプルデータに戻しますか？", isPresented: $confirmReset) {
            Button("リセット", role: .destructive) {
                SampleSeeder.reset(in: context)
                PendingImportStore.clear()
                ImportRouter.shared.refreshCount()
                if let settings = settingsRows.first {
                    syncFields(settings)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("入力したシフトと勤務先は消え、最初のサンプルに戻ります。")
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
        wageText = String(settings.defaultHourlyWage)
        transportText = String(settings.defaultTransportAllowance)
    }

    private func rewrite(_ value: Int, into text: Binding<String>) {
        let current = Int(text.wrappedValue.filter(\.isNumber)) ?? 0
        if current != value {
            text.wrappedValue = String(value)
        }
    }
}
