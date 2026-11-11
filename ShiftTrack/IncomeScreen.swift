import SwiftData
import SwiftUI

private enum IncomeScope: String, CaseIterable, Identifiable {
    case month = "月間"
    case year = "年間"
    var id: String { rawValue }
}

struct IncomeScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]
    @State private var scope: IncomeScope = .year
    @State private var anchor = Date()
    @State private var editGoal = false
    @State private var askApply = false
    @State private var pendingGoal = 0
    @State private var delta: Int?
    @State private var showWalls = false
    @State private var showGuideTable = false
    @State private var showBreakdown = false
    @AppStorage("incomeGuide.birthYear") private var birthYear = 0
    @AppStorage("incomeGuide.birthMonth") private var birthMonth = 0
    @AppStorage("incomeGuide.birthDay") private var birthDay = 0
    @State private var showGuide = false
    @State private var forecastWorkplace: UUID?

    var body: some View {
        if let settings = settingsRows.first {
            content(settings)
        } else {
            Theme.background
        }
    }

    private var wallLine: String {
        let year = Calendar.current.component(.year, from: .now)
        guard let interval = IncomeEngine.yearInterval(year) else { return "今年の見込みを出しています。" }
        let includeTransport = settingsRows.first?.includeTransport ?? true
        let snapshots = ShiftMapping.snapshots(shifts, includeTransport: includeTransport)
        let forecast = IncomeEngine.totals(shifts: snapshots, from: interval.0, until: interval.1, now: .now).forecastYen
        if let next = IncomeWalls.all.first(where: { forecast < $0.yen }) {
            return "次の壁（\(next.title)）まで \(Formatters.yen(next.yen - forecast))。押すと内容を見られます。"
        }
        return "表示している壁はすべて超えています。押すと内容を見られます。"
    }

    private func guideFigures(year: Int) -> IncomeGuide.Figures {
        let calendar = ShiftOverlap.tokyo
        let salarySnapshots = ShiftMapping.snapshots(shifts, includeTransport: false)
        let salary: Int
        if let interval = IncomeEngine.yearInterval(year, calendar: calendar) {
            salary = IncomeEngine.totals(
                shifts: salarySnapshots,
                from: interval.0,
                until: interval.1,
                now: .now,
                calendar: calendar
            ).forecastYen
        } else {
            salary = 0
        }
        let socialSnapshots = ShiftMapping.snapshots(shifts, includeTransport: true)
        let today = LocalDay.from(.now, calendar: calendar)
        let next = LocalDay.from(calendar.date(byAdding: .year, value: 1, to: .now) ?? .now, calendar: calendar)
        let social = IncomeGuide.sum(
            socialSnapshots.map { (day: LocalDay.from($0.payDate, calendar: calendar), yen: $0.yen) },
            from: today,
            until: next
        )
        return IncomeGuide.Figures(salaryYen: salary, socialYen: social)
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
            HStack {
                InOutWordmark()
                Spacer()
                HelpButton { showGuide = true }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scope == .year ? "\(year)" : Formatters.monthTitle(anchor))
                    .font(dynamicTypeSize.isAccessibilitySize ? .system(.largeTitle, design: .rounded, weight: .bold) : .doto(54))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(scope == .year ? "\(year)年" : Formatters.monthTitle(anchor))
                if scope == .year {
                    Text("年")
                        .designFont(16, weight: .bold)
                }
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
                                .designFont(16, weight: .bold)
                                .foregroundStyle(scope == item ? Theme.ink : Theme.muted)
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

            yearForecastCard(totals)
                .padding(.top, 12)

            if scope == .month {
                let monthRows = shifts
                    .filter { calendar.isDate($0.date, equalTo: anchor, toGranularity: .month) }
                    .map { shift in
                        MonthShiftFact(
                            startMinutes: shift.startMinutes,
                            endMinutes: shift.endMinutes,
                            workedMinutes: shift.workedMinutes,
                            yen: shift.estimatedYen(includeTransport: settings.includeTransport),
                            workplaceName: shift.workplace?.name ?? ""
                        )
                    }
                let monthLine = MonthFacts.headline(MonthFacts.summarize(monthRows))
                Text(monthLine)
                    .designFont(13)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(monthLine)
            }

            ForEach(workplaces) { workplace in
                Button {
                    forecastWorkplace = workplace.uuid
                } label: {
                    HStack {
                        Text(PayWindows.phrase(workplace))
                            .designFont(16, weight: .medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            goalHeader(title: scope == .year ? "年間目標" : "月間目標", goal: goal) {
                pendingGoal = goal
                editGoal = true
            }
            .padding(.top, 14)

            salaryCard(totals, goal: goal)
                .padding(.top, 12)

            Text("勤務先ごと")
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            if totals.rows.isEmpty {
                Text(emptySalaryText(calendar: calendar))
                    .designFont(16)
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
                                    .designFont(16, weight: .medium)
                                    .foregroundStyle(Theme.ink)
                                Text(Formatters.hours(row.minutes))
                                    .designFont(16)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Formatters.yen(row.yen))
                                .designFont(16, weight: .bold)
                                .foregroundStyle(Theme.lime)
                        }
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            Button {
                showWalls = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("年収の壁")
                        .designFont(16, weight: .bold)
                        .foregroundStyle(Theme.ink)
                    Text(wallLine)
                        .designFont(16)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("income.walls")

            Button {
                showGuideTable = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("年収の目安")
                        .designFont(16, weight: .bold)
                        .foregroundStyle(Theme.ink)
                    Text("2026年11月11日時点の目安です。税と社会保険は別の合計です。")
                        .designFont(16)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("income.guide")

            Button {
                showBreakdown = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("月の内訳")
                        .designFont(16, weight: .bold)
                        .foregroundStyle(Theme.ink)
                    Text("支給見込みです。深夜・休日の割増は分けていません。")
                        .designFont(16)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("income.breakdown")

            Text("表示しているのは、その月・年に入る給料です。給料日が翌月の勤務先は、働いた月ではなく入金月に載ります。")
                .designFont(16)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .overlay {
            if showGuide, !GuideMemory.suppressed {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    GuideCard(
                        page: 1,
                        total: 1,
                        text: "今日と今月のお給料の見込みです。シフトの時間と時給から計算します。",
                        onBack: nil,
                        onNext: { showGuide = false },
                        onClose: { showGuide = false }
                    )
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { forecastWorkplace != nil },
            set: { if !$0 { forecastWorkplace = nil } }
        )) {
            PayPeriodsView(workplaceID: forecastWorkplace)
        }
        .sheet(isPresented: $showWalls) {
            WallsScreen()
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showBreakdown) {
            PayBreakdownScreen()
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $showGuideTable) {
            IncomeGuideScreen(
                year: year,
                figures: guideFigures(year: year),
                birthYear: $birthYear,
                birthMonth: $birthMonth,
                birthDay: $birthDay
            )
            .presentationBackground(Theme.background)
        }
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

    private func yearForecastCard(_ totals: IncomeEngine.Totals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("年収の見込み")
                .designFont(16, weight: .bold)
                .foregroundStyle(Color.white)
            forecastLine("働いた分", totals.workedYen)
            forecastLine(scope == .year ? "年末までのシフト分" : "この期間のシフト分", totals.scheduledYen)
            forecastLine("合計", totals.forecastYen)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func forecastLine(_ title: String, _ yen: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.white)
            Spacer()
            Text(Formatters.yen(yen))
                .font(.doto(22))
                .foregroundStyle(Theme.lime)
        }
    }

    private func goalHeader(title: String, goal: Int, edit: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .designFont(16, weight: .medium)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button(action: edit) {
                HStack(spacing: 6) {
                    Text(Formatters.yen(goal))
                        .designFont(16, weight: .black)
                    Image(systemName: "pencil")
                        .designFont(16, weight: .bold)
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
                    .designFont(16, weight: .black)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(remainingLabel(remaining))
                    .designFont(16, weight: .medium)
                    .foregroundStyle(Theme.ink)
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
                .designFont(16, weight: .medium)
                .foregroundStyle(Theme.muted)
            Text(value)
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.ink)
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

    private func emptySalaryText(calendar: Calendar) -> String {
        let workedHere = shifts.contains { shift in
            if scope == .year {
                return calendar.component(.year, from: shift.date) == calendar.component(.year, from: anchor)
            }
            return calendar.isDate(shift.date, equalTo: anchor, toGranularity: .month)
        }
        if workedHere {
            return "この期間に働いたシフトはあります。給料日が翌月以降の勤務先は、入金される月の給料に出ます。"
        }
        return "この期間に入る給料のシフトはまだありません"
    }

    private func store(_ settings: AppSettings, value: Int, year: Int, month: Int, applyForward: Bool) {
        if scope == .year {
            settings.setYearGoal(value, year: year, applyForward: applyForward)
        } else {
            settings.setMonthGoal(value, year: year, month: month, applyForward: applyForward)
        }
        try? context.save()
    }

    private func move(_ delta: Int) {
        let component: Calendar.Component = scope == .year ? .year : .month
        guard let next = Calendar.current.date(byAdding: component, value: delta, to: anchor) else { return }
        anchor = next
    }

    private func chevron(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(Theme.dayFilled)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name == "chevron.left" ? (scope == .year ? "前の年" : "前の月") : (scope == .year ? "次の年" : "次の月"))
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
                    .designFont(16, weight: .medium)
                    .foregroundStyle(Theme.muted)
                Text(center)
                    .designFont(16, weight: .black)
                    .foregroundStyle(Theme.lime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let delta, delta != 0 {
                    Text(delta > 0 ? "+\(Formatters.yen(delta))" : Formatters.yen(delta))
                        .designFont(16, weight: .bold)
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
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .designFont(16, weight: .medium)
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .designFont(16, weight: .black)
                        .foregroundStyle(Theme.lime)
                    TextField("0", text: $text)
                        .keyboardType(.numberPad)
                        .designFont(16, weight: .black)
                        .foregroundStyle(Theme.ink)
                        .focused($typing)
                }
                Text("\(Formatters.yen(minimum))〜\(Formatters.yen(upper - 1))")
                    .designFont(16)
                    .foregroundStyle(Theme.muted)
                if !error.isEmpty {
                    Text(error)
                        .designFont(16)
                        .foregroundStyle(Theme.behind)
                }
                Spacer()
                LimeCapsuleButton(title: "完了する", fillWidth: true, designSize: 16) { commit() }
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { typing = false }
                        .foregroundStyle(Theme.lime)
                }
            }
            .darkSheet()
            .onAppear {
                text = String(goal)
                typing = true
            }
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
