import SwiftData
import SwiftUI

/// Edits one shift's todos. The add label and the open circle are confirmed.
/// Where they sit on the screen is not. A finished item has no confirmed symbol.
struct TodoEditor: View {
    var shiftID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkShift.date) private var shifts: [WorkShift]
    @State private var draft = ""

    private var shift: WorkShift? { shifts.first { $0.uuid == shiftID } }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                if let shift {
                    Text(shift.workplace?.name ?? "勤務先")
                        .designFont(16, weight: .bold)
                    Text(Formatters.longDay(shift.date))
                        .designFont(13)
                        .foregroundStyle(Theme.muted)
                    ForEach(shift.todos) { item in
                        Button {
                            toggle(item.id, on: shift)
                        } label: {
                            HStack(spacing: 8) {
                                if let symbol = ConfirmedSymbols.todoMark(done: item.done) {
                                    Image(systemName: symbol)
                                } else {
                                    Text("済")
                                        .designFont(13, weight: .bold)
                                }
                                Text(item.title)
                                    .designFont(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(PressableStyle())
                        .foregroundStyle(Theme.ink)
                    }
                    Text("やることを追加")
                        .designFont(16, weight: .bold)
                    TextField("やること", text: $draft)
                        .designFont(16)
                        .padding(ScreenInsets.todo)
                        .background(Theme.cardRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("todo.draft")
                    Button("追加") { add(on: shift) }
                        .buttonStyle(PressableStyle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("todo.add")
                }
            }
            .background(Theme.background)
            .navigationTitle("やること")
            .toolbar {
                Button("閉じる") { dismiss() }
                    .accessibilityIdentifier("todo.close")
            }
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
}
