import SwiftData
import SwiftUI

/// 年収の壁. This year's income estimate against the common thresholds.
struct WallsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @State private var expanded: Int?
    @State private var showHelp = false

    var body: some View {
        let includeTransport = settingsRows.first?.includeTransport ?? true
        let snapshots = ShiftMapping.snapshots(shifts, includeTransport: includeTransport)
        let year = Calendar.current.component(.year, from: .now)
        let totals: IncomeEngine.Totals = {
            guard let interval = IncomeEngine.yearInterval(year) else { return IncomeEngine.Totals() }
            return IncomeEngine.totals(shifts: snapshots, from: interval.0, until: interval.1, now: .now)
        }()
        let forecast = totals.forecastYen
        let next = IncomeWalls.all.first { forecast < $0.yen }

        return NavigationStack {
            ScreenScroll(spacing: Space.m) {
                Text("年収の壁")
                    .font(AppFont.screenTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("walls.title")
                    .padding(.top, Space.xs)
                Card(spacing: Space.xs) {
                    Text("\(year)年に入る給料の見込み")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink2)
                    DotoText("¥" + Formatters.yenDigits(forecast), size: 36, spoken: "\(forecast)円")
                    if let next {
                        Text("次の壁（\(next.title)・\(next.subtitle)）まで あと\(Formatters.yen(next.yen - forecast))")
                            .font(AppFont.rowTitle)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("表示している壁はすべて超えています")
                            .font(AppFont.rowTitle)
                            .foregroundStyle(Theme.ink)
                    }
                    Text(includeTransport ? "交通費を含めた見込みです。" : "交通費を含めない見込みです。")
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                }
                SectionHeader(title: "壁ごとの近さ", detail: "押すと説明が開きます。")
                ForEach(IncomeWalls.all) { wall in
                    wallCard(wall, forecast: forecast)
                }
                InfoNote(text: IncomeWalls.disclaimer)
            }
            .background(Theme.paper)
            .navigationTitle("年収の壁")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("walls.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .foregroundStyle(Theme.signalInk)
                    .accessibilityLabel("ヘルプ")
                }
            }
            .darkSheet()
            .accessibilityIdentifier("walls.screen")
            .sheet(isPresented: $showHelp) {
                HelpSheet(
                    title: "年収の壁について",
                    paragraphs: IncomeWalls.all.map { "\($0.title)（\($0.subtitle)）：\($0.detail)" } + [IncomeWalls.disclaimer]
                )
            }
        }
    }

    private func wallCard(_ wall: IncomeWall, forecast: Int) -> some View {
        let ratio = Double(forecast) / Double(wall.yen)
        let open = expanded == wall.yen
        return Button {
            if reduceMotion {
                expanded = open ? nil : wall.yen
            } else {
                withAnimation(Motion.layout) { expanded = open ? nil : wall.yen }
            }
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(wall.title)円")
                            .font(AppFont.rowTitle)
                            .foregroundStyle(Theme.ink)
                        Text(wall.subtitle)
                            .font(AppFont.helper)
                            .foregroundStyle(Theme.ink2)
                    }
                    Spacer(minLength: Space.xs)
                    Text(Formatters.percent(ratio, decimals: false))
                        .font(AppFont.value.weight(.bold))
                        .foregroundStyle(ratio >= 1 ? Theme.danger : Theme.ink)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink2)
                        .accessibilityHidden(true)
                }
                ProgressBar(value: ratio, label: "\(wall.title)円に対する見込み")
                if open {
                    Text(wall.detail)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.m)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "説明を表示中" : "")
    }
}

/// Plain help for a screen: one card per paragraph.
struct HelpSheet: View {
    var title: String
    var paragraphs: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.s) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text("\(index + 1)")
                            .font(AppFont.label.monospacedDigit())
                            .foregroundStyle(Theme.ink)
                            .frame(width: 26, height: 26)
                            .background(Theme.signal, in: Circle())
                            .accessibilityHidden(true)
                        Text(paragraph)
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.m)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                .padding(.top, Space.xxs)
            }
            .background(Theme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("help.close")
                }
            }
            .darkSheet()
        }
    }
}
