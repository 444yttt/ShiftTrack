import SwiftData
import SwiftUI

/// How a premium is set. Stored with the existing fields: a yen amount, or a
/// percent on top of the hourly wage when the amount is 0 (see `PayRates`).
enum PremiumMode: String, CaseIterable, Identifiable {
    case off, percent, amount
    var id: String { rawValue }
}

/// Plain-language summary of a monthly closing and payday.
enum PaySummary {
    static func monthly(closingDay: Int, paydayDay: Int, monthOffset: Int) -> String {
        let pay = paydayDay <= 0 ? "末日" : "\(paydayDay)日"
        let when: String
        switch monthOffset {
        case 0: when = "その月の"
        case 1: when = "翌月の"
        default: when = "翌々月の"
        }
        if closingDay <= 0 {
            return "毎月1日から末日までの勤務分を、\(when)\(pay)に受け取ります。"
        }
        let next = closingDay >= 31 ? 1 : closingDay + 1
        return "前の月の\(next)日から\(closingDay)日までの勤務分を、締めた月から見て\(when)\(pay)に受け取ります。"
    }
}

/// 勤務先を編集 / 勤務先を追加. One place for each setting, a visible label on
/// every control, and a line that says what each section changes.
struct WorkplaceEditorView: View {
    var existingID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]

    // 基本
    @State private var name = ""
    @State private var colorHex = Theme.palette[0]
    @State private var genre = ""
    // 連絡先と場所
    @State private var place = ""
    @State private var phone = ""
    @State private var openingHours = ""
    @State private var officialURL = ""
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var hasCoordinate = false
    @State private var pinFromHere = false
    @State private var locating = false
    @State private var locateNote = ""
    // 給料
    @State private var payIsDaily = false
    @State private var wageText = "1200"
    @State private var dailyText = "8000"
    @State private var transportText = "500"
    // 締め日と給料日
    @State private var payCycle: PayCycle = .month
    @State private var closingDay = 0
    @State private var paydayOffset = 1
    @State private var paydayDay = 25
    @State private var payWeekday = 0
    // 割増
    @State private var nightMode: PremiumMode = .off
    @State private var nightRate = 25
    @State private var nightText = ""
    @State private var nightStart = 22 * 60
    @State private var nightEnd = 5 * 60
    @State private var holidayMode: PremiumMode = .off
    @State private var holidayRate = 25
    @State private var holidayText = ""
    @State private var holidayDays: Set<Int> = [1, 7]
    @State private var holidayNightOn = false
    @State private var holidayNightText = ""
    @State private var holidayNightStart = 22 * 60
    @State private var holidayNightEnd = 5 * 60
    @State private var overtimeMode: PremiumMode = .off
    @State private var overtimeRate = 25
    @State private var overtimeHours = 8
    @State private var overtimePerHour = true
    @State private var overtimeText = ""
    // 休憩
    @State private var customBreaks = false
    @State private var breakRules: [InOutRecovered.BreakRule] = []
    // 打刻の丸め
    @State private var roundingUnit = 1
    @State private var roundingStart = 0
    @State private var roundingEnd = 0
    @State private var earlyFromPlan = false
    @State private var showsRounding = false
    // Kept as stored; the redesigned editor has no control for them.
    @State private var holidayRates = Array(repeating: 0, count: 7)
    @State private var wageHistory: [Workplace.WageHistoryEntry] = []
    @State private var payRuleDates: [Date] = []
    @State private var wageBands: [Workplace.WageBandEntry] = []
    // メモ
    @State private var notes = ""

    @State private var error = ""
    @State private var confirmDelete = false
    @State private var showTemplate = false
    @State private var loaded = false
    @FocusState private var typing: Bool

    private var existing: Workplace? { workplaces.first { $0.uuid == existingID } }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                if !error.isEmpty {
                    InfoNote(text: error, tone: .error)
                        .padding(.top, Space.xs)
                        .accessibilityIdentifier("workplace.error.top")
                }
                basics
                contact
                pay
                payday
                premiums
                breaks
                message
                details
                memo
                if !error.isEmpty {
                    InfoNote(text: error, tone: .error)
                }
                PrimaryButton(title: existing == nil ? "この内容で追加" : "変更を保存", identifier: "workplace.save") {
                    save()
                }
                if existing != nil {
                    DestructiveButton(title: "この勤務先を削除", identifier: "workplace.delete") {
                        confirmDelete = true
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle(existing == nil ? "勤務先を追加" : "勤務先を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("workplace.save.top")
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
            .onChange(of: customBreaks) { _, on in
                if on, breakRules.isEmpty {
                    breakRules = InOutRecovered.legalBreakRules
                }
            }
            .sheet(isPresented: $showTemplate) {
                MessageTemplateEditor()
            }
            .alert("この勤務先を削除しますか？", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) { deleteWorkplace() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この勤務先のシフトも一緒に消えます。元に戻せません。")
            }
        }
    }

    // MARK: Sections

    private var basics: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "基本")
            Card {
                LabeledField(label: "勤務先の名前（必須）", text: $name, prompt: "例：架空茶房 北窓", identifier: "field.名前")
                    .focused($typing)
                colorPicker
                LabeledField(label: "ジャンル（任意）", text: $genre, prompt: "例：カフェ", identifier: "field.ジャンル")
                    .focused($typing)
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("カレンダーでの色")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xxs) {
                    ForEach(Array(Theme.palette.enumerated()), id: \.element) { index, hex in
                        let selected = colorHex == hex
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                                .overlay {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.black))
                                            .foregroundStyle(Color.readable(onHex: hex))
                                    }
                                }
                                .padding(3)
                                .overlay {
                                    if selected {
                                        Circle().stroke(Theme.ink, lineWidth: 2)
                                    }
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("色 \(index + 1)")
                        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                    }
                }
            }
        }
    }

    private var contact: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "連絡先と場所", detail: "ホームと勤務先の「地図」「電話」「メッセージ」ボタンで使います。空のままだと、そのボタンは押せません。")
            Card {
                LabeledField(
                    label: "住所",
                    text: $place,
                    prompt: "例：架空県北窓町1-2",
                    helper: "「地図」ボタンで、この住所を Apple のマップで開きます。",
                    identifier: "field.住所"
                )
                .focused($typing)
                SecondaryButton(
                    title: locating ? "現在地を調べています…" : "現在地から住所を入れる",
                    systemImage: "location",
                    identifier: "workplace.locate"
                ) {
                    Task { await fillFromHere() }
                }
                .disabled(locating)
                if !locateNote.isEmpty {
                    InfoNote(text: locateNote, tone: locateNote.hasPrefix("入れました") ? .plain : .warning)
                }
                LabeledField(
                    label: "電話番号",
                    text: $phone,
                    prompt: "例：03-0000-0000",
                    helper: "「電話」と「メッセージ」ボタンで使います。",
                    keyboard: .phonePad,
                    identifier: "field.電話番号"
                )
                .focused($typing)
                LabeledField(label: "営業時間（任意）", text: $openingHours, prompt: "例：10:00–20:00", identifier: "field.営業時間")
                    .focused($typing)
                LabeledField(label: "公式サイト（任意）", text: $officialURL, prompt: "https://", keyboard: .URL, identifier: "field.公式サイト")
                    .focused($typing)
            }
        }
    }

    private var pay: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "給料")
            Card {
                SegmentedRow(label: "給料の形", selection: $payIsDaily, identifier: "workplace.payKind") {
                    Text("時給").tag(false)
                    Text("日給").tag(true)
                }
                if payIsDaily {
                    YenField(
                        label: "日給（1回あたり）",
                        text: $dailyText,
                        helper: "日給の勤務先では、休憩で給料は減りません。",
                        identifier: "field.日給"
                    )
                } else {
                    YenField(
                        label: "時給",
                        text: $wageText,
                        helper: "ホームの「いままでの稼ぎ」と、給料の見込みに使います。",
                        identifier: "field.時給"
                    )
                }
                YenField(
                    label: "交通費（1回あたり）",
                    text: $transportText,
                    helper: "設定で「交通費を給料に含める」がオンのとき、シフトごとに足します。",
                    identifier: "field.交通費"
                )
            }
        }
    }

    private var payday: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "締め日と給料日", detail: "給料タブで、どの月の給料として数えるかに使います。")
            Card {
                SegmentedRow(label: "支払いの周期", selection: $payCycle, identifier: "workplace.payCycle") {
                    ForEach(PayCycle.allCases) { cycle in
                        Text(cycle.title).tag(cycle)
                    }
                }
                switch payCycle {
                case .month:
                    PickerRow(label: "締め日", selection: $closingDay, identifier: "workplace.closingDay") {
                        Text("末日").tag(0)
                        ForEach(1...30, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    PickerRow(label: "給料日の月", selection: $paydayOffset, identifier: "workplace.paydayMonth") {
                        Text("締めた月").tag(0)
                        Text("翌月").tag(1)
                        Text("翌々月").tag(2)
                    }
                    PickerRow(label: "給料日", selection: $paydayDay, identifier: "workplace.paydayDay") {
                        Text("末日").tag(0)
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PaySummary.monthly(closingDay: closingDay, paydayDay: paydayDay, monthOffset: paydayOffset))
                            .font(AppFont.body.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("workplace.payday.summary")
                        Text(nextPaydayLine)
                            .font(AppFont.helper)
                            .foregroundStyle(Theme.ink2)
                        if paydayDay > 28 || closingDay > 28 {
                            InfoNote(text: "その日がない月は、月の末日として数えます。")
                        }
                        if PayScheduleMath.breaksInShortFebruary(closingDay: closingDay, paydayDay: paydayDay, monthOffset: paydayOffset, calendar: ShiftOverlap.tokyo) {
                            InfoNote(text: "2月は、給料日が締め日より前か同じ日になります。", tone: .warning)
                        }
                    }
                    .padding(Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                case .week:
                    PickerRow(
                        label: "支払う曜日",
                        selection: $payWeekday,
                        helper: "その週の勤務分を、選んだ曜日に受け取る計算にします。",
                        identifier: "workplace.payWeekday"
                    ) {
                        Text("選んでください").tag(0)
                        ForEach(1...7, id: \.self) { weekday in
                            Text(Self.weekdayNames[weekday] + "曜日").tag(weekday)
                        }
                    }
                case .day:
                    InfoNote(text: "勤務した日に受け取る計算にします。")
                }
            }
        }
    }

    private var premiums: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "割増", detail: "深夜・休日・残業の時間に上乗せする分です。割増率は時給に対する割合です。")
            Card(spacing: Space.s) {
                if payIsDaily {
                    InfoNote(text: "日給の勤務先では、深夜の割増は計算しません。休日と残業は、日給とは別に足せます。")
                } else {
                    premiumBlock(
                        title: "深夜",
                        helper: "決まった時間帯の勤務に上乗せします。",
                        mode: $nightMode,
                        rate: $nightRate,
                        amount: $nightText,
                        amountLabel: "深夜の時給",
                        identifier: "workplace.night"
                    )
                    if nightMode != .off {
                        timeWindow(startTitle: "深夜の始まり", start: $nightStart, endTitle: "深夜の終わり", end: $nightEnd)
                    }
                    RowDivider()
                }
                premiumBlock(
                    title: "休日",
                    helper: "選んだ曜日の勤務に上乗せします。",
                    mode: $holidayMode,
                    rate: $holidayRate,
                    amount: $holidayText,
                    amountLabel: "休日の時給",
                    identifier: "workplace.holiday"
                )
                if holidayMode != .off {
                    WeekdayPicker(label: "休日にする曜日", days: $holidayDays)
                    if !payIsDaily, nightMode != .off {
                        ToggleRow(
                            title: "休日の深夜は別の時給にする",
                            helper: "オフのときは、休日と深夜の割増率を足して計算します。",
                            isOn: $holidayNightOn,
                            identifier: "workplace.holidayNight"
                        )
                        if holidayNightOn {
                            YenField(label: "休日の深夜の時給", text: $holidayNightText, identifier: "field.休日深夜")
                            timeWindow(startTitle: "休日深夜の始まり", start: $holidayNightStart, endTitle: "休日深夜の終わり", end: $holidayNightEnd)
                        }
                    }
                }
                RowDivider()
                premiumBlock(
                    title: "残業",
                    helper: "1回の勤務が決まった時間を超えた分に上乗せします。",
                    mode: $overtimeMode,
                    rate: $overtimeRate,
                    amount: $overtimeText,
                    amountLabel: overtimePerHour ? "1時間あたりの残業手当" : "1回あたりの残業手当",
                    amountTitle: "金額で指定",
                    identifier: "workplace.overtime"
                )
                if overtimeMode != .off {
                    StepperRow(
                        label: "残業になるまでの時間",
                        valueText: "\(overtimeHours)時間",
                        value: $overtimeHours,
                        range: 1...16,
                        identifier: "workplace.overtime.after"
                    )
                    if overtimeMode == .amount {
                        SegmentedRow(label: "手当の数え方", selection: $overtimePerHour, identifier: "workplace.overtime.unit") {
                            Text("1時間ごと").tag(true)
                            Text("1回ごと").tag(false)
                        }
                    }
                }
            }
        }
    }

    private func premiumBlock(
        title: String,
        helper: String,
        mode: Binding<PremiumMode>,
        rate: Binding<Int>,
        amount: Binding<String>,
        amountLabel: String,
        amountTitle: String = "時給で指定",
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SegmentedRow(label: "\(title)の割増", selection: mode, helper: helper, identifier: identifier) {
                Text("なし").tag(PremiumMode.off)
                Text("割増率").tag(PremiumMode.percent)
                Text(amountTitle).tag(PremiumMode.amount)
            }
            switch mode.wrappedValue {
            case .off:
                EmptyView()
            case .percent:
                StepperRow(
                    label: "割増率",
                    valueText: "\(rate.wrappedValue)%",
                    value: rate,
                    range: 1...100,
                    helper: "時給 \(Formatters.yen(previewWage)) なら \(Formatters.yen(PayRates.raised(previewWage, percent: rate.wrappedValue))) で計算します。",
                    identifier: "\(identifier).rate"
                )
            case .amount:
                YenField(label: amountLabel, text: amount, identifier: "\(identifier).amount")
            }
        }
    }

    private func timeWindow(startTitle: String, start: Binding<Int>, endTitle: String, end: Binding<Int>) -> some View {
        HStack(alignment: .top, spacing: Space.xs) {
            MinutesTimePicker(title: startTitle, minutes: start)
            MinutesTimePicker(title: endTitle, minutes: end)
        }
    }

    private var breaks: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "休憩", detail: "シフトを入れるときの休憩の初期値です。保存してあるシフトの休憩は変わりません。")
            Card {
                SegmentedRow(label: "休憩の決め方", selection: $customBreaks, identifier: "workplace.breaks") {
                    Text("法定の目安").tag(false)
                    Text("この勤務先の決まり").tag(true)
                }
                if customBreaks {
                    InfoNote(text: "勤務時間が「この時間を超えたら」を超えると、その休憩を入れます。いくつか当てはまるときは、いちばん長い時間の決まりを使います。")
                    BreakRuleEditor(rules: $breakRules)
                } else {
                    InfoNote(text: "6時間を超える勤務は45分、8時間を超える勤務は60分の休憩を入れます。")
                }
            }
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "連絡メッセージ")
            Card {
                Button {
                    showTemplate = true
                } label: {
                    NavRow(
                        systemImage: "text.bubble",
                        title: "メッセージのひな形",
                        subtitle: "「メッセージ」ボタンで使う文章です。宛名にはこの勤務先の名前が入ります（送る前に変えられます）。"
                    )
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("workplace.template")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "詳細")
            Card {
                DisclosureGroup(isExpanded: $showsRounding) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        InfoNote(text: "出勤・退勤の打刻を記録したシフトで、給料に数える時刻の目安を出すときの決まりです。予定の時刻と見込みは変わりません。")
                        PickerRow(label: "丸める単位", selection: $roundingUnit, identifier: "workplace.rounding.unit") {
                            ForEach(roundingUnits, id: \.self) { unit in
                                Text(unit < 2 ? "丸めない" : "\(unit)分").tag(unit)
                            }
                        }
                        if roundingUnit >= 2 {
                            roundingPicker("出勤の時刻", selection: $roundingStart, identifier: "workplace.rounding.start")
                            roundingPicker("退勤の時刻", selection: $roundingEnd, identifier: "workplace.rounding.end")
                        }
                        ToggleRow(
                            title: "早く来ても予定の開始から数える",
                            helper: "予定より早い出勤は、予定の開始時刻から数えます。",
                            isOn: $earlyFromPlan,
                            identifier: "workplace.earlyFromPlan"
                        )
                    }
                    .padding(.top, Space.xs)
                } label: {
                    Text("打刻の丸め")
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.ink)
                .frame(minHeight: 44)
            }
        }
    }

    private func roundingPicker(_ title: String, selection: Binding<Int>, identifier: String) -> some View {
        PickerRow(label: title, selection: selection, identifier: identifier) {
            Text("そのまま").tag(0)
            Text("切り上げ").tag(1)
            Text("切り捨て").tag(2)
            Text("近いほう").tag(3)
        }
    }

    private var memo: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "メモ")
            Card {
                LabeledField(label: "メモ（任意）", text: $notes, prompt: "持ち物、制服、連絡先の担当者など", identifier: "field.メモ", multiline: true)
                    .focused($typing)
            }
        }
    }

    // MARK: Helpers

    static let weekdayNames = ["", "日", "月", "火", "水", "木", "金", "土"]

    private var previewWage: Int {
        payIsDaily ? 1_000 : max(0, Int(wageText.filter(\.isNumber)) ?? 0)
    }

    private var roundingUnits: [Int] {
        var units = [1, 5, 10, 15, 30, 60]
        if !units.contains(roundingUnit) {
            units.append(roundingUnit)
            units.sort()
        }
        return units
    }

    private var nextPaydayLine: String {
        let calendar = ShiftOverlap.tokyo
        let today = LocalDay.from(.now, calendar: calendar)
        let plan = PayScheduleMath.plan(
            workday: today,
            closingDay: closingDay,
            paydayDay: paydayDay,
            monthOffset: paydayOffset,
            preferEarlier: true,
            calendar: calendar
        )
        var line = "今日の勤務分の給料日は \(plan.payday.month)月\(plan.payday.day)日 です。"
        if plan.direction == .earlier {
            line += "土日・年末年始は前の平日にしています。"
        } else if plan.direction == .later {
            line += "土日・年末年始は次の平日にしています。"
        }
        return line
    }

    private func yen(_ text: String) -> Int {
        min(100_000, max(0, Int(text.filter(\.isNumber)) ?? 0))
    }

    private func fillFromHere() async {
        locating = true
        locateNote = ""
        defer { locating = false }
        switch await CurrentLocation.shared.addressHere() {
        case .address(let line, let lat, let lon):
            place = line
            latitude = lat
            longitude = lon
            hasCoordinate = true
            pinFromHere = true
            locateNote = "入れました。違っていたら、住所の欄を直してください。"
        case .notAllowed:
            locateNote = "位置情報が許可されていません。設定の「位置情報」から許可できます。"
        case .notFound:
            locateNote = "現在地の住所がわかりませんでした。住所の欄に入れてください。"
        }
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else {
            if let settings = settingsRows.first {
                wageText = String(settings.defaultHourlyWage)
                transportText = String(settings.defaultTransportAllowance)
            }
            let used = Set(workplaces.map(\.colorHex))
            colorHex = Theme.palette.first { !used.contains($0) } ?? Theme.palette[0]
            return
        }
        name = existing.name
        colorHex = existing.colorHex
        genre = existing.genre
        place = existing.place
        phone = existing.phone
        openingHours = existing.openingHours
        officialURL = existing.officialURL
        latitude = existing.latitude
        longitude = existing.longitude
        hasCoordinate = existing.hasMapCoordinate
        payIsDaily = existing.payIsDaily
        wageText = String(existing.hourlyWage)
        dailyText = String(existing.dailyWage)
        transportText = String(existing.transportAllowance)
        payCycle = existing.payCycle
        closingDay = existing.closingDay
        paydayOffset = existing.paydayMonthOffset
        paydayDay = existing.paydayDay
        payWeekday = existing.payWeekday

        nightStart = existing.nightStartMinutes
        nightEnd = existing.nightEndMinutes
        nightText = existing.nightWage > 0 ? String(existing.nightWage) : ""
        nightRate = existing.nightRatePercent > 0 ? existing.nightRatePercent : 25
        nightMode = !existing.nightPayEnabled ? .off : (existing.nightWage > 0 ? .amount : .percent)

        holidayRates = existing.holidayRatePercents
        holidayDays = existing.holidayWeekdays.isEmpty ? [1, 7] : existing.holidayWeekdays
        holidayText = existing.holidayWage > 0 ? String(existing.holidayWage) : ""
        let storedHolidayRate = holidayDays.sorted().compactMap { day in
            holidayRates.indices.contains(day - 1) ? holidayRates[day - 1] : nil
        }.first { $0 > 0 }
        holidayRate = storedHolidayRate ?? 25
        holidayMode = !existing.holidayPayEnabled ? .off : (existing.holidayWage > 0 ? .amount : .percent)
        holidayNightOn = existing.holidayNightEnabled
        holidayNightText = existing.holidayNightWage > 0 ? String(existing.holidayNightWage) : ""
        holidayNightStart = existing.holidayNightStartMinutes
        holidayNightEnd = existing.holidayNightEndMinutes

        overtimeHours = max(1, existing.overtimeAfterMinutes / 60)
        overtimePerHour = existing.overtimePerHour
        overtimeText = existing.overtimeExtra > 0 ? String(existing.overtimeExtra) : ""
        overtimeRate = existing.overtimeRatePercent > 0 ? existing.overtimeRatePercent : 25
        overtimeMode = !existing.overtimeEnabled ? .off : (existing.overtimeExtra > 0 ? .amount : .percent)

        customBreaks = existing.customBreaks
        breakRules = existing.breakRules
        roundingUnit = existing.roundingUnitMinutes
        roundingStart = existing.roundingStartRaw
        roundingEnd = existing.roundingEndRaw
        earlyFromPlan = existing.earlyClockCountsFromPlan
        wageHistory = existing.wageHistory
        payRuleDates = existing.payRuleDates
        wageBands = existing.wageBands
        notes = existing.notes
    }

    /// The first problem, in the order the form shows the fields. Nil when it can be saved.
    private var problem: String? {
        if let message = WorkplaceEditorCheck.message(
            name: name,
            hourlyWage: payIsDaily ? nil : WorkplaceEditorCheck.signedYen(wageText),
            wageDates: [],
            payRuleDates: [],
            calendar: .current
        ) {
            return message
        }
        if payIsDaily, yen(dailyText) == 0 { return "日給を入れてください。" }
        if !payIsDaily, yen(wageText) == 0 { return "時給を入れてください。" }
        if payCycle == .week, !(1...7).contains(payWeekday) { return "週払いの曜日を選んでください。" }
        if !payIsDaily, nightMode == .amount, yen(nightText) == 0 { return "深夜の時給を入れてください。" }
        if holidayMode != .off, holidayDays.isEmpty { return "休日にする曜日を1つ以上選んでください。" }
        if holidayMode == .amount, yen(holidayText) == 0 { return "休日の時給を入れてください。" }
        if holidayMode != .off, holidayNightOn, nightMode != .off, !payIsDaily, yen(holidayNightText) == 0 {
            return "休日の深夜の時給を入れてください。"
        }
        if overtimeMode == .amount, yen(overtimeText) == 0 { return "残業手当の金額を入れてください。" }
        return nil
    }

    private func save() {
        if let problem {
            error = problem
            return
        }
        error = ""
        let workplace: Workplace
        if let existing {
            workplace = existing
        } else {
            workplace = Workplace(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                colorHex: colorHex,
                hourlyWage: yen(wageText),
                transportAllowance: yen(transportText)
            )
            context.insert(workplace)
        }
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        // A pin read for the old address would open the wrong place in Maps.
        let addressChanged = trimmedPlace != (existing?.place ?? "")
        workplace.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.colorHex = colorHex
        workplace.genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.place = trimmedPlace
        workplace.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.openingHours = openingHours.trimmingCharacters(in: .whitespacesAndNewlines)
        workplace.officialURL = officialURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if pinFromHere || !addressChanged {
            workplace.latitude = latitude
            workplace.longitude = longitude
            workplace.hasMapCoordinate = hasCoordinate
        } else {
            workplace.latitude = 0
            workplace.longitude = 0
            workplace.hasMapCoordinate = false
        }

        workplace.payIsDaily = payIsDaily
        workplace.hourlyWage = yen(wageText)
        workplace.dailyWage = yen(dailyText)
        workplace.transportAllowance = yen(transportText)
        workplace.payCycle = payCycle
        workplace.closingDay = closingDay
        workplace.paydayMonthOffset = paydayOffset
        workplace.paydayDay = paydayDay
        workplace.payWeekday = payWeekday

        let nightOn = nightMode != .off && !payIsDaily
        workplace.nightPayEnabled = nightOn
        workplace.nightWage = nightMode == .amount ? yen(nightText) : 0
        workplace.nightRatePercent = nightMode == .percent ? nightRate : (nightMode == .off ? workplace.nightRatePercent : 0)
        workplace.nightStartMinutes = nightStart
        workplace.nightEndMinutes = nightEnd

        workplace.holidayPayEnabled = holidayMode != .off
        workplace.setHolidayWeekdays(holidayDays)
        workplace.holidayWage = holidayMode == .amount ? yen(holidayText) : 0
        if holidayMode == .percent {
            var rates = holidayRates
            for day in holidayDays where rates.indices.contains(day - 1) {
                rates[day - 1] = holidayRate
            }
            workplace.setHolidayRatePercents(rates)
        } else {
            workplace.setHolidayRatePercents(holidayRates)
        }
        let holidayNight = holidayMode != .off && nightOn && holidayNightOn
        workplace.holidayNightEnabled = holidayNight
        workplace.holidayNightWage = holidayNight ? yen(holidayNightText) : 0
        workplace.holidayNightStartMinutes = holidayNightStart
        workplace.holidayNightEndMinutes = holidayNightEnd

        workplace.overtimeEnabled = overtimeMode != .off
        workplace.overtimeAfterMinutes = overtimeHours * 60
        workplace.overtimePerHour = overtimePerHour
        workplace.overtimeExtra = overtimeMode == .amount ? yen(overtimeText) : 0
        workplace.overtimeRatePercent = overtimeMode == .percent ? overtimeRate : (overtimeMode == .off ? workplace.overtimeRatePercent : 0)

        workplace.customBreaks = customBreaks
        workplace.breakRules = breakRules
        workplace.roundingUnitMinutes = roundingUnit
        workplace.roundingStartRaw = roundingStart
        workplace.roundingEndRaw = roundingEnd
        workplace.earlyClockCountsFromPlan = earlyFromPlan
        workplace.wageHistory = wageHistory
        workplace.payRuleDates = payRuleDates
        workplace.wageBands = wageBands
        workplace.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try context.save()
        } catch {
            self.error = "保存できませんでした。少し待ってから、もう一度試してください。"
            return
        }
        dismiss()
    }

    private func deleteWorkplace() {
        if let existing { context.delete(existing) }
        do {
            try context.save()
        } catch {
            self.error = "削除できませんでした。少し待ってから、もう一度試してください。"
            return
        }
        dismiss()
    }
}
