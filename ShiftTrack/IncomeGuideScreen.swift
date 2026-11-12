import SwiftUI

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
        ScreenScroll {
            HStack {
                Text("年収の目安")
                    .designFont(16, weight: .black)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("閉じる") { dismiss() }
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.accentText)
            }
            .padding(.top, 8)
            Text("\(IncomeGuide.asOf.year)年\(IncomeGuide.asOf.month)月\(IncomeGuide.asOf.day)日時点の目安です。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            Text("給与収入 \(Formatters.yen(figures.salaryYen))")
                .designFont(28, weight: .semibold, design: .rounded, digits: true)
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("income.guide.salary")
            Text("社会保険の見込 \(Formatters.yen(figures.socialYen))")
                .designFont(22, weight: .semibold, design: .rounded, digits: true)
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("income.guide.social")
            Text("所得税は通勤手当を除いた給与収入、社会保険は通勤手当を含めた今後の見込です。同じ合計は使いません。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            birthRow
            ForEach(IncomeGuide.lines(year: year, ageOnDecember31: age)) { line in
                lineCard(line)
            }
            Text(IncomeGuide.sourceNote)
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
        .background(Theme.background)
    }

    private var birthRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("12月31日時点の年齢")
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.ink)
            if let age {
                Text("\(year)年12月31日で\(age)歳")
                    .designFont(16, weight: .bold)
                DatePicker(
                    "生年月日",
                    selection: birthBinding,
                    displayedComponents: .date
                )
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .accessibilityIdentifier("income.guide.birth")
                Button("生年月日を消す") {
                    birthYear = 0
                    birthMonth = 0
                    birthDay = 0
                }
                .designFont(13, weight: .bold)
                .foregroundStyle(Theme.accentText)
            } else {
                Text("生年月日がないと、150万円と130万円のどちらを見るか決まりません。")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
                Button("生年月日を入れる") {
                    birthYear = 2006
                    birthMonth = 1
                    birthDay = 1
                }
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.accentText)
                .accessibilityIdentifier("income.guide.birth")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        VStack(alignment: .leading, spacing: 8) {
            Text(line.title)
                .designFont(16, weight: .bold)
                .foregroundStyle(Theme.ink)
            if let yen = line.yen {
                let estimate = IncomeGuide.estimate(line.basis, figures: figures)
                let outlook = IncomeGuide.outlook(estimate: estimate, line: yen, bound: line.bound)
                Text(line.bound == .lessThan ? "\(Formatters.yen(yen))未満" : "\(Formatters.yen(yen))以下")
                    .designFont(20, weight: .semibold, design: .rounded, digits: true)
                Text(IncomeGuide.message(title: line.title, outlook: outlook))
                    .designFont(13)
                    .foregroundStyle(Theme.ink)
            } else {
                Text("金額の線はありません")
                    .designFont(16, weight: .bold)
            }
            Text(line.note)
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
