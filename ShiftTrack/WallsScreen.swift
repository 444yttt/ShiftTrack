import SwiftData
import SwiftUI

struct WallsScreen: View {
    @Environment(\.dismiss) private var dismiss
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

        return ScreenScroll {
            HStack {
                Text("年収の壁")
                    .designFont(16, weight: .black)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("walls.title")
                Spacer()
                Button("閉じる") { dismiss() }
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.accentText)
                    .accessibilityIdentifier("walls.close")
                HelpButton { showHelp = true }
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("今年の給料見込")
                    .designFont(16, weight: .medium)
                    .foregroundStyle(Theme.muted)
                Text(Formatters.yen(forecast))
                    .designFont(16, weight: .black)
                    .foregroundStyle(Theme.accentText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let next {
                    Text("次の壁（\(next.title)）まで \(Formatters.yen(next.yen - forecast))")
                        .designFont(16, weight: .medium)
                        .foregroundStyle(Theme.ink)
                } else {
                    Text("表示している壁はすべて超えています")
                        .designFont(16, weight: .medium)
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 12)

            VStack(spacing: 12) {
                ForEach(IncomeWalls.all) { wall in
                    wallCard(wall, forecast: forecast)
                }
            }
            .padding(.top, 4)

            Text(IncomeWalls.disclaimer)
                .designFont(16)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .background(Theme.background)
        .accessibilityIdentifier("walls.screen")
        .sheet(isPresented: $showHelp) {
            HelpSheet(
                title: "年収の壁",
                paragraphs: IncomeWalls.all.map { "\($0.title) \($0.subtitle)。\($0.detail)" } + [IncomeWalls.disclaimer]
            )
        }
    }

    private func wallCard(_ wall: IncomeWall, forecast: Int) -> some View {
        let ratio = Double(forecast) / Double(wall.yen)
        let open = expanded == wall.yen
        return Button {
            expanded = open ? nil : wall.yen
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wall.title)
                            .designFont(16, weight: .bold)
                            .foregroundStyle(Theme.ink)
                        Text(wall.subtitle)
                            .designFont(16)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(Formatters.percent(ratio, decimals: false))
                        .designFont(16, weight: .bold)
                        .foregroundStyle(Theme.accentText)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(Theme.lime)
                            .frame(width: proxy.size.width * min(1, max(0, ratio)))
                    }
                }
                .frame(height: 8)
                if open {
                    Text(wall.detail)
                        .designFont(16)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct HelpSheet: View {
    var title: String
    var paragraphs: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .designFont(15)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.accentText)
                }
            }
            .darkSheet()
        }
    }
}
