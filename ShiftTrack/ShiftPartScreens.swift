import SwiftData
import SwiftUI

/// Pattern controls for the calendar and the today list.
/// The strings 「シフトパターン」, 「この日に置く」, 「シフトパターンを作る」,
/// 「パターンの名前（例：遅番）」, 「シフトパターンに追加」, and
/// 「確認が必要な日があります」 are cstrings from the reference binary.
/// No screenshot ties them to a frame, so this is not a pixel match.
struct ShiftPartSection: View {
    var parts: [ShiftPart]
    var dayChipDay: Date
    var patternDays: [Date]
    var note: String
    var pending: ShiftPartPlace.Pending?
    var canCreate: Bool
    var gathering: Bool
    var pickedCount: Int
    var showsGathering: Bool = true
    var showsPatternRows: Bool = true
    var identifierPrefix: String = "calendar"
    var onToggleGathering: () -> Void
    var onCreate: () -> Void
    var onDayChip: (ShiftPart) -> Void
    var onPatternRow: (ShiftPart) -> Void
    var onClosePending: () -> Void

    private var visible: [ShiftPart] {
        parts.filter { !$0.hidden }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("シフトパターン")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("pattern.heading")
            Text("日付をいくつか選んで、シフトパターンをまとめて置いたり、外したりします。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("外す命令は未回収なので、ここは置くだけです。別のシフトがある日は、重なりの式が未回収のため保留し、そのタップでは1件も追加しません。同じパターンが既にある日は足しません。休憩の分数は写しません。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(note)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("pattern.result")
            if let pending {
                pendingCard(pending)
            }
            if showsGathering {
                Button(gathering ? "選ぶのを終える" : "日付をいくつか選ぶ") {
                    onToggleGathering()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.lime)
                .accessibilityIdentifier("calendar.pick.mode")
                if gathering {
                    Text("選んだ日 \(pickedCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("calendar.picked.count")
                }
            }
            if visible.isEmpty {
                Text(canCreate ? "シフトパターンはまだありません" : "先に勤務先を1件追加してください。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            } else {
                Text(showsPatternRows
                     ? "日チップは\(Formatters.longDay(dayChipDay))に置きます。下の行は、選んだ日がなければその日だけです。"
                     : "日チップは\(Formatters.longDay(dayChipDay))に置きます。週の矢印とスワイプは見ている日だけを変え、入っているシフトの日付は変えません。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visible) { part in
                            Button {
                                onDayChip(part)
                            } label: {
                                chipLabel(part)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(identifierPrefix).daychip.\(part.name)")
                        }
                    }
                }
                if showsPatternRows {
                    VStack(spacing: 8) {
                        ForEach(visible) { part in
                            Button {
                                onPatternRow(part)
                            } label: {
                                rowLabel(part)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("\(identifierPrefix).pattern.\(part.name)")
                        }
                    }
                }
            }
            LimeCapsuleButton(title: "シフトパターンを作る", fillWidth: true, identifier: "\(identifierPrefix).part.add", action: onCreate)
                .disabled(!canCreate)
            if patternDays.isEmpty && gathering {
                Text("日付を選んでください")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func pendingCard(_ pending: ShiftPartPlace.Pending) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("確認が必要な日があります")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Text("このシフトは確認が必要です")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.lime)
            ForEach(Array(pending.clashes.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            Text("このタップではシフトを追加していません。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Button("閉じる", action: onClosePending)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.lime)
                .accessibilityIdentifier("pattern.pending.close")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("pattern.pending")
    }

    private func chipLabel(_ part: ShiftPart) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hexString: part.colorHex))
                .frame(width: 8, height: 8)
            Text(part.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Text("この日に置く")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.lime)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.card)
        .clipShape(Capsule())
    }

    private func rowLabel(_ part: ShiftPart) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hexString: part.colorHex))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(Formatters.clock(part.startMinute))–\(Formatters.clock(part.endMinute))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text("休憩は置きません")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text("この日に置く")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.lime)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ShiftPartEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]

    @State private var name = ""
    @State private var workplaceID: UUID?
    @State private var startMinute = 10 * 60
    @State private var endMinute = 15 * 60
    @State private var todoText = ""
    @State private var error = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScreenScroll {
                Text("シフトパターンを作る")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("置くとき、開始と終了と勤務先だけを読みます。パターンに残した休憩は写しません。法定休憩も入れません。開始が終了以上のときは終了を翌日にします。同じ分も翌日です。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("パターンの名前（例：遅番）", text: $name)
                    .focused($typing)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Theme.cardRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("field.パターン名")
                if workplaces.isEmpty {
                    Text("先に勤務先を1件追加してください。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                } else {
                    Picker("勤務先", selection: $workplaceID) {
                        ForEach(workplaces) { workplace in
                            Text(workplace.name).tag(Optional(workplace.uuid))
                        }
                    }
                    .tint(Theme.lime)
                    HStack(alignment: .top, spacing: 10) {
                        MinutesTimePicker(title: "開始", minutes: $startMinute)
                        MinutesTimePicker(title: "終了", minutes: $endMinute)
                    }
                    Text("やることを追加")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    TextField("改行で複数", text: $todoText, axis: .vertical)
                        .focused($typing)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Theme.cardRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("field.やること")
                    Text("置いたシフトでは、やることは未了のままです。丸を押してリマインダーへ反映する操作はこの経路にありません。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.behind)
                }
                LimeCapsuleButton(title: "シフトパターンに追加", fillWidth: true, identifier: "pattern.save", action: save)
                    .disabled(workplaces.isEmpty)
            }
            .background(Theme.background)
            .navigationTitle("シフトパターン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.lime)
                        .accessibilityIdentifier("pattern.editor.close")
                }
            }
            .onAppear {
                if workplaceID == nil {
                    workplaceID = workplaces.first?.uuid
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "パターンの名前を入れてください"
            return
        }
        guard let workplaceID else {
            error = "勤務先を選んでください。"
            return
        }
        let lines = todoText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let todos = lines.map { ShiftTodoCodec.Item(id: UUID(), title: String($0), done: false) }
        let part = ShiftPart(
            name: trimmed,
            workplaceUUID: workplaceID,
            startMinute: startMinute,
            endMinute: endMinute,
            breakMinutes: 0,
            defaultTodosRaw: ShiftTodoCodec.encode(todos),
            colorHex: Theme.palette[trimmed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Theme.palette.count]
        )
        context.insert(part)
        do {
            try context.save()
        } catch {
            context.delete(part)
            self.error = ShiftPartPlace.saveFailedText
            return
        }
        dismiss()
    }
}
