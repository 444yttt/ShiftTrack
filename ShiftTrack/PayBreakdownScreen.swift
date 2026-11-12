import SwiftData
import SwiftUI

/// 月の内訳: one month of work (by work date) split into base, premium,
/// transport and 天引・手当, with the paydays the money arrives on. Amounts
/// come from the same engine as the rest of the app.
struct PayBreakdownScreen: View {
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @Query private var settingsRows: [AppSettings]
    @Environment(\.dismiss) private var dismiss
    @State private var anchor = Date()

    private var includeTransport: Bool { settingsRows.first?.includeTransport ?? true }

    private struct Line: Identifiable {
        var id: UUID
        var workplaceID: UUID
        var workplaceName: String
        var minutes: Int
        var base: Int
        var premium: Int
        var transport: Int
        var adjustment: Int
        var payday: Date
        var total: Int { base + premium + transport + adjustment }
    }

    private var lines: [Line] {
        let calendar = Calendar.current
        return shifts.compactMap { shift in
            guard let place = shift.workplace,
                  calendar.isDate(shift.date, equalTo: anchor, toGranularity: .month) else { return nil }
            let wage = PayMath.wageParts(shift)
            return Line(
                id: shift.uuid,
                workplaceID: place.uuid,
                workplaceName: place.name,
                minutes: shift.workedMinutes,
                base: wage.base,
                premium: wage.premium,
                transport: includeTransport ? max(0, place.transportAllowance) : 0,
                adjustment: shift.adjustmentYen,
                payday: PaySchedule.payday(for: shift.date, workplace: place)
            )
        }
    }

    var body: some View {
        let rows = lines
        let base = rows.reduce(0) { $0 + $1.base }
        let premium = rows.reduce(0) { $0 + $1.premium }
        let transport = rows.reduce(0) { $0 + $1.transport }
        let adjustment = rows.reduce(0) { $0 + $1.adjustment }
        let total = max(0, base + premium + transport + adjustment)
        let month = Calendar.current.component(.month, from: anchor)
        return NavigationStack {
            ScreenScroll(spacing: Space.m) {
                HStack(spacing: Space.xs) {
                    monthButton("chevron.left", label: "前の月", delta: -1)
                    Spacer(minLength: 0)
                    DotoText(Formatters.dotoMonth(anchor), size: 28, spoken: Formatters.monthTitle(anchor))
                    Spacer(minLength: 0)
                    monthButton("chevron.right", label: "次の月", delta: 1)
                }
                .padding(.top, Space.xs)
                Card(spacing: Space.xs) {
                    Text("\(month)月に働いた分の見込み")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink2)
                    DotoText("¥" + Formatters.yenDigits(total), size: 36, spoken: "\(total)円")
                    RowDivider()
                    ValueRow(title: "基本の給料", value: Formatters.yen(base))
                    ValueRow(title: "割増（深夜・休日・残業）", value: Formatters.yen(premium))
                    ValueRow(title: includeTransport ? "交通費" : "交通費（含めない設定）", value: Formatters.yen(transport))
                    ValueRow(title: "天引・手当", value: (adjustment < 0 ? "−" : "") + Formatters.yen(abs(adjustment)))
                    InfoNote(text: "働いた日で数えています。給料タブの金額は給料日の月で数えるので、月がずれることがあります。税金・社会保険は計算していません。")
                }
                SectionHeader(title: "勤務先ごと")
                if rows.isEmpty {
                    EmptyState(systemImage: "calendar", message: "この月に働くシフトはありません")
                } else {
                    Card(spacing: Space.xs) {
                        ForEach(workplaceTotals(rows), id: \.id) { place in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .font(AppFont.rowTitle)
                                        .foregroundStyle(Theme.ink)
                                    Text(Formatters.hours(place.minutes))
                                        .font(AppFont.helper)
                                        .foregroundStyle(Theme.ink2)
                                }
                                Spacer(minLength: Space.xs)
                                Text(Formatters.yen(place.yen))
                                    .font(AppFont.value.weight(.bold))
                                    .foregroundStyle(Theme.ink)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    SectionHeader(title: "入金の予定")
                    Card(spacing: Space.xs) {
                        ForEach(paydays(rows), id: \.day) { group in
                            HStack(alignment: .firstTextBaseline) {
                                Text(Formatters.longDay(group.day))
                                    .font(AppFont.rowTitle)
                                    .foregroundStyle(Theme.ink)
                                Spacer(minLength: Space.xs)
                                Text(Formatters.yen(group.yen))
                                    .font(AppFont.value.weight(.bold))
                                    .foregroundStyle(Theme.ink)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle("月の内訳")
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

    private func workplaceTotals(_ rows: [Line]) -> [(id: UUID, name: String, minutes: Int, yen: Int)] {
        var order: [UUID] = []
        var names: [UUID: String] = [:]
        var minutes: [UUID: Int] = [:]
        var yen: [UUID: Int] = [:]
        for row in rows {
            if names[row.workplaceID] == nil { order.append(row.workplaceID) }
            names[row.workplaceID] = row.workplaceName
            minutes[row.workplaceID, default: 0] += row.minutes
            yen[row.workplaceID, default: 0] += row.total
        }
        return order.map { ($0, names[$0] ?? "", minutes[$0] ?? 0, yen[$0] ?? 0) }
    }

    private func paydays(_ rows: [Line]) -> [(day: Date, yen: Int)] {
        let calendar = Calendar.current
        var totals: [Date: Int] = [:]
        for row in rows {
            totals[calendar.startOfDay(for: row.payday), default: 0] += row.total
        }
        return totals.keys.sorted().map { ($0, totals[$0] ?? 0) }
    }

    private func monthButton(_ symbol: String, label: String, delta: Int) -> some View {
        Button {
            if let next = Calendar.current.date(byAdding: .month, value: delta, to: anchor) {
                anchor = next
            }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.sunken, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
