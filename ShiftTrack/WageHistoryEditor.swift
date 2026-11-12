import SwiftUI

/// Dated hourly-wage periods for one workplace. Stored on the workplace's
/// existing `wageHistoryRaw` string; this screen does not add a model.
struct WageHistoryEditor: View {
    @Binding var entries: [Workplace.WageHistoryEntry]
    var currentWage: Int
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Draft?

    private struct Draft: Identifiable {
        var id = UUID()
        /// Index into `entries` while editing. Nil adds a period.
        var index: Int?
        var day: Date
        var wageText: String
    }

    private var ordered: [(offset: Int, entry: Workplace.WageHistoryEntry)] {
        entries.enumerated()
            .sorted { $0.element.at > $1.element.at }
            .map { (offset: $0.offset, entry: $0.element) }
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: "シフトの日以前でいちばん新しい時給を使います。履歴がない日は、勤務先の時給のままです。")
                if entries.isEmpty {
                    EmptyState(
                        systemImage: "clock.arrow.circlepath",
                        message: "履歴はまだありません。日付と時給を追加すると、その日以降の計算が変わります。"
                    )
                } else {
                    Card(spacing: 0) {
                        ForEach(Array(ordered.enumerated()), id: \.element.offset) { position, row in
                            if position > 0 { RowDivider() }
                            Button {
                                draft = Draft(
                                    index: row.offset,
                                    day: row.entry.at,
                                    wageText: String(row.entry.hourlyWage)
                                )
                            } label: {
                                NavRow(
                                    title: Formatters.longDay(row.entry.at),
                                    subtitle: "この日以降",
                                    value: Formatters.yen(row.entry.hourlyWage)
                                )
                            }
                            .buttonStyle(RowButtonStyle())
                            .accessibilityIdentifier("wage.history.\(Int(row.entry.at.timeIntervalSince1970))")
                        }
                    }
                }
                SecondaryButton(title: "期間を追加", systemImage: "plus", identifier: "wage.history.add") {
                    draft = Draft(
                        index: nil,
                        day: Calendar.current.startOfDay(for: .now),
                        wageText: currentWage > 0 ? String(currentWage) : ""
                    )
                }
            }
            .background(Theme.paper)
            .navigationTitle("時給の履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .sheet(item: $draft) { item in
                WageHistoryDraftSheet(draft: item, entries: $entries)
            }
        }
    }
}

private struct WageHistoryDraftSheet: View {
    var draft: WageHistoryEditor.Draft
    @Binding var entries: [Workplace.WageHistoryEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var wageText: String
    @State private var error = ""

    init(draft: WageHistoryEditor.Draft, entries: Binding<[Workplace.WageHistoryEntry]>) {
        self.draft = draft
        _entries = entries
        _day = State(initialValue: Calendar.current.startOfDay(for: draft.day))
        _wageText = State(initialValue: draft.wageText)
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                if !error.isEmpty {
                    InfoNote(text: error, tone: .error)
                }
                Card {
                    DatePicker(selection: $day, displayedComponents: .date) {
                        Text("この日から")
                            .font(AppFont.body)
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.signalInk)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("wage.history.day")
                    RowDivider()
                    YenField(label: "時給", text: $wageText, identifier: "wage.history.wage")
                }
                PrimaryButton(title: draft.index == nil ? "追加" : "変更を保存", identifier: "wage.history.save") {
                    save()
                }
                if draft.index != nil {
                    DestructiveButton(title: "この期間を削除", identifier: "wage.history.delete") {
                        if let index = draft.index, entries.indices.contains(index) {
                            entries.remove(at: index)
                        }
                        dismiss()
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle(draft.index == nil ? "期間を追加" : "期間を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
        }
    }

    private func save() {
        let digits = wageText.filter(\.isNumber)
        guard let wage = Int(digits), wage > 0 else {
            error = "時給を入れてください。"
            return
        }
        let start = Calendar.current.startOfDay(for: day)
        var next = entries
        if let index = draft.index, next.indices.contains(index) {
            next[index] = Workplace.WageHistoryEntry(at: start, hourlyWage: wage)
        } else {
            next.append(Workplace.WageHistoryEntry(at: start, hourlyWage: wage))
        }
        // One period per calendar day. The later edit replaces an earlier one on that day.
        var byDay: [Date: Int] = [:]
        for entry in next {
            byDay[Calendar.current.startOfDay(for: entry.at)] = entry.hourlyWage
        }
        entries = byDay.map { Workplace.WageHistoryEntry(at: $0.key, hourlyWage: $0.value) }
            .sorted { $0.at < $1.at }
        dismiss()
    }
}
