import SwiftUI

struct IncomeGuideScreen: View {
    var estimate: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenScroll {
            HStack {
                Text("年収の目安")
                    .designFont(16, weight: .black)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button("閉じる") { dismiss() }
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.lime)
            }
            .padding(.top, 8)
            Text("\(IncomeGuide.asOf.year)年\(IncomeGuide.asOf.month)月\(IncomeGuide.asOf.day)日の相談メモです。一次資料では未確認です。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            Text("今年の見込 \(Formatters.yen(estimate))")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text("交通費を除く集計は、まだ分けていません。制度ごとの数え方は各行に書いてあります。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            ForEach(IncomeGuide.lines) { line in
                VStack(alignment: .leading, spacing: 8) {
                    Text(line.title)
                        .designFont(16, weight: .bold)
                        .foregroundStyle(Theme.ink)
                    if let yen = line.yen {
                        let outlook = IncomeGuide.outlook(estimate: estimate, line: yen)
                        Text(Formatters.yen(yen))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
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
            Text(IncomeGuide.sourceNote)
                .designFont(13)
                .foregroundStyle(Theme.muted)
        }
        .background(Theme.background)
    }
}
