import SwiftData
import SwiftUI

private enum IncomeScope: String, CaseIterable, Identifiable {
    case month = "月"
    case year = "年"
    var id: String { rawValue }
}

struct IncomeScreen: View {
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @State private var scope: IncomeScope = .year
    @State private var anchor = Date()
    @State private var editGoal = false

    var body: some View {
        if let settings = settingsRows.first {
            content(settings)
        } else {
            Theme.background
        }
    }

    private func content(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings
        let snapshots = ShiftMapping.snapshots(shifts, includeTransport: settings.includeTransport)
        let calendar = Calendar.current
        let year = calendar.component(.year, from: anchor)
        let period = scope == .year
            ? IncomeEngine.yearInterval(year)
            : IncomeEngine.monthInterval(anchor)
        let totals = period.map { IncomeEngine.totals(shifts: snapshots, from: $0.0, until: $0.1, now: .now) } ?? IncomeEngine.Totals()
        let currentYear = calendar.component(.year, from: .now)
        let yearTotals: IncomeEngine.Totals = {
            guard let interval = IncomeEngine.yearInterval(currentYear) else { return IncomeEngine.Totals() }
            return IncomeEngine.totals(shifts: snapshots, from: interval.0, until: interval.1, now: .now)
        }()
        let pace = IncomeEngine.annualized(workedYen: yearTotals.workedYen, now: .now)
        let showPace = year == currentYear

        return ScreenScroll {
            HStack(alignment: .center, spacing: 8) {
                Text(scope == .year ? "\(year)年" : Formatters.monthTitle(anchor))
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    chevron("chevron.left") { move(-1) }
                    chevron("chevron.right") { move(1) }
                }
                HStack(spacing: 0) {
                    ForEach(IncomeScope.allCases) { item in
                        Button {
                            scope = item
                        } label: {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(scope == item ? Theme.ink : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(scope == item ? Theme.lime : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Theme.card)
                .clipShape(Capsule())
            }
            .padding(.top, 8)

            estimateCard(totals, scope: scope)
                .padding(.top, 14)

            if showPace {
                paceCard(pace: pace, goal: settings.annualIncomeGoal, worked: yearTotals.workedYen)
                    .padding(.top, 12)
                goalCard(forecast: yearTotals.forecastYen, goal: settings.annualIncomeGoal) {
                    editGoal = true
                }
                .padding(.top, 12)
            } else {
                goalCard(forecast: totals.forecastYen, goal: settings.annualIncomeGoal) {
                    editGoal = true
                }
                .padding(.top, 12)
            }

            Text("勤務先別")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            if totals.rows.isEmpty {
                Text("この期間のシフトはまだありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    ForEach(totals.rows) { row in
                        HStack {
                            Text(row.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Formatters.yen(row.yen))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.lime)
                                Text(Formatters.percent(row.share, decimals: false))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $editGoal) {
            GoalEditorSheet(goal: $settings.annualIncomeGoal)
        }
    }

    private func estimateCard(_ totals: IncomeEngine.Totals, scope: IncomeScope) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(scope == .year ? "年収の見込み" : "この期間の見込み")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(Formatters.yen(totals.forecastYen))
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(Theme.lime)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            HStack(spacing: 8) {
                mini(scope == .year ? "働いた分" : "働いた分", yen: totals.workedYen, minutes: totals.workedMinutes)
                mini(scope == .year ? "年末までのシフト" : "期間内の残り", yen: totals.scheduledYen, minutes: totals.scheduledMinutes)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func mini(_ title: String, yen: Int, minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(Formatters.yen(yen))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(Formatters.hours(minutes))
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func paceCard(pace: Int, goal: Int, worked: Int) -> some View {
        let ratio = goal > 0 ? Double(pace) / Double(goal) : 0
        let onTrack = goal > 0 && pace >= goal
        return VStack(alignment: .leading, spacing: 8) {
            Text("今日時点の見込み")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline) {
                Text(Formatters.yen(pace))
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                if goal > 0 {
                    Text(onTrack ? "ペース良好" : "遅れ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(onTrack ? Theme.lime : Theme.behind)
                }
            }
            Text(paceCaption(pace: pace, goal: goal, ratio: ratio, worked: worked))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func paceCaption(pace: Int, goal: Int, ratio: Double, worked: Int) -> String {
        if goal <= 0 {
            return "今日まで \(Formatters.yen(worked))。このまま続けると年末 \(Formatters.yen(pace))。目標額は設定から変えられます。"
        }
        return "このまま続けると年末 \(Formatters.yen(pace))（目標の\(Formatters.percent(ratio, decimals: false))）"
    }

    private func goalCard(forecast: Int, goal: Int, edit: @escaping () -> Void) -> some View {
        let ratio = goal > 0 ? Double(forecast) / Double(goal) : 0
        let remaining = goal - forecast
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("目標進捗")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button(action: edit) {
                    Text(goal > 0 ? Formatters.yen(goal) : "目標を設定")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(Theme.lime)
                        .frame(width: proxy.size.width * min(1, max(0, ratio)))
                }
            }
            .frame(height: 10)
            HStack {
                Text(goal > 0 ? Formatters.percent(ratio, decimals: true) : "—")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                Spacer()
                Text(remainingLabel(remaining))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func remainingLabel(_ remaining: Int) -> String {
        if remaining > 0 { return "残り \(Formatters.yen(remaining))" }
        if remaining == 0 { return "目標達成" }
        return "超過 \(Formatters.yen(-remaining))"
    }

    private func move(_ delta: Int) {
        let component: Calendar.Component = scope == .year ? .year : .month
        guard let next = Calendar.current.date(byAdding: component, value: delta, to: anchor) else { return }
        anchor = next
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.dayFilled)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct GoalEditorSheet: View {
    @Binding var goal: Int
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("年収目標")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Theme.lime)
                    TextField("1000000", text: $text)
                        .keyboardType(.numberPad)
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(Theme.lime)
                }
                Text("進捗とペースは、この金額と比べます。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("目標額")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        goal = min(100_000_000, max(0, Int(text.filter(\.isNumber)) ?? 0))
                        dismiss()
                    }
                    .foregroundStyle(Theme.lime)
                }
            }
            .darkSheet()
            .onAppear { text = goal == 0 ? "" : String(goal) }
        }
        .presentationDetents([.medium])
    }
}
