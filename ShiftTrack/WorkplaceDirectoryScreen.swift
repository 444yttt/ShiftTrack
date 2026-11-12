import SwiftData
import SwiftUI

/// 勤務先. One white card per workplace: pay, payday rhythm, working contact
/// actions, and its shift patterns. New workplaces go through the wizard.
struct WorkplaceDirectoryScreen: View {
    private enum Sheet: Identifiable {
        case wizard
        case edit(UUID)
        case partNew(UUID)
        case partEdit(UUID)
        case message(UUID)
        case help

        var id: String {
            switch self {
            case .wizard: "wizard"
            case .edit(let id): "edit-\(id.uuidString)"
            case .partNew(let id): "part-new-\(id.uuidString)"
            case .partEdit(let id): "part-\(id.uuidString)"
            case .message(let id): "message-\(id.uuidString)"
            case .help: "help"
            }
        }
    }

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]
    @State private var sheet: Sheet?
    @State private var expanded: UUID?

    var body: some View {
        ScreenScroll(spacing: Space.m) {
            ScreenHeader(title: "勤務先", subtitle: workplaces.isEmpty ? nil : "\(workplaces.count)件") {
                HelpButton { sheet = .help }
            }
            if workplaces.isEmpty {
                EmptyState(
                    systemImage: "building.2",
                    message: "勤務先はまだありません。登録すると、シフトと給料の見込みが使えるようになります。"
                )
                .accessibilityIdentifier("workplaces.title")
            } else {
                ForEach(workplaces) { workplace in
                    workplaceCard(workplace)
                }
            }
            PrimaryButton(title: "勤務先を追加", systemImage: "plus", identifier: "workplace.add") {
                sheet = .wizard
            }
        }
        .background(Theme.paper)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .wizard:
                WorkplaceWizard()
            case .edit(let id):
                WorkplaceEditorView(existingID: id)
            case .partNew(let id):
                ShiftPartEditor(presetWorkplaceID: id)
                    .presentationBackground(Theme.paper)
            case .partEdit(let id):
                ShiftPartEditor(partID: id)
                    .presentationBackground(Theme.paper)
            case .message(let id):
                if let place = workplaces.first(where: { $0.uuid == id }) {
                    MessageComposerSheet(workplace: place)
                }
            case .help:
                HelpSheet(title: "勤務先について", paragraphs: HelpCopy.workplaces)
            }
        }
    }

    private func workplaceCard(_ workplace: Workplace) -> some View {
        let open = expanded == workplace.uuid
        let mine = parts.filter { $0.workplaceUUID == workplace.uuid && !$0.hidden }
        let mapReason = WorkplaceContact.mapReason(for: workplace)
        let phoneReason = WorkplaceContact.phoneReason(for: workplace)
        return Card(spacing: Space.s) {
            HStack(spacing: Space.s) {
                Circle()
                    .fill(workplace.color)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Theme.ink.opacity(0.2), lineWidth: 1))
                    .overlay {
                        Text(String(workplace.name.prefix(1)))
                            .font(.headline)
                            .foregroundStyle(Color.readable(onHex: workplace.colorHex))
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workplace.name)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Theme.ink)
                    if !workplace.genre.isEmpty {
                        Text(workplace.genre)
                            .font(AppFont.helper)
                            .foregroundStyle(Theme.ink2)
                    }
                }
                Spacer(minLength: Space.xs)
                SecondaryButton(title: "編集", systemImage: "pencil", fillWidth: false, identifier: "workplace.edit.\(workplace.name)") {
                    sheet = .edit(workplace.uuid)
                }
            }
            HStack(spacing: Space.xs) {
                StatTile(
                    title: workplace.payIsDaily ? "日給" : "時給",
                    value: Formatters.yen(workplace.payIsDaily ? workplace.dailyWage : workplace.hourlyWage)
                )
                StatTile(title: "交通費（1回）", value: Formatters.yen(workplace.transportAllowance))
            }
            Label(PayWindows.phrase(workplace), systemImage: "calendar.badge.clock")
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
            if !workplace.place.isEmpty {
                Label(workplace.place, systemImage: "mappin.and.ellipse")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
            HStack(alignment: .top, spacing: Space.xs) {
                QuickActionTile(title: "地図", systemImage: "map.fill", disabledReason: mapReason, identifier: "workplace.action.map.\(workplace.name)") {
                    if let url = WorkplaceContact.mapURL(for: workplace) { openURL(url) }
                }
                QuickActionTile(title: "電話", systemImage: "phone.fill", disabledReason: phoneReason, identifier: "workplace.action.phone.\(workplace.name)") {
                    if let url = WorkplaceContact.telURL(workplace.phone) { openURL(url) }
                }
                QuickActionTile(title: "メッセージ", systemImage: "message.fill", disabledReason: phoneReason, identifier: "workplace.action.message.\(workplace.name)") {
                    sheet = .message(workplace.uuid)
                }
            }
            RowDivider()
            Button {
                if reduceMotion {
                    expanded = open ? nil : workplace.uuid
                } else {
                    withAnimation(Motion.layout) { expanded = open ? nil : workplace.uuid }
                }
            } label: {
                HStack {
                    Text(mine.isEmpty ? "シフトパターン（まだありません）" : "シフトパターン \(mine.count)件")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: Space.xs)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.ink2)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel("\(workplace.name)のシフトパターン")
            .accessibilityValue(open ? "開いています" : "閉じています")
            .accessibilityIdentifier(open ? "patterns.close" : "workplace.card")
            if open {
                Text("シフトパターン")
                    .font(AppFont.helper)
                    .foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("patterns.heading")
                ForEach(mine) { part in
                    Button {
                        sheet = .partEdit(part.uuid)
                    } label: {
                        NavRow(
                            title: part.name,
                            subtitle: "\(Formatters.clock(part.startMinute))〜\(Formatters.clock(part.endMinute))・\(PatternBreak.summary(modeRaw: part.breakModeRaw, fixedMinutes: part.breakMinutes, customRulesRaw: part.breakRulesRaw))"
                        )
                    }
                    .buttonStyle(RowButtonStyle())
                    .accessibilityHint("押すと編集します")
                }
                SecondaryButton(title: "パターンを追加", systemImage: "plus", identifier: "workplace.pattern.add") {
                    sheet = .partNew(workplace.uuid)
                }
            }
        }
    }
}
