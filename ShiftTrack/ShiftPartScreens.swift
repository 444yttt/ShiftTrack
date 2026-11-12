import SwiftData
import SwiftUI

/// Pattern controls for the calendar and the home screen.
/// Tapping a pattern puts its times, break and to-dos on the chosen day in one
/// step. The edit and manage entries open `ShiftPartEditor` and `ShiftPartList`.
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
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("シフトパターン")
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("pattern.heading")
                Text(gathering
                     ? "パターンを押すと、選んだ日すべてに時間・休憩・やることを置きます。"
                     : "押すと、\(Formatters.longDay(dayChipDay))に時間・休憩・やることを置きます。")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.xs)
            if !note.isEmpty {
                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "checkmark.circle")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityHidden(true)
                    Text(note)
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("pattern.result")
                    if let onUndo {
                        TextLinkButton(title: "取り消す", systemImage: "arrow.uturn.backward", identifier: "pattern.undo", action: onUndo)
                    }
                }
                .padding(.horizontal, Space.s)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .transition(.opacity)
            }
            if let pending {
                pendingCard(pending)
            }
            if showsGathering {
                HStack(spacing: Space.xs) {
                    SecondaryButton(
                        title: gathering ? "選ぶのを終える" : "日付をまとめて選ぶ",
                        systemImage: gathering ? "checkmark" : "calendar.badge.plus",
                        fillWidth: false,
                        identifier: "calendar.pick.mode",
                        action: onToggleGathering
                    )
                    if gathering {
                        Text("選んだ日 \(pickedCount)日")
                            .font(AppFont.label)
                            .foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("calendar.picked.count")
                    }
                }
                if gathering && patternDays.isEmpty {
                    InfoNote(text: "カレンダーの日付を押して選んでください。もう一度押すと外れます。")
                }
            }
            if visible.isEmpty {
                InfoNote(text: canCreate
                         ? "まだパターンがありません。よく入る時間を登録しておくと、1回押すだけで置けます。"
                         : "先に勤務先を1件登録してください。")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
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
                    VStack(spacing: Space.xs) {
                        ForEach(visible) { part in
                            HStack(spacing: Space.xs) {
                                Button {
                                    onPatternRow(part)
                                } label: {
                                    rowLabel(part)
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("\(identifierPrefix).pattern.\(part.name)")
                                IconButton(
                                    systemImage: "pencil",
                                    label: "\(part.name)を編集",
                                    identifier: "\(identifierPrefix).pattern.edit.\(part.name)"
                                ) {
                                    onEdit(part)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: Space.xs) {
                SecondaryButton(title: "パターンを作る", systemImage: "plus", identifier: "\(identifierPrefix).part.add", action: onCreate)
                    .disabled(!canCreate)
                if !visible.isEmpty {
                    SecondaryButton(title: "一覧", systemImage: "list.bullet", fillWidth: false, identifier: "\(identifierPrefix).part.manage", action: onManage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.allowed(Motion.chip, reduce: reduceMotion), value: note)
    }

    private func pendingCard(_ pending: ShiftPartPlace.Pending) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label("ほかのシフトがある日を含むため、置きませんでした", systemImage: "exclamationmark.circle")
                .font(AppFont.rowTitle)
                .foregroundStyle(Theme.ink)
            ForEach(Array(pending.clashes.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
            }
            InfoNote(text: "その日を外して選び直すか、「1件ずつ入力」から重ねて追加してください。何も追加していません。")
            TextLinkButton(title: "閉じる", identifier: "pattern.pending.close", action: onClosePending)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.ink, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pattern.pending")
    }

    private func timeLine(_ part: ShiftPart) -> String {
        "\(Formatters.clock(part.startMinute))–\(Formatters.clock(part.endMinute))"
    }

    private func swatch(_ part: ShiftPart) -> some View {
        Circle()
            .fill(Color(hexString: part.colorHex))
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func chipLabel(_ part: ShiftPart) -> some View {
        HStack(spacing: Space.xs) {
            swatch(part)
            VStack(alignment: .leading, spacing: 1) {
                Text(part.name)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink)
                Text(timeLine(part))
                    .font(AppFont.helper.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
            }
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.signalInk)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.s)
        .frame(minHeight: 52)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint("押すと、\(Formatters.longDay(dayChipDay))に置きます")
    }

    private func rowLabel(_ part: ShiftPart) -> some View {
        HStack(spacing: Space.s) {
            swatch(part)
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text(timeLine(part))
                    .font(AppFont.helper.monospacedDigit())
                    .foregroundStyle(Theme.ink2)
                Text(PatternBreak.summary(
                    modeRaw: part.breakModeRaw,
                    fixedMinutes: part.breakMinutes,
                    customRulesRaw: part.breakRulesRaw
                ))
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: Space.xs)
            Text(gathering ? "選んだ日に置く" : "置く")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Space.s)
                .frame(minHeight: 36)
                .background(Theme.signal, in: Capsule())
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

/// Break picker shared by the two pattern editors.
struct PatternBreakEditor: View {
    @Binding var modeRaw: Int
    @Binding var fixedMinutes: Int
    @Binding var rules: [InOutRecovered.BreakRule]

    private var mode: PatternBreakMode { PatternBreak.mode(modeRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SegmentedRow(label: "休憩の決め方", selection: $modeRaw, helper: PatternBreak.detail(mode), identifier: "pattern.breakMode") {
                ForEach(PatternBreakMode.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            switch mode {
            case .fixed:
                VStack(alignment: .leading, spacing: 6) {
                    Text("よく使う長さ")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.xs) {
                            ForEach([0, 30, 45, 60], id: \.self) { minutes in
                                ChipButton(title: minutes == 0 ? "なし" : "\(minutes)分", selected: fixedMinutes == minutes) {
                                    fixedMinutes = minutes
                                }
                            }
                        }
                        .padding(.vertical, 2)
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
}

/// Create or edit a pattern. Pass `partID` to edit; nil creates.
struct ShiftPartEditor: View {
    var partID: UUID? = nil
    /// Workplace chosen when a new pattern is started from a workplace card.
    var presetWorkplaceID: UUID? = nil
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
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: existing == nil
                         ? "よく入る時間をパターンにします。カレンダーやホームから、1回押すだけで置けます。"
                         : "変えた内容は、これから置くシフトに使われます。すでに置いたシフトは変わりません。")
                    .padding(.top, Space.xs)
                Card {
                    LabeledField(label: "パターンの名前（必須）", text: $name, prompt: "例：遅番", identifier: "field.パターン名")
                    if workplaces.isEmpty {
                        InfoNote(text: "先に勤務先を1件登録してください。", tone: .warning)
                    } else {
                        workplacePicker
                    }
                }
                if !workplaces.isEmpty {
                    SectionHeader(title: "時間")
                    Card {
                        HStack(alignment: .top, spacing: Space.xs) {
                            MinutesTimePicker(title: "開始", minutes: $startMinute)
                            MinutesTimePicker(title: "終了", minutes: $endMinute)
                        }
                        InfoNote(text: endsNextDay
                                 ? "終了が開始と同じか早いので、翌日に終わるシフトとして置きます。"
                                 : "同じ日の中で終わるシフトとして置きます。")
                    }
                    SectionHeader(title: "休憩")
                    Card {
                        PatternBreakEditor(modeRaw: $breakModeRaw, fixedMinutes: $breakMinutes, rules: $rules)
                    }
                    SectionHeader(title: "見た目とやること")
                    Card {
                        colorRow
                        LabeledField(
                            label: "やること（1行に1つ）",
                            text: $todoText,
                            prompt: "例：レジ締め",
                            helper: "置いたシフトに、未完了のやることとして入ります。設定でオンにするとリマインダーにも入ります。",
                            identifier: "field.やること",
                            multiline: true
                        )
                    }
                }
                if !error.isEmpty {
                    InfoNote(text: error, tone: .error)
                }
                if existing != nil {
                    DestructiveButton(title: "このパターンを削除", identifier: "pattern.delete") {
                        confirmDelete = true
                    }
                }
            }
            .background(Theme.paper)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: existing == nil ? "保存" : "変更を保存", identifier: "pattern.save", action: save)
                    .disabled(workplaces.isEmpty)
                    .padding(.horizontal, Space.gutter)
                    .padding(.vertical, Space.xs)
                    .background(Theme.paper)
            }
            .navigationTitle(existing == nil ? "パターンを作る" : "パターンを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                        .accessibilityIdentifier("pattern.editor.close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") {
                        typing = false
                        Keyboard.dismiss()
                    }
                    .foregroundStyle(Theme.signalInk)
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
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        ForEach(workplaces) { workplace in
                            ChipButton(title: workplace.name, selected: workplaceID == workplace.uuid) {
                                workplaceID = workplace.uuid
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } else {
            PickerRow(label: "勤務先", selection: $workplaceID, identifier: "pattern.workplace") {
                ForEach(workplaces) { workplace in
                    Text(workplace.name).tag(Optional(workplace.uuid))
                }
            }
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("カレンダーでの色")
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xxs) {
                    ForEach(Array(Theme.palette.enumerated()), id: \.element) { index, hex in
                        let selected = colorHex == hex
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Theme.ink.opacity(0.3), lineWidth: 1))
                                .overlay {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.black))
                                            .foregroundStyle(Color.readable(onHex: hex))
                                    }
                                }
                                .padding(3)
                                .overlay {
                                    if selected {
                                        Circle().stroke(Theme.ink, lineWidth: 2)
                                    }
                                }
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("色 \(index + 1)")
                        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
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
            workplaceID = presetWorkplaceID ?? workplaces.first?.uuid
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
            ScreenScroll(spacing: Space.s) {
                InfoNote(text: "パターンを選ぶと編集できます。消しても、すでに置いたシフトは残ります。")
                    .padding(.top, Space.xs)
                let visible = parts.filter { !$0.hidden }
                if visible.isEmpty {
                    EmptyState(systemImage: "square.stack", message: "パターンはまだありません")
                }
                ForEach(visible) { part in
                    card(part)
                }
                PrimaryButton(title: "パターンを作る", systemImage: "plus", identifier: "partlist.add") {
                    editing = PartRoute(partID: nil)
                }
                .disabled(workplaces.isEmpty)
            }
            .background(Theme.paper)
            .navigationTitle("パターンの一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
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
        return Card(spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(Color(hexString: part.colorHex))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Theme.ink.opacity(0.35), lineWidth: 1))
                    .accessibilityHidden(true)
                Text(part.name)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
            }
            Text("\(workplace?.name ?? "勤務先なし")・\(Formatters.clock(part.startMinute))–\(Formatters.clock(part.endMinute))")
                .font(AppFont.helper.monospacedDigit())
                .foregroundStyle(Theme.ink2)
            Text(PatternBreak.summary(modeRaw: part.breakModeRaw, fixedMinutes: part.breakMinutes, customRulesRaw: part.breakRulesRaw))
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
            HStack(spacing: Space.xs) {
                SecondaryButton(title: "編集", systemImage: "pencil", fillWidth: false, identifier: "partlist.edit.\(part.name)") {
                    editing = PartRoute(partID: part.uuid)
                }
                Spacer(minLength: 0)
                Button("削除") { deleting = part }
                    .font(AppFont.label)
                    .foregroundStyle(Theme.danger)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("partlist.delete.\(part.name)")
            }
        }
    }
}
