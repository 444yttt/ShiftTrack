import SwiftUI

/// “When a shift is longer than X, put in a Y-minute break” rules.
struct BreakRuleEditor: View {
    @Binding var rules: [InOutRecovered.BreakRule]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            InfoNote(text: "上にある決まりほど先に見ます。同じ時間の決まりが2つあるときは、上のほうを使います。")
            ForEach(Array(rules.indices), id: \.self) { index in
                if rules.indices.contains(index) {
                    ruleRow(index)
                }
            }
            SecondaryButton(title: "休憩の決まりを足す", systemImage: "plus", identifier: "breakrule.add") {
                guard rules.count < 8 else { return }
                rules.append(.init(overMinutes: 360, breakMinutes: 45))
            }
            .disabled(rules.count >= 8)
            if rules.count >= 8 {
                InfoNote(text: "決まりは8つまでです。")
            }
        }
    }

    private func ruleRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("決まり \(index + 1)")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            valueRow(
                label: "勤務がこの時間を超えたら",
                minutes: rules[index].overMinutes,
                range: 0...1439
            ) { rules[index].overMinutes = $0 }
            valueRow(
                label: "入れる休憩",
                minutes: rules[index].breakMinutes,
                range: 0...600
            ) { rules[index].breakMinutes = $0 }
            HStack(spacing: Space.xs) {
                SecondaryButton(title: "上へ", systemImage: "arrow.up", identifier: "breakrule.up.\(index)") { move(index, by: -1) }
                    .disabled(index == 0)
                SecondaryButton(title: "下へ", systemImage: "arrow.down", identifier: "breakrule.down.\(index)") { move(index, by: 1) }
                    .disabled(index == rules.count - 1)
                Button("削除") {
                    guard rules.indices.contains(index) else { return }
                    rules.remove(at: index)
                }
                .font(AppFont.label)
                .foregroundStyle(Theme.danger)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("決まり \(index + 1)を削除")
            }
        }
        .padding(Space.s)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private func valueRow(label: String, minutes: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: Space.xs)
                Text(Formatters.hours(minutes))
                    .font(AppFont.value.weight(.bold))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Space.xxs) {
                nudge("−15分", spoken: "\(label)を15分短く", delta: -15, minutes: minutes, range: range, set: set)
                nudge("+15分", spoken: "\(label)を15分長く", delta: 15, minutes: minutes, range: range, set: set)
                nudge("−1分", spoken: "\(label)を1分短く", delta: -1, minutes: minutes, range: range, set: set)
                nudge("+1分", spoken: "\(label)を1分長く", delta: 1, minutes: minutes, range: range, set: set)
            }
        }
    }

    private func nudge(
        _ title: String,
        spoken: String,
        delta: Int,
        minutes: Int,
        range: ClosedRange<Int>,
        set: @escaping (Int) -> Void
    ) -> some View {
        Button {
            set(min(range.upperBound, max(range.lowerBound, minutes + delta)))
        } label: {
            Text(title)
                .font(AppFont.label.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(spoken)
    }

    private func move(_ index: Int, by offset: Int) {
        let next = index + offset
        guard rules.indices.contains(index), rules.indices.contains(next) else { return }
        rules.swapAt(index, next)
    }
}
