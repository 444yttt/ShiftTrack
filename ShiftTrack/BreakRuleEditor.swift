import SwiftUI

struct BreakRuleEditor: View {
    @Binding var rules: [InOutRecovered.BreakRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("上にある規則が、同じ時間のときは先に使われます。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            ForEach(rules.indices, id: \.self) { index in
                ruleRow(index)
            }
            Button {
                guard rules.count < 8 else { return }
                rules.append(.init(overMinutes: 360, breakMinutes: 45))
            } label: {
                Text("休憩の決まりを追加")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.lime)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(rules.count >= 8)
        }
    }

    private func ruleRow(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("この時間を超えたら")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.muted)
            stepRow(value: rules[index].overMinutes, range: 0...1439) { rules[index].overMinutes = $0 }
            Text("休憩 \(Formatters.hours(rules[index].breakMinutes))")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ink)
            stepRow(value: rules[index].breakMinutes, range: 0...600) { rules[index].breakMinutes = $0 }
            HStack(spacing: 8) {
                smallButton("上へ") { move(index, by: -1) }
                    .disabled(index == 0)
                smallButton("下へ") { move(index, by: 1) }
                    .disabled(index == rules.count - 1)
                smallButton("この決まりを削除") { rules.remove(at: index) }
            }
        }
        .padding(12)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepRow(value: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 8) {
            Text(Formatters.hours(value))
                .font(.title3.weight(.black))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                nudge("−15分", delta: -15, value: value, range: range, set: set)
                nudge("+15分", delta: 15, value: value, range: range, set: set)
            }
            HStack(spacing: 8) {
                nudge("−1分", delta: -1, value: value, range: range, set: set)
                nudge("+1分", delta: 1, value: value, range: range, set: set)
            }
        }
    }

    private func nudge(_ title: String, delta: Int, value: Int, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        Button {
            set(min(range.upperBound, max(range.lowerBound, value + delta)))
        } label: {
            Text(title)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.lime)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Theme.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func move(_ index: Int, by offset: Int) {
        let next = index + offset
        guard rules.indices.contains(next) else { return }
        rules.swapAt(index, next)
    }
}
