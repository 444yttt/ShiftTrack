import SwiftData
import SwiftUI

/// Pattern controls for the calendar and the today list.
/// Tapping a pattern puts its times, break and todos on the chosen day in one step.
/// The edit and manage entries open `ShiftPartEditor` and `ShiftPartList`.
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
    var onEdit: (ShiftPart) -> Void = { _ in }
    var onManage: () -> Void = {}
    /// Set right after a tap that added shifts. Shows 「取り消す」.
    var onUndo: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visible: [ShiftPart] {
        parts.filter { !$0.hidden }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("シフトパターン")
                .designFont(18, weight: .bold)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("pattern.heading")
            Text("タップすると、\(Formatters.longDay(dayChipDay))に時間・休憩・やることをまとめて置きます。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if !note.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(note)
                        .designFont(14, weight: .bold)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("pattern.result")
                    if let onUndo {
                        Button("取り消す", action: onUndo)
                            .designFont(14, weight: .bold)
                            .foregroundStyle(Theme.accentText)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("pattern.undo")
                    }
                }
                .transition(.opacity)
            }
            if let pending {
                pendingCard(pending)
            }
            if showsGathering {
                HStack(spacing: 10) {
                    SecondaryPillButton(
                        title: gathering ? "選ぶのを終える" : "日付をまとめて選ぶ",
                        systemImage: gathering ? "checkmark" : "calendar.badge.plus",
                        identifier: "calendar.pick.mode",
                        action: onToggleGathering
                    )
                    if gathering {
                        Text("選んだ日 \(pickedCount)")
                            .designFont(14, weight: .bold)
                            .foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("calendar.picked.count")
                    }
                }
            }
            if visible.isEmpty {
                Text(canCreate ? "まだパターンがありません。よく使う時間を登録しておくと、1タップで置けます。" : "先に勤務先を1件追加してください。")
                    .designFont(14)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visible) { part in
                            Button {
                                onDayChip(part)
                            } label: {
                                chipLabel(part)
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button("編集", systemImage: "pencil") { onEdit(part) }
                            }
                            .accessibilityIdentifier("\(identifierPrefix).daychip.\(part.name)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                if showsPatternRows {
                    Text(gathering
                         ? "下の行をタップすると、選んだ日すべてに置きます。"
                         : "下の行は、日付を選んでいなければ\(Formatters.longDay(dayChipDay))だけに置きます。")
                        .designFont(13)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        ForEach(visible) { part in
                            HStack(spacing: 8) {
                                Button {
                                    onPatternRow(part)
                                } label: {
                                    rowLabel(part)
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("\(identifierPrefix).pattern.\(part.name)")
                                Button {
                                    onEdit(part)
                                } label: {
                                    Image(systemName: "pencil")
                                        .designFont(16, weight: .bold)
                                        .foregroundStyle(Theme.ink)
                                        .frame(width: 48, height: 48)
                                        .background(Theme.card)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel("\(part.name)を編集")
                                .accessibilityIdentifier("\(identifierPrefix).pattern.edit.\(part.name)")
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                LimeCapsuleButton(title: "パターンを作る", fillWidth: true, identifier: "\(identifierPrefix).part.add", action: onCreate)
                    .disabled(!canCreate)
                if !visible.isEmpty {
                    SecondaryPillButton(title: "一覧", systemImage: "list.bullet", identifier: "\(identifierPrefix).part.manage", action: onManage)
                }
            }
            if patternDays.isEmpty && gathering {
                Text("カレンダーの日付をタップして選んでください。")
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .animation(Motion.allowed(Motion.chip, reduce: reduceMotion), value: note)
    }

    private func pendingCard(_ pending: ShiftPartPlace.Pending) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("確認が必要な日があります")
                .designFont(15, weight: .bold)
                .foregroundStyle(Theme.ink)
            Text("このシフトは確認が必要です")
                .designFont(14, weight: .bold)
                .foregroundStyle(Theme.accentText)
            ForEach(Array(pending.clashes.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .designFont(14)
                    .foregroundStyle(Theme.ink)
            }
            Text("別のシフトがある日があるため、今回は何も追加していません。")
                .designFont(13)
                .foregroundStyle(Theme.muted)
            Button("閉じる", action: onClosePending)
                .designFont(14, weight: .bold)
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pattern.pending.close")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pattern.pending")
    }

    private func timeLine(_ part: ShiftPart) -> String {
        "\(Formatters.clock(part.startMinute))–\(Formatters.clock(part.endMinute))"
    }

    private func chipLabel(_ part: ShiftPart) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hexString: part.colorHex))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(part.name)
                    .designFont(15, weight: .bold)
                    .foregroundStyle(Theme.ink)
                Text(timeLine(part))
                    .designFont(12)
                    .foregroundStyle(Theme.muted)
            }
            Text("置く")
                .designFont(13, weight: .bold)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.lime)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Theme.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint("タップすると、\(Formatters.longDay(dayChipDay))に置きます")
    }

    private func rowLabel(_ part: ShiftPart) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hexString: part.colorHex))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .designFont(16, weight: .bold)
                    .foregroundStyle(Theme.ink)
                Text(timeLine(part))
                    .designFont(14)
                    .foregroundStyle(Theme.muted)
                Text(PatternBreak.summary(
                    modeRaw: part.breakModeRaw,
                    fixedMinutes: part.breakMinutes,
                    customRulesRaw: part.breakRulesRaw
                ))
                    .designFont(13)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text("置く")
                .designFont(14, weight: .bold)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Theme.lime)
                .clipShape(Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// Break picker shared by the two pattern editors.
struct PatternBreakEditor: View {
    @Binding var modeRaw: Int
    @Binding var fixedMinutes: Int
    @Binding var rules: [InOutRecovered.BreakRule]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var mode: PatternBreakMode { PatternBreak.mode(modeRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("休憩")
                .designFont(15, weight: .bold)
                .foregroundStyle(Theme.ink)
            if dynamicTypeSize.isAccessibilitySize {
                Picker("休憩のきめ方", selection: $modeRaw) { options }
                    .pickerStyle(.menu)
            } else {
                Picker("休憩のきめ方", selection: $modeRaw) { options }
                    .pickerStyle(.segmented)
            }
            Text(PatternBreak.detail(mode))
                .designFont(13)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            switch mode {
            case .fixed:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([0, 30, 45, 60], id: \.self) { minutes in
                            quick(minutes)
                        }
                    }
                }
                BreakMinutesControl(minutes: $fixedMinutes, range: 0...600)
            case .workplace:
                EmptyView()
            case .custom:
                BreakRuleEditor(rules: $rules)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var options: some View {
        ForEach(PatternBreakMode.allCases) { item in
            Text(item.title).tag(item.rawValue)
        }
    }

    private func quick(_ minutes: Int) -> some View {
        let selected = fixedMinutes == minutes
        return Button {
            fixedMinutes = minutes
        } label: {
            Text(minutes == 0 ? "なし" : "\(minutes)分")
                .designFont(14, weight: .bold)
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? Theme.ink : Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Theme.ink : Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Create or edit a pattern. Pass `partID` to edit; nil creates.
struct ShiftPartEditor: View {
    var partID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]

    @State private var name = ""
    @State private var workplaceID: UUID?
    @State private var startMinute = 10 * 60
    @State private var endMinute = 15 * 60
    @State private var breakModeRaw = PatternBreakMode.fixed.rawValue
    @State private var breakMinutes = 0
    @State private var rules: [InOutRecovered.BreakRule] = []
    @State private var colorHex = Theme.palette[0]
    @State private var todoText = ""
    @State private var error = ""
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var typing: Bool

    private var existing: ShiftPart? { parts.first { $0.uuid == partID } }

    private var endsNextDay: Bool {
        InOutRecovered.patternEndAddsOneDay(startMinute: startMinute, endMinute: endMinute)
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                VStack(alignment: .leading, spacing: 14) {
                    Text(existing == nil
                         ? "よく使う時間を、パターンにして登録します。"
                         : "変えた内容は、これから置くシフトに使われます。すでに置いたシフトは変わりません。")
                        .designFont(14)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("パターンの名前（例：遅番）", text: $name)
                        .focused($typing)
                        .submitLabel(.done)
                        .designFont(17, weight: .medium)
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .frame(minHeight: 52)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                        .accessibilityIdentifier("field.パターン名")
                    if workplaces.isEmpty {
                        Text("先に勤務先を1件追加してください。")
                            .designFont(14)
                            .foregroundStyle(Theme.muted)
                    } else {
                        workplacePicker
                        HStack(alignment: .top, spacing: 10) {
                            MinutesTimePicker(title: "開始", minutes: $startMinute)
                            MinutesTimePicker(title: "終了", minutes: $endMinute)
                        }
                        Text(endsNextDay
                             ? "終了が開始と同じか早いので、翌日の終了として置きます。"
                             : "同じ日の中で置きます。")
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                        PatternBreakEditor(modeRaw: $breakModeRaw, fixedMinutes: $breakMinutes, rules: $rules)
                            .surfaceCard()
                        colorRow
                        VStack(alignment: .leading, spacing: 6) {
                            Text("やること（1行に1つ）")
                                .designFont(14, weight: .medium)
                                .foregroundStyle(Theme.muted)
                            TextField("改行で複数", text: $todoText, axis: .vertical)
                                .lineLimit(2...6)
                                .focused($typing)
                                .designFont(17)
                                .foregroundStyle(Theme.ink)
                                .padding(ScreenInsets.todo)
                                .background(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                                .accessibilityIdentifier("field.やること")
                            Text("置いたシフトには、やることが未完了で入ります。設定でオンにするとリマインダーにも入ります。")
                                .designFont(13)
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !error.isEmpty {
                        Text(error)
                            .designFont(14, weight: .medium)
                            .foregroundStyle(Theme.behind)
                    }
                    if existing != nil {
                        Button("このパターンを削除") { confirmDelete = true }
                            .designFont(16, weight: .bold)
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .accessibilityIdentifier("pattern.delete")
                    }
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LimeCapsuleButton(title: existing == nil ? "保存" : "変更を保存", fillWidth: true, identifier: "pattern.save", designSize: 17, action: save)
                    .disabled(workplaces.isEmpty)
                    .padding(.horizontal, Space.gutter)
                    .padding(.vertical, 10)
                    .background(Theme.background)
            }
            .navigationTitle(existing == nil ? "パターンを作る" : "パターンを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("pattern.editor.close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { typing = false }
                }
            }
            .darkSheet()
            .onAppear(perform: load)
            .alert("このパターンを削除しますか？", isPresented: $confirmDelete) {
                Button("削除", role: .destructive, action: deletePart)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("すでに置いたシフトは消えません。")
            }
        }
    }

    @ViewBuilder private var workplacePicker: some View {
        if workplaces.count <= 4 {
            VStack(alignment: .leading, spacing: 6) {
                Text("勤務先")
                    .designFont(14, weight: .medium)
                    .foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(workplaces) { workplace in
                            let selected = workplaceID == workplace.uuid
                            Button {
                                workplaceID = workplace.uuid
                            } label: {
                                Text(workplace.name)
                                    .designFont(15, weight: .bold)
                                    .foregroundStyle(selected ? Color.white : Theme.ink)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                                    .background(selected ? Theme.ink : Theme.card)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(selected ? Theme.ink : Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        } else {
            Picker("勤務先", selection: $workplaceID) {
                ForEach(workplaces) { workplace in
                    Text(workplace.name).tag(Optional(workplace.uuid))
                }
            }
            .tint(Theme.accentText)
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("色")
                .designFont(14, weight: .medium)
                .foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Theme.palette, id: \.self) { hex in
                        let selected = colorHex == hex
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 1))
                                .overlay {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundStyle(hex == "111111" ? Color.white : Theme.ink)
                                    }
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("色 \(hex)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            name = existing.name
            workplaceID = existing.workplaceUUID
            startMinute = existing.startMinute
            endMinute = existing.endMinute
            breakModeRaw = existing.breakModeRaw
            breakMinutes = existing.breakMinutes
            rules = BreakRules.decode(existing.breakRulesRaw)
            colorHex = existing.colorHex
            todoText = existing.defaultTodos.map(\.title).joined(separator: "\n")
        } else if workplaceID == nil {
            workplaceID = workplaces.first?.uuid
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "パターンの名前を入れてください。"
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
        // A todo whose title did not change keeps its id.
        let previous = existing?.defaultTodos ?? []
        let todos = lines.map { line in
            ShiftTodoCodec.Item(
                id: previous.first(where: { $0.title == line })?.id ?? UUID(),
                title: String(line),
                done: false
            )
        }
        let storedRules = BreakRules.encode(rules)
        let storedBreak = ShiftDatePolicy.clampedBreak(breakMinutes, range: 0...600)
        if let existing {
            existing.name = trimmed
            existing.workplaceUUID = workplaceID
            existing.startMinute = startMinute
            existing.endMinute = endMinute
            existing.breakModeRaw = breakModeRaw
            existing.breakMinutes = storedBreak
            existing.breakRulesRaw = storedRules
            existing.colorHex = colorHex
            existing.defaultTodosRaw = ShiftTodoCodec.encode(todos)
        } else {
            context.insert(ShiftPart(
                name: trimmed,
                workplaceUUID: workplaceID,
                startMinute: startMinute,
                endMinute: endMinute,
                breakMinutes: storedBreak,
                defaultTodosRaw: ShiftTodoCodec.encode(todos),
                colorHex: colorHex,
                breakModeRaw: breakModeRaw,
                breakRulesRaw: storedRules
            ))
        }
        do {
            try context.save()
        } catch {
            self.error = ShiftPartPlace.saveFailedText
            return
        }
        dismiss()
    }

    private func deletePart() {
        guard let existing else { return }
        context.delete(existing)
        try? context.save()
        dismiss()
    }
}

/// Every saved pattern in one place: edit, delete, or add another.
struct ShiftPartList: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @State private var editing: PartRoute?
    @State private var deleting: ShiftPart?

    struct PartRoute: Identifiable {
        var id: String { partID?.uuidString ?? "new" }
        var partID: UUID?
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                VStack(alignment: .leading, spacing: 10) {
                    Text("パターンを選んで編集できます。削除しても、すでに置いたシフトは残ります。")
                        .designFont(14)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(parts.filter { !$0.hidden }) { part in
                        card(part)
                    }
                    LimeCapsuleButton(title: "パターンを作る", fillWidth: true, identifier: "partlist.add") {
                        editing = PartRoute(partID: nil)
                    }
                    .disabled(workplaces.isEmpty)
                    .padding(.top, 6)
                }
                .padding(.top, 8)
            }
            .background(Theme.background)
            .navigationTitle("パターンの一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("partlist.close")
                }
            }
            .darkSheet()
            .sheet(item: $editing) { route in
                ShiftPartEditor(partID: route.partID)
            }
            .alert("このパターンを削除しますか？", isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            )) {
                Button("削除", role: .destructive) {
                    if let deleting {
                        context.delete(deleting)
                        try? context.save()
                    }
                    deleting = nil
                }
                Button("キャンセル", role: .cancel) { deleting = nil }
            } message: {
                Text("すでに置いたシフトは消えません。")
            }
        }
    }

    private func card(_ part: ShiftPart) -> some View {
        let workplace = workplaces.first { $0.uuid == part.workplaceUUID }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hexString: part.colorHex))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 1))
                Text(part.name)
                    .designFont(17, weight: .bold)
                    .foregroundStyle(Theme.ink)
            }
            Text("\(workplace?.name ?? "勤務先なし")  \(Formatters.clock(part.startMinute))–\(Formatters.clock(part.endMinute))")
                .designFont(14)
                .foregroundStyle(Theme.muted)
            Text(PatternBreak.summary(modeRaw: part.breakModeRaw, fixedMinutes: part.breakMinutes, customRulesRaw: part.breakRulesRaw))
                .designFont(13)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                SecondaryPillButton(title: "編集", systemImage: "pencil", identifier: "partlist.edit.\(part.name)") {
                    editing = PartRoute(partID: part.uuid)
                }
                Button("削除") { deleting = part }
                    .designFont(15, weight: .bold)
                    .foregroundStyle(Theme.destructive)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("partlist.delete.\(part.name)")
            }
        }
        .surfaceCard()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
