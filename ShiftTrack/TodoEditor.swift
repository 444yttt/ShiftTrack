import SwiftData
import SwiftUI

/// やること for one shift: check items off, add new ones, delete them.
struct TodoEditor: View {
    var shiftID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @State private var draft = ""

    private var shift: WorkShift? { shifts.first { $0.uuid == shiftID } }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                if let shift {
                    Text("\(shift.workplace?.name ?? "勤務先")・\(Formatters.longDay(shift.date)) \(Formatters.clock(shift.startMinutes))〜")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, Space.xs)
                    Card(spacing: 0) {
                        if shift.todos.isEmpty {
                            Text("やることはまだありません")
                                .font(AppFont.body)
                                .foregroundStyle(Theme.ink2)
                                .frame(minHeight: 44)
                        }
                        ForEach(shift.todos) { item in
                            HStack(spacing: Space.xs) {
                                Button {
                                    toggle(item.id, on: shift)
                                } label: {
                                    HStack(spacing: Space.s) {
                                        Image(systemName: item.done ? "checkmark.circle.fill" : ConfirmedSymbols.todoMark(done: false) ?? "circle")
                                            .font(.title3)
                                            .foregroundStyle(item.done ? Theme.signalInk : Theme.ink2)
                                            .accessibilityHidden(true)
                                        Text(item.title)
                                            .font(AppFont.body)
                                            .foregroundStyle(item.done ? Theme.ink2 : Theme.ink)
                                            .strikethrough(item.done, color: Theme.ink2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(minHeight: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(RowButtonStyle())
                                .accessibilityLabel(item.title)
                                .accessibilityValue(item.done ? "完了" : "未完了")
                                .accessibilityAddTraits(item.done ? [.isSelected, .isButton] : .isButton)
                                Button {
                                    remove(item.id, on: shift)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(Theme.danger)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(item.title)を削除")
                            }
                            RowDivider()
                        }
                    }
                    Card {
                        LabeledField(label: "やることを追加", text: $draft, prompt: "例：レジ締め", identifier: "todo.draft")
                            .submitLabel(.done)
                            .onSubmit { add(on: shift) }
                        PrimaryButton(title: "追加", systemImage: "plus", identifier: "todo.add") { add(on: shift) }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        InfoNote(text: "設定で「やることをリマインダーに書き出す」をオンにすると、リマインダーにも入ります。")
                    }
                } else {
                    EmptyState(systemImage: "questionmark.folder", message: "このシフトは見つかりませんでした")
                }
            }
            .background(Theme.paper)
            .navigationTitle("やること")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("todo.close")
                }
            }
            .darkSheet()
        }
    }

    private func add(on shift: WorkShift) {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var items = shift.todos
        items.append(ShiftTodoCodec.Item(id: UUID(), title: title, done: false))
        shift.todos = items
        try? context.save()
        draft = ""
    }

    private func toggle(_ id: UUID, on shift: WorkShift) {
        var items = shift.todos
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
        shift.todos = items
        try? context.save()
    }

    private func remove(_ id: UUID, on shift: WorkShift) {
        var items = shift.todos
        items.removeAll { $0.id == id }
        shift.todos = items
        try? context.save()
    }
}
