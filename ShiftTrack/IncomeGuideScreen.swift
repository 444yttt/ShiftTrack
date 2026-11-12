import SwiftUI

/// 年収の目安. Tax and social-insurance lines compared with this year's estimate.
struct IncomeGuideScreen: View {
    var year: Int
    var figures: IncomeGuide.Figures
    @Binding var birthYear: Int
    @Binding var birthMonth: Int
    @Binding var birthDay: Int
    @Environment(\.dismiss) private var dismiss

    private var birth: LocalDay? {
        guard birthYear > 1900, (1...12).contains(birthMonth), (1...31).contains(birthDay) else { return nil }
        return LocalDay(year: birthYear, month: birthMonth, day: birthDay)
    }

    private var age: Int? {
        guard let birth else { return nil }
        return IncomeGuide.age(on: IncomeGuide.december31(year), born: birth)
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: "\(IncomeGuide.asOf.year)年\(IncomeGuide.asOf.month)月\(IncomeGuide.asOf.day)日時点の目安です。税や社会保険の判定ではありません。")
                    .padding(.top, Space.xs)
                Card(spacing: Space.xs) {
                    Text("\(year)年の見込み")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink2)
                    ValueRow(title: "給与収入（交通費を除く）", value: Formatters.yen(figures.salaryYen), emphasized: true)
                        .accessibilityIdentifier("income.guide.salary")
                    ValueRow(title: "今後1年の収入（交通費を含む）", value: Formatters.yen(figures.socialYen), emphasized: true)
                        .accessibilityIdentifier("income.guide.social")
                    InfoNote(text: "所得税は交通費を除いた給与収入、社会保険は交通費を含めた今後1年の見込みで比べます。")
                }
                birthCard
                SectionHeader(title: "線ごとの見込み")
                ForEach(IncomeGuide.lines(year: year, ageOnDecember31: age)) { line in
                    lineCard(line)
                }
                InfoNote(text: IncomeGuide.sourceNote)
            }
            .background(Theme.paper)
            .navigationTitle("年収の目安")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
        }
    }

    private var birthCard: some View {
        Card(spacing: Space.s) {
            Text("12月31日時点の年齢")
                .font(AppFont.rowTitle)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if let age {
                ValueRow(title: "\(year)年12月31日の年齢", value: "\(age)歳", emphasized: true)
                DatePicker(selection: birthBinding, displayedComponents: .date) {
                    Text("生年月日")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                }
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .tint(Theme.signalInk)
                .frame(minHeight: 44)
                .accessibilityIdentifier("income.guide.birth")
                TextLinkButton(title: "生年月日を消す", identifier: "income.guide.birth.clear") {
                    birthYear = 0
                    birthMonth = 0
                    birthDay = 0
                }
            } else {
                InfoNote(text: "生年月日がないと、19〜22歳向けの線と一般の線のどちらで見るかを決められません。生年月日はこの端末にだけ残ります。")
                SecondaryButton(title: "生年月日を入れる", systemImage: "calendar", identifier: "income.guide.birth") {
                    birthYear = 2006
                    birthMonth = 1
                    birthDay = 1
                }
            }
        }
    }

    private var birthBinding: Binding<Date> {
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
                let year = birthYear > 1900 ? birthYear : 2006
                let month = (1...12).contains(birthMonth) ? birthMonth : 1
                let day = (1...31).contains(birthDay) ? birthDay : 1
                return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
            },
            set: { date in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
                birthYear = calendar.component(.year, from: date)
                birthMonth = calendar.component(.month, from: date)
                birthDay = calendar.component(.day, from: date)
            }
        )
    }

    private func lineCard(_ line: IncomeGuide.Line) -> some View {
        Card(spacing: Space.xs) {
            Text(line.title)
                .font(AppFont.rowTitle)
                .foregroundStyle(Theme.ink)
            if let yen = line.yen {
                let estimate = IncomeGuide.estimate(line.basis, figures: figures)
                let outlook = IncomeGuide.outlook(estimate: estimate, line: yen, bound: line.bound)
                ValueRow(title: "線", value: line.bound == .lessThan ? "\(Formatters.yen(yen))未満" : "\(Formatters.yen(yen))以下", emphasized: true)
                ProgressBar(value: yen > 0 ? Double(estimate) / Double(yen) : 0, label: "\(line.title)に対する見込み")
                Text(IncomeGuide.message(title: line.title, outlook: outlook))
                    .font(AppFont.body)
                    .foregroundStyle(outlook == .over ? Theme.danger : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("金額の線はありません")
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
            }
            InfoNote(text: line.note)
        }
    }
}
