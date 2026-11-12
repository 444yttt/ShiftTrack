import SwiftData
import SwiftUI

/// Three short steps to register a workplace: the store, the pay, and an
/// optional usual shift. Everything can be changed later in the editor.
struct WorkplaceWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]

    @State private var step = 1
    // 1. お店
    @State private var name = ""
    @State private var place = ""
    @State private var phone = ""
    @State private var hours = ""
    @State private var officialURL = ""
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var hasCoordinate = false
    @State private var showImport = false
    // 2. 給料
    @State private var wage = ""
    @State private var transport = ""
    @State private var closingDay = 0
    @State private var paydayOffset = 1
    @State private var paydayDay = 25
    @State private var night = true
    @State private var overtime = true
    @State private var legalBreak = true
    // 3. よく入る時間
    @State private var patternName = ""
    @State private var startMinute = 17 * 60
    @State private var endMinute = 22 * 60
    @State private var weekdays: Set<Int> = []
    @AppStorage(ShiftNoticeRefresh.beforeKey) private var notify = false
    @State private var error = ""
    @State private var loaded = false
    @FocusState private var typing: Bool

    private let steps = ["お店", "時給と給料日", "よく入る時間"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.m) {
                        switch step {
                        case 1: stepOne
                        case 2: stepTwo
                        default: stepThree
                        }
                        if !error.isEmpty {
                            InfoNote(text: error, tone: .error)
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)
                footer
            }
            .background(Theme.paper)
            .navigationTitle("勤務先を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("wizard.close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        typing = false
                        Keyboard.dismiss()
                    }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onAppear(perform: load)
            .sheet(isPresented: $showImport) {
                WorkplaceImportView { draft in
                    if !draft.name.isEmpty { name = draft.name }
                    if !draft.address.isEmpty { place = draft.address }
                    if !draft.phone.isEmpty { phone = draft.phone }
                    hours = draft.hours
                    officialURL = draft.officialURL
                    latitude = draft.latitude
                    longitude = draft.longitude
                    hasCoordinate = draft.hasCoordinate
                }
            }
        }
    }

    // MARK: Progress and footer

    private var progress: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("ステップ \(step) / \(steps.count)：\(steps[step - 1])")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("wizard.step")
            HStack(spacing: Space.xxs) {
                ForEach(1...steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.signalInk : Theme.sunken)
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s)
    }

    private var footer: some View {
        HStack(spacing: Space.s) {
            SecondaryButton(title: step == 1 ? "やめる" : "戻る", identifier: "wizard.back") {
                error = ""
                if step == 1 { dismiss() } else { step -= 1 }
            }
            PrimaryButton(title: step == steps.count ? "登録する" : "次へ", identifier: step == steps.count ? "wizard.finish" : "wizard.next") {
                advance()
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s)
        .background(Theme.paper)
    }

    private func header(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.onSignal)
                .frame(width: 56, height: 56)
                .background(Theme.signal, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.screenTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(detail)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Space.xs)
    }

    // MARK: Steps

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header(
                systemImage: "storefront",
                title: "働くお店",
                detail: "名前だけでも登録できます。住所と電話番号を入れると、ホームの「地図」「電話」「メッセージ」が使えます。"
            )
            Card {
                LabeledField(label: "お店の名前（必須）", text: $name, prompt: "例：架空茶房 北窓", identifier: "field.名前")
                    .focused($typing)
                LabeledField(label: "住所（任意）", text: $place, prompt: "例：架空県北窓町1-2", identifier: "field.住所")
                    .focused($typing)
                LabeledField(label: "電話番号（任意）", text: $phone, prompt: "例：03-0000-0000", keyboard: .phonePad, identifier: "field.電話番号")
                    .focused($typing)
            }
            SecondaryButton(title: "ショップカードの写真や地図のリンクから読む", systemImage: "text.viewfinder", identifier: "wizard.photo") {
                showImport = true
            }
            InfoNote(text: "読み取りはこの端末の中で行い、入れる前に結果を確かめられます。")
        }
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header(
                systemImage: "yensign",
                title: "時給と給料日",
                detail: "見込みの計算に使います。あとから勤務先の編集で変えられます。"
            )
            Card {
                YenField(label: "時給", text: $wage, prompt: "例：1200", helper: "ホームの「いままでの稼ぎ」に使います。", identifier: "field.時給")
                YenField(label: "交通費（1回あたり）", text: $transport, prompt: "0", identifier: "field.交通費")
            }
            SectionHeader(title: "締め日と給料日")
            Card {
                PickerRow(label: "締め日", selection: $closingDay, identifier: "wizard.closingDay") {
                    Text("末日").tag(0)
                    ForEach(1...30, id: \.self) { Text("\($0)日").tag($0) }
                }
                PickerRow(label: "給料日の月", selection: $paydayOffset, identifier: "wizard.paydayMonth") {
                    Text("締めた月").tag(0)
                    Text("翌月").tag(1)
                    Text("翌々月").tag(2)
                }
                PickerRow(label: "給料日", selection: $paydayDay, identifier: "wizard.paydayDay") {
                    Text("末日").tag(0)
                    ForEach(1...31, id: \.self) { Text("\($0)日").tag($0) }
                }
                InfoNote(text: PaySummary.monthly(closingDay: closingDay, paydayDay: paydayDay, monthOffset: paydayOffset))
            }
            SectionHeader(title: "割増と休憩")
            Card(spacing: Space.s) {
                ToggleRow(title: "深夜（22時〜5時）に25%上乗せ", helper: "法律で決まっている深夜の割増です。", isOn: $night, identifier: "wizard.night")
                RowDivider()
                ToggleRow(title: "1日8時間を超えた分に25%上乗せ", helper: "残業の割増です。", isOn: $overtime, identifier: "wizard.overtime")
                RowDivider()
                ToggleRow(title: "法定の休憩を入れる", helper: "6時間を超える勤務は45分、8時間を超える勤務は60分の休憩を初期値にします。", isOn: $legalBreak, identifier: "wizard.break")
            }
        }
    }

    private var stepThree: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header(
                systemImage: "calendar.badge.clock",
                title: "よく入る時間（任意）",
                detail: "よく入る時間をパターンにしておくと、カレンダーやホームから1回で置けます。なければ空のまま登録できます。"
            )
            Card {
                LabeledField(label: "パターンの名前", text: $patternName, prompt: "例：遅番", identifier: "field.シフト名")
                    .focused($typing)
                HStack(alignment: .top, spacing: Space.xs) {
                    MinutesTimePicker(title: "開始", minutes: $startMinute)
                    MinutesTimePicker(title: "終了", minutes: $endMinute)
                }
                WeekdayPicker(label: "毎週入る曜日（任意）", days: $weekdays, helper: "選ぶと「曜日で入れる」の型にもなります。")
            }
            Card {
                ToggleRow(title: "シフトの前に知らせる", helper: "開始の30分前に通知します。設定でいつでも変えられます。", isOn: $notify, identifier: "wizard.notify")
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let settings = settingsRows.first {
            wage = settings.defaultHourlyWage > 0 ? String(settings.defaultHourlyWage) : ""
            transport = String(settings.defaultTransportAllowance)
        }
    }

    private func advance() {
        typing = false
        switch step {
        case 1:
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                error = WorkplaceEditorCheck.emptyName
                return
            }
            error = ""
            step = 2
        case 2:
            guard (Int(wage.filter(\.isNumber)) ?? 0) > 0 else {
                error = "時給を入れてください。"
                return
            }
            error = ""
            step = 3
        default:
            save()
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            step = 1
            error = WorkplaceEditorCheck.emptyName
            return
        }
        let wageValue = min(100_000, Int(wage.filter(\.isNumber)) ?? 0)
        let used = Set(workplaces.map(\.colorHex))
        let workplace = Workplace(
            name: trimmed,
            colorHex: Theme.palette.first { !used.contains($0) } ?? Theme.palette[workplaces.count % Theme.palette.count],
            hourlyWage: wageValue,
            transportAllowance: min(100_000, Int(transport.filter(\.isNumber)) ?? 0)
        )
        workplace.place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.openingHours = hours
        workplace.officialURL = officialURL
        workplace.latitude = latitude
        workplace.longitude = longitude
        workplace.hasMapCoordinate = hasCoordinate
        workplace.closingDay = closingDay
        workplace.paydayMonthOffset = paydayOffset
        workplace.paydayDay = paydayDay
        workplace.customBreaks = !legalBreak
        workplace.nightPayEnabled = night
        workplace.nightWage = 0
        workplace.nightRatePercent = night ? 25 : 0
        workplace.overtimeEnabled = overtime
        workplace.overtimeAfterMinutes = 8 * 60
        workplace.overtimeExtra = 0
        workplace.overtimeRatePercent = overtime ? 25 : 0
        context.insert(workplace)
        let patternTitle = patternName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !patternTitle.isEmpty {
            context.insert(ShiftPart(
                name: patternTitle,
                workplaceUUID: workplace.uuid,
                startMinute: startMinute,
                endMinute: endMinute,
                breakMinutes: 0,
                colorHex: workplace.colorHex,
                breakModeRaw: legalBreak ? PatternBreakMode.workplace.rawValue : PatternBreakMode.fixed.rawValue
            ))
            if !weekdays.isEmpty {
                context.insert(ShiftPattern(
                    name: patternTitle,
                    workplaceUUID: workplace.uuid,
                    startMinutes: startMinute,
                    endMinutes: endMinute,
                    breakMinutes: 0,
                    weekdays: weekdays,
                    breakModeRaw: legalBreak ? PatternBreakMode.workplace.rawValue : PatternBreakMode.fixed.rawValue
                ))
            }
        }
        do {
            try context.save()
        } catch {
            self.error = "保存できませんでした。少し待ってから、もう一度試してください。"
            return
        }
        if notify {
            Task { _ = await SettingsAccess.requestNotifications() }
        }
        dismiss()
    }
}
