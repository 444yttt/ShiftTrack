import SwiftData
import SwiftUI

private enum IncomeScope: String, CaseIterable, Identifiable {
    case month = "月間"
    case year = "年間"
    var id: String { rawValue }
}

struct IncomeScreen: View {
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @State private var scope: IncomeScope = .month
    @State private var anchor = Date()
    @State private var editGoal = false
    @State private var askApply = false
    @State private var pendingGoal = 0
    @State private var delta: Int?

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
        let month = calendar.component(.month, from: anchor)
        let period = scope == .year
            ? IncomeEngine.yearInterval(year)
            : IncomeEngine.monthInterval(anchor)
        let totals = period.map { IncomeEngine.totals(shifts: snapshots, from: $0.0, until: $0.1, now: .now) } ?? IncomeEngine.Totals()
        let goal = scope == .year ? settings.yearGoal(year) : settings.monthGoal(year: year, month: month)
        let minimum = scope == .year ? 10_000 : 5_000
        let upper = scope == .year ? 10_000_000 : 1_000_000

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

            goalHeader(title: scope == .year ? "年間目標" : "月間目標", goal: goal) {
                pendingGoal = goal
                editGoal = true
            }
            .padding(.top, 14)

            salaryCard(totals, goal: goal)
                .padding(.top, 12)

            Text("勤務先ごと")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            if totals.rows.isEmpty {
                Text("この期間に入る給料のシフトはまだありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    ForEach(totals.rows) { row in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color(hexString: row.colorHex))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                Text(Formatters.hours(row.minutes))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Formatters.yen(row.yen))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.lime)
                        }
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            Text("表示しているのは、その月・年に入る給料です。給料日が翌月の勤務先は、働いた月ではなく入金月に載ります。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .onAppear { refreshDelta(settings, worked: totals.workedYen, year: year, month: month) }
        .onChange(of: scope) { _, _ in refreshDelta(settings, worked: totals.workedYen, year: year, month: month) }
        .onChange(of: anchor) { _, _ in refreshDelta(settings, worked: totals.workedYen, year: year, month: month) }
        .sheet(isPresented: $editGoal) {
            GoalEditorSheet(goal: $pendingGoal, minimum: minimum, upper: upper, title: scope == .year ? "年間目標" : "月間目標") {
                editGoal = false
                askApply = true
            }
        }
        .confirmationDialog(
            scope == .year ? "翌年以降も同じ金額を反映しますか" : "翌月以降も同じ金額を反映しますか",
            isPresented: $askApply,
            titleVisibility: .visible
        ) {
            Button("反映する") {
                store(settings, value: pendingGoal, year: year, month: month, applyForward: true)
            }
            Button("反映しない") {
                store(settings, value: pendingGoal, year: year, month: month, applyForward: false)
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func goalHeader(title: String, goal: Int, edit: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button(action: edit) {
                HStack(spacing: 6) {
                    Text(Formatters.yen(goal))
                        .font(.system(size: 16, weight: .black))
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Theme.lime)
            }
            .buttonStyle(.plain)
        }
    }

    private func salaryCard(_ totals: IncomeEngine.Totals, goal: Int) -> some View {
        let ratio = goal > 0 ? Double(totals.workedYen) / Double(goal) : 0
        let remaining = goal - totals.workedYen
        return VStack(alignment: .leading, spacing: 14) {
            SalaryDonut(rows: totals.rows, center: Formatters.yen(totals.workedYen), delta: delta)
            HStack {
                Text(goal > 0 ? Formatters.percent(ratio, decimals: true) : "—")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                Spacer()
                Text(remainingLabel(remaining))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
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
            HStack(spacing: 8) {
                mini("総勤務時間", value: Formatters.hours(totals.forecastMinutes))
                mini("給料見込", value: Formatters.yen(totals.forecastYen))
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func mini(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func remainingLabel(_ remaining: Int) -> String {
        if remaining > 0 { return "目標まで \(Formatters.yen(remaining))" }
        if remaining == 0 { return "目標達成" }
        return "目標を \(Formatters.yen(-remaining)) 超過"
    }

    private func refreshDelta(_ settings: AppSettings, worked: Int, year: Int, month: Int) {
        let key = scope == .year ? "y\(year)" : String(format: "m%04d-%02d", year, month)
        if settings.salarySeenKey == key {
            let difference = worked - settings.salarySeenWorked
            delta = difference == 0 ? nil : difference
        } else {
            delta = nil
        }
        settings.salarySeenKey = key
        settings.salarySeenWorked = worked
    }

    private func store(_ settings: AppSettings, value: Int, year: Int, month: Int, applyForward: Bool) {
        if scope == .year {
            settings.setYearGoal(value, year: year, applyForward: applyForward)
        } else {
            settings.setMonthGoal(value, year: year, month: month, applyForward: applyForward)
        }
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

private struct SalaryDonut: View {
    var rows: [IncomeEngine.Row]
    var center: String
    var delta: Int?

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Canvas { context, size in
                    let total = rows.reduce(0) { $0 + $1.yen }
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2 - 10
                    if total <= 0 {
                        var path = Path()
                        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                        context.stroke(path, with: .color(Theme.track), lineWidth: 14)
                        return
                    }
                    var start = -Double.pi / 2
                    for row in rows where row.yen > 0 {
                        let sweep = Double(row.yen) / Double(total) * 2 * .pi
                        var path = Path()
                        path.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .radians(start),
                            endAngle: .radians(start + sweep),
                            clockwise: false
                        )
                        context.stroke(path, with: .color(Color(hexString: row.colorHex)), style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                        start += sweep
                    }
                }
                .frame(width: 132, height: 132)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("今日までの給料")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Text(center)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Theme.lime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let delta, delta != 0 {
                    Text(delta > 0 ? "+\(Formatters.yen(delta))" : Formatters.yen(delta))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(delta > 0 ? Theme.lime : Theme.behind)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct GoalEditorSheet: View {
    @Binding var goal: Int
    var minimum: Int
    var upper: Int
    var title: String
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Theme.lime)
                    TextField("0", text: $text)
                        .keyboardType(.numberPad)
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(.white)
                }
                Text("\(Formatters.yen(minimum))〜\(Formatters.yen(upper - 1))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.behind)
                }
                Spacer()
                LimeCapsuleButton(title: "完了する", fillWidth: true) { commit() }
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.lime)
                }
            }
            .darkSheet()
            .onAppear { text = String(goal) }
        }
        .presentationDetents([.medium])
    }

    private func commit() {
        let value = Int(text.filter(\.isNumber)) ?? 0
        guard value >= minimum, value < upper else {
            error = "\(Formatters.yen(minimum))以上、\(Formatters.yen(upper))未満にしてください"
            return
        }
        goal = value
        onDone()
        dismiss()
    }
}
