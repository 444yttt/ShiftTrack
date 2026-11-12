import SwiftData
import SwiftUI

/// Three registration steps from the reference screenshots.
/// Illustrations are drawn stand-ins. Photo import uses the existing on-device reader.
struct WorkplaceWizard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var step = 1
    @State private var name = ""
    @State private var place = ""
    @State private var phone = ""
    @State private var wage = ""
    @State private var effectiveFrom = Date()
    @State private var night = true
    @State private var overtime = true
    @State private var legalBreak = true
    @State private var patternName = ""
    @State private var startMinute = 17 * 60
    @State private var endMinute = 22 * 60
    @State private var weekdays: Set<Int> = []
    @AppStorage(ShiftNoticeRefresh.beforeKey) private var notify = false
    @State private var hours = ""
    @State private var officialURL = ""
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var hasCoordinate = false
    @State private var showImport = false

    var body: some View {
        VStack(spacing: 0) {
            progress
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if step == 1 { stepOne }
                    if step == 2 { stepTwo }
                    if step == 3 { stepThree }
                }
                .padding(16)
            }
            footer
        }
        .background(Theme.background)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { index in
                Text(String(format: "%02d", index))
                    .designFont(13, weight: .bold)
                    .foregroundStyle(step == index ? Theme.ink : Theme.muted)
                    .frame(width: 36, height: 36)
                    .background(step == index ? Theme.lime : (index < step ? Theme.ink : Theme.cardRaised))
                    .foregroundStyle(index < step ? Color.white : Theme.ink)
                    .clipShape(Circle())
                if index < 3 {
                    Capsule().fill(Theme.cardRaised).frame(height: 3)
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .designFont(14, weight: .bold)
                    .frame(width: 36, height: 36)
                    .background(Theme.cardRaised)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShopPlaceholder()
            Text("勤務先を登録")
                .designFont(16, weight: .black)
            Text("働いているお店の名前を入れます。住所と電話番号は、道順や遅刻の連絡に使います。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            Text("マップで探す")
                .designFont(13, weight: .bold)
            HStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.cardRaised).frame(height: 48)
                Button {
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 48, height: 48)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay { Circle().stroke(Theme.ink, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索")
            }
            field("店舗名", text: $name, identifier: "field.名前")
            field("住所", text: $place, identifier: "field.住所")
            field("連絡先", text: $phone, identifier: "field.連絡先")
            Button {
                showImport = true
            } label: {
                Text("写真から読み取る")
                    .designFont(16, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay { Capsule().stroke(Theme.ink, lineWidth: 1.5) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wizard.photo")
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

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 12) {
            PayPlaceholder()
            Text("お給料の決まり")
                .designFont(16, weight: .black)
            Text("お給料の見込みの計算に使います。あとから勤務先の画面で直せます。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            HStack {
                Text("時給")
                Spacer()
                TextField("0", text: $wage)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityIdentifier("field.時給")
                Text("円")
            }
            .padding(14)
            .background(Theme.cardRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            DatePicker("適用開始日", selection: $effectiveFrom, displayedComponents: .date)
            HStack {
                Text("締め日")
                Spacer()
                Text("末日")
                    .foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            toggleRow("深夜割増（22時〜5時）", isOn: $night)
            Text(night ? "25%" : "0%")
                .designFont(13, weight: .bold)
                .foregroundStyle(Theme.muted)
            toggleRow("残業割増（1日8時間超）", isOn: $overtime)
            Text(overtime ? "25%" : "0%")
                .designFont(13, weight: .bold)
                .foregroundStyle(Theme.muted)
            toggleRow("休憩", isOn: $legalBreak)
            Text("法律で決まった休憩で計算します（6時間を超えたら45分、8時間を超えたら60分）。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
    }

    private var stepThree: some View {
        VStack(alignment: .leading, spacing: 12) {
            CalendarPlaceholder()
            Text("いつものシフト")
                .designFont(16, weight: .black)
            Text("毎週決まって入るシフトがあれば入れます。なければそのまま「はじめる」で進めます。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            field("シフト名", text: $patternName, identifier: "field.シフト名")
            HStack {
                Text("開始")
                Spacer()
                MinutesTimePicker(title: "開始", minutes: $startMinute)
            }
            HStack {
                Text("終了")
                Spacer()
                MinutesTimePicker(title: "終了", minutes: $endMinute)
            }
            Text("毎週入る曜日")
                .designFont(13, weight: .bold)
            HStack {
                ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { index, label in
                    let weekday = index + 1
                    Button(label) {
                        if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                    }
                    .designFont(13, weight: .bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(weekdays.contains(weekday) ? Theme.ink : Color.white)
                    .foregroundStyle(weekdays.contains(weekday) ? Color.white : Theme.ink)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(Theme.ink, lineWidth: 1) }
                }
            }
            toggleRow("シフトの前に通知", isOn: $notify)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(step == 1 ? "スキップ" : "戻る") {
                if step == 1 { dismiss() } else { step -= 1 }
            }
            .designFont(16, weight: .bold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.cardRaised)
            .clipShape(Capsule())
            Button(step == 3 ? "はじめる" : (step == 1 ? "追加して次へ" : "次へ")) {
                if step < 3 { step += 1 } else { save() }
            }
            .designFont(16, weight: .bold)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ink)
            .clipShape(Capsule())
            .accessibilityIdentifier(step == 3 ? "wizard.finish" : "wizard.next")
        }
        .padding(16)
    }

    private func field(_ title: String, text: Binding<String>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .designFont(13, weight: .bold)
            TextField(title, text: text)
                .designFont(16)
                .padding(14)
                .background(Theme.cardRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier(identifier)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .designFont(16, weight: .bold)
        }
        .tint(Theme.accentText)
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismiss()
            return
        }
        let wageValue = Int(wage.filter(\.isNumber)) ?? 0
        let workplace = Workplace(
            name: trimmed,
            colorHex: "C6F24E",
            hourlyWage: wageValue,
            transportAllowance: 0
        )
        workplace.place = place
        workplace.notes = phone
        workplace.phone = phone
        workplace.openingHours = hours
        workplace.officialURL = officialURL
        workplace.latitude = latitude
        workplace.longitude = longitude
        workplace.hasMapCoordinate = hasCoordinate
        workplace.closingDay = 0
        workplace.customBreaks = !legalBreak
        workplace.wageHistory = [Workplace.WageHistoryEntry(at: effectiveFrom, hourlyWage: wageValue)]
        workplace.nightPayEnabled = night
        workplace.nightRatePercent = night ? 25 : 0
        workplace.overtimeEnabled = overtime
        workplace.overtimeRatePercent = overtime ? 25 : 0
        context.insert(workplace)
        let patternTitle = patternName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !patternTitle.isEmpty {
            let part = ShiftPart(
                name: patternTitle,
                workplaceUUID: workplace.uuid,
                startMinute: startMinute,
                endMinute: endMinute,
                breakMinutes: 0
            )
            context.insert(part)
            if !weekdays.isEmpty {
                let pattern = ShiftPattern(
                    name: patternTitle,
                    workplaceUUID: workplace.uuid,
                    startMinutes: startMinute,
                    endMinutes: endMinute,
                    breakMinutes: 0,
                    weekdays: weekdays
                )
                context.insert(pattern)
            }
        }
        try? context.save()
        if notify {
            Task { _ = await SettingsAccess.requestNotifications() }
        }
        dismiss()
    }
}
