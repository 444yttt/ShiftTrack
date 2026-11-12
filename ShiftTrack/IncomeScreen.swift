import SwiftData
import SwiftUI

private enum IncomeScope: String, CaseIterable, Identifiable {
    case month = "月ごと"
    case year = "年ごと"
    var id: String { rawValue }
}

/// 給料. Money that arrives in the chosen month or year (counted by payday),
/// the goal, the split by workplace, and the pay screens.
struct IncomeScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query private var settingsRows: [AppSettings]
    @State private var scope: IncomeScope = .month
    @State private var anchor = Date()
    @State private var editGoal = false
    @State private var askApply = false
    @State private var pendingGoal = 0
    @State private var delta: Int?
    @State private var showWalls = false
    @State private var showGuideTable = false
    @State private var showBreakdown = false
    @State private var showHelp = false
    @State private var forecastWorkplace: UUID?
    @AppStorage("incomeGuide.birthYear") private var birthYear = 0
    @AppStorage("incomeGuide.birthMonth") private var birthMonth = 0
    @AppStorage("incomeGuide.birthDay") private var birthDay = 0

    var body: some View {
        if let settings = settingsRows.first {
            content(settings)
        } else {
            Theme.paper
        }
    }

    private var wallLine: String {
        let year = Calendar.current.component(.year, from: .now)
        guard let interval = IncomeEngine.yearInterval(year) else { return "今年の見込みと比べます。" }
        let includeTransport = settingsRows.first?.includeTransport ?? true
        let snapshots = ShiftMapping.snapshots(shifts, includeTransport: includeTransport)
        let forecast = IncomeEngine.totals(shifts: snapshots, from: interval.0, until: interval.1, now: .now).forecastYen
        if let next = IncomeWalls.all.first(where: { forecast < $0.yen }) {
            return "次の壁（\(next.title)）まで \(Formatters.yen(next.yen - forecast))"
        }
        return "表示している壁はすべて超えています"
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

        return ScreenScroll(spacing: Space.m) {
            ScreenHeader(title: "給料") {
                HelpButton { showHelp = true }
            }
            periodCard(year: year)
            totalCard(totals, year: year, month: month)
            goalCard(totals, goal: goal)
            workplaceSection(totals, calendar: calendar)
            if scope == .month {
                monthFacts(calendar: calendar, includeTransport: settings.includeTransport)
            }
            paydaySection
            moreSection
            InfoNote(text: "金額は、働いた月ではなく給料日のある月で数えます。税金や社会保険は引いていない目安です。")
        }
        .background(Theme.paper)
        .sheet(isPresented: $showHelp) {
            HelpSheet(title: "給料の見方", paragraphs: HelpCopy.income)
        }
        .sheet(isPresented: Binding(
            get: { forecastWorkplace != nil },
            set: { if !$0 { forecastWorkplace = nil } }
        )) {
            PayPeriodsView(workplaceID: forecastWorkplace)
        }
        .sheet(isPresented: $showWalls) {
            WallsScreen()
                .presentationBackground(Theme.paper)
        }
        .sheet(isPresented: $showBreakdown) {
            PayBreakdownScreen()
                .presentationBackground(Theme.paper)
        }
        .sheet(isPresented: $showGuideTable) {
            IncomeGuideScreen(
                year: year,
                figures: guideFigures(year: year),
                birthYear: $birthYear,
                birthMonth: $birthMonth,
                birthDay: $birthDay
            )
            .presentationBackground(Theme.paper)
        }
        .onAppear { refreshDelta(settings, worked: totals.workedYen, year: year, month: month) }
        .onChange(of: scope) { _, _ in refreshDelta(settings, worked: totals.workedYen, year: year, month: month) }
        .onChange(of: anchor) { _, _ in refreshDelta(settings, worked: totals.workedYen, year: year, month: month) }
        .sheet(isPresented: $editGoal) {
            GoalEditorSheet(goal: $pendingGoal, minimum: minimum, upper: upper, title: scope == .year ? "\(year)年の目標" : "\(month)月の目標") {
                editGoal = false
                askApply = true
            }
        }
        .confirmationDialog(
            scope == .year ? "翌年以降も同じ目標にしますか？" : "翌月以降も同じ目標にしますか？",
            isPresented: $askApply,
            titleVisibility: .visible
        ) {
            Button(scope == .year ? "翌年以降も同じにする" : "翌月以降も同じにする") {
                store(settings, value: pendingGoal, year: year, month: month, applyForward: true)
            }
            Button(scope == .year ? "この年だけにする" : "この月だけにする") {
                store(settings, value: pendingGoal, year: year, month: month, applyForward: false)
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // MARK: Cards

    private func periodCard(year: Int) -> some View {
        Card(spacing: Space.s) {
            SegmentedRow(label: "表示する期間", selection: $scope, identifier: "income.scope") {
                ForEach(IncomeScope.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            HStack(spacing: Space.xs) {
                chevron("chevron.left", label: scope == .year ? "前の年" : "前の月") { move(-1) }
                Spacer(minLength: 0)
                if scope == .year {
                    DotoText("\(year)", size: 30, spoken: "\(year)年")
                        .accessibilityIdentifier("income.period")
                } else {
                    DotoText(Formatters.dotoMonth(anchor), size: 30, spoken: Formatters.monthTitle(anchor))
                        .accessibilityIdentifier("income.period")
                }
                Spacer(minLength: 0)
                chevron("chevron.right", label: scope == .year ? "次の年" : "次の月") { move(1) }
            }
            if !isCurrentPeriod {
                TextLinkButton(title: scope == .year ? "今年に戻る" : "今月に戻る", identifier: "income.now") {
                    anchor = Date()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var isCurrentPeriod: Bool {
        Calendar.current.isDate(anchor, equalTo: .now, toGranularity: scope == .year ? .year : .month)
    }

    private func totalCard(_ totals: IncomeEngine.Totals, year: Int, month: Int) -> some View {
        Card(spacing: Space.s) {
            Text(scope == .year ? "\(year)年に入る給料（見込み）" : "\(month)月に入る給料（見込み）")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink2)
            DotoText("¥" + Formatters.yenDigits(totals.forecastYen), size: 40, spoken: "\(totals.forecastYen)円")
                .accessibilityIdentifier("income.total")
            HStack(spacing: Space.xs) {
                StatTile(title: "働いた分", value: Formatters.yen(totals.workedYen))
                StatTile(title: "これからの分", value: Formatters.yen(totals.scheduledYen))
            }
            ValueRow(title: "勤務時間の合計", value: Formatters.hours(totals.forecastMinutes))
        }
    }

    private func goalCard(_ totals: IncomeEngine.Totals, goal: Int) -> some View {
        let ratio = goal > 0 ? Double(totals.workedYen) / Double(goal) : 0
        let remaining = goal - totals.workedYen
        return Card(spacing: Space.s) {
            HStack(alignment: .center) {
                Text(scope == .year ? "年の目標" : "月の目標")
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.xs)
                SecondaryButton(title: "変える", systemImage: "pencil", fillWidth: false, identifier: "income.goal.edit") {
                    pendingGoal = goal
                    editGoal = true
                }
            }
            ValueRow(title: "目標", value: Formatters.yen(goal), emphasized: true)
            ProgressBar(value: ratio, label: "目標に対する働いた分")
            HStack(alignment: .firstTextBaseline) {
                Text(goal > 0 ? "働いた分で \(Formatters.percent(ratio, decimals: true))" : "目標が未設定です")
                Spacer(minLength: Space.xs)
                Text(remainingLabel(remaining))
            }
            .font(AppFont.helper)
            .foregroundStyle(Theme.ink2)
            if let delta, delta != 0 {
                Label(
                    "前に見たときから \(delta > 0 ? "+" : "−")\(Formatters.yen(abs(delta)))",
                    systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(AppFont.helper.weight(.semibold))
                .foregroundStyle(delta > 0 ? Theme.signalInk : Theme.danger)
            }
        }
    }

    private func workplaceSection(_ totals: IncomeEngine.Totals, calendar: Calendar) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "勤務先ごと")
            Card(spacing: Space.s) {
                if totals.rows.isEmpty {
                    Text(emptySalaryText(calendar: calendar))
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .center, spacing: Space.m) {
                        SalaryDonut(rows: totals.rows)
                            .frame(width: 96, height: 96)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(totals.rows) { row in
                                HStack(spacing: Space.xs) {
                                    Circle()
                                        .fill(Color(hexString: row.colorHex))
                                        .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                                        .frame(width: 10, height: 10)
                                        .accessibilityHidden(true)
                                    Text(row.name)
                                        .font(AppFont.label)
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: Space.xxs)
                                    Text(Formatters.percent(row.share, decimals: false))
                                        .font(AppFont.helper.monospacedDigit())
                                        .foregroundStyle(Theme.ink2)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    RowDivider()
                    ForEach(totals.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(AppFont.rowTitle)
                                    .foregroundStyle(Theme.ink)
                                Text(Formatters.hours(row.minutes))
                                    .font(AppFont.helper)
                                    .foregroundStyle(Theme.ink2)
                            }
                            Spacer(minLength: Space.xs)
                            Text(Formatters.yen(row.yen))
                                .font(AppFont.value.weight(.bold))
                                .foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func monthFacts(calendar: Calendar, includeTransport: Bool) -> some View {
        let rows = shifts
            .filter { calendar.isDate($0.date, equalTo: anchor, toGranularity: .month) }
            .map { shift in
                MonthShiftFact(
                    startMinutes: shift.startMinutes,
                    endMinutes: shift.endMinutes,
                    workedMinutes: shift.workedMinutes,
                    yen: shift.estimatedYen(includeTransport: includeTransport),
                    workplaceName: shift.workplace?.name ?? ""
                )
            }
        return InfoNote(text: "この月に働く分：" + MonthFacts.headline(MonthFacts.summarize(rows)), systemImage: "calendar")
    }

    private var paydaySection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "給料日ごとの見込み", detail: "勤務先を選ぶと、締めの期間ごとの金額と支給日が見られます。")
            if workplaces.isEmpty {
                EmptyState(systemImage: "building.2", message: "勤務先を登録すると、ここに出ます。")
            } else {
                Card(spacing: 0) {
                    ForEach(workplaces) { workplace in
                        Button {
                            forecastWorkplace = workplace.uuid
                        } label: {
                            NavRow(title: workplace.name, subtitle: PayWindows.phrase(workplace))
                        }
                        .buttonStyle(RowButtonStyle())
                        .accessibilityIdentifier("income.periods.\(workplace.name)")
                        RowDivider()
                    }
                }
            }
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: "くわしく見る")
            Card(spacing: 0) {
                Button {
                    showBreakdown = true
                } label: {
                    NavRow(systemImage: "list.bullet.rectangle", title: "月の内訳", subtitle: "基本給・割増・交通費・天引と、入金の予定")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("income.breakdown")
                RowDivider()
                Button {
                    showWalls = true
                } label: {
                    NavRow(systemImage: "flag", title: "年収の壁", subtitle: wallLine)
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("income.walls")
                RowDivider()
                Button {
                    showGuideTable = true
                } label: {
                    NavRow(systemImage: "checklist", title: "年収の目安", subtitle: "税と社会保険の線と、今年の見込みを比べます")
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityIdentifier("income.guide")
            }
        }
    }

    // MARK: Helpers

    private func remainingLabel(_ remaining: Int) -> String {
        if remaining > 0 { return "目標まで \(Formatters.yen(remaining))" }
        if remaining == 0 { return "目標に届きました" }
        return "目標を \(Formatters.yen(-remaining)) 超えています"
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
            return "この期間に働くシフトはあります。給料日が翌月以降の勤務先は、入金される月に出ます。"
        }
        return "この期間に入る給料はまだありません。"
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
        if reduceMotion {
            anchor = next
        } else {
            withAnimation(Motion.layout) { anchor = next }
        }
    }

    private func chevron(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.sunken, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Ring of each workplace's share. Decorative: the rows beside it carry the numbers.
private struct SalaryDonut: View {
    var rows: [IncomeEngine.Row]

    var body: some View {
        Canvas { context, size in
            let total = rows.reduce(0) { $0 + $1.yen }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineWidth: CGFloat = 16
            let radius = min(size.width, size.height) / 2 - lineWidth / 2
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(Theme.sunken), lineWidth: lineWidth)
            guard total > 0 else { return }
            var start = -Double.pi / 2
            for row in rows where row.yen > 0 {
                let sweep = Double(row.yen) / Double(total) * 2 * .pi
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: .radians(start), endAngle: .radians(start + sweep), clockwise: false)
                context.stroke(path, with: .color(Color(hexString: row.colorHex)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                var edge = Path()
                edge.addArc(center: center, radius: radius + lineWidth / 2, startAngle: .radians(start), endAngle: .radians(start + sweep), clockwise: false)
                context.stroke(edge, with: .color(Theme.ink.opacity(0.15)), lineWidth: 1)
                start += sweep
            }
        }
        .accessibilityHidden(true)
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
            VStack(alignment: .leading, spacing: Space.m) {
                Card {
                    YenField(
                        label: "目標の金額",
                        text: $text,
                        helper: "\(Formatters.yen(minimum))以上、\(Formatters.yen(upper))未満で入れます。",
                        error: error.isEmpty ? nil : error,
                        identifier: "goal.amount"
                    )
                }
                Spacer(minLength: 0)
                PrimaryButton(title: "決定", identifier: "goal.save") { commit() }
            }
            .padding(Space.m)
            .background(Theme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { Keyboard.dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onAppear {
                text = String(goal)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func commit() {
        let value = Int(text.filter(\.isNumber)) ?? 0
        guard value >= minimum, value < upper else {
            error = "\(Formatters.yen(minimum))以上、\(Formatters.yen(upper))未満にしてください。"
            return
        }
        goal = value
        onDone()
        dismiss()
    }
}
