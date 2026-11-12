import SwiftData
import SwiftUI

/// Workplace cards follow the reference screenshots: a black card, wage in Doto,
/// and an expanding pattern list. Creating a workplace opens the 3-step wizard.
struct WorkplaceDirectoryScreen: View {
    private enum Sheet: Identifiable {
        case wizard
        case edit(UUID)
        case partNew
        case partEdit(UUID)

        var id: String {
            switch self {
            case .wizard: "wizard"
            case .edit(let id): "edit-\(id.uuidString)"
            case .partNew: "part-new"
            case .partEdit(let id): "part-\(id.uuidString)"
            }
        }
    }

    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @Query(sort: \ShiftPart.createdAt) private var parts: [ShiftPart]
    @State private var sheet: Sheet?
    @State private var expanded: UUID?
    @State private var showGuide = false

    var body: some View {
        ScreenScroll {
            HStack {
                InOutWordmark()
                Spacer()
                HelpButton { showGuide = true }
            }
            if workplaces.isEmpty {
                Text("勤務先はまだありません。1件追加すると、シフトと収入の見込みが使えます。")
                    .designFont(14)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .accessibilityIdentifier("workplaces.title")
            } else {
                VStack(spacing: 12) {
                    ForEach(workplaces) { workplace in
                        workplaceCard(workplace)
                    }
                }
                .padding(.top, 12)
                Text("勤務先")
                    .font(.system(size: 1))
                    .foregroundStyle(Theme.background)
                    .accessibilityIdentifier("workplaces.title")
            }

            LimeCapsuleButton(title: "勤務先を追加", fillWidth: true, identifier: "workplace.add") {
                sheet = .wizard
            }
            .padding(.top, 12)
        }
        .background(Theme.background)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .wizard:
                WorkplaceWizard()
            case .edit(let id):
                WorkplaceEditorView(existingID: id)
            case .partNew:
                ShiftPartEditor()
                    .presentationBackground(Theme.background)
            case .partEdit(let id):
                ShiftPartEditor(partID: id)
                    .presentationBackground(Theme.background)
            }
        }
        .onChange(of: showGuide) { _, on in
            ScreenDim.shared.isOn = on
        }
        .overlay {
            if showGuide {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    GuideCard(
                        page: 1,
                        total: GuideCopy.workplaces.count,
                        text: GuideCopy.workplaces[0],
                        onBack: nil,
                        onNext: {
                            GuideMemory.mark("workplaces")
                            showGuide = false
                        },
                        onClose: {
                            GuideMemory.mark("workplaces")
                            showGuide = false
                        }
                    )
                }
            }
        }
    }

    private func workplaceCard(_ workplace: Workplace) -> some View {
        let open = expanded == workplace.uuid
        let mine = parts.filter { $0.workplaceUUID == workplace.uuid && !$0.hidden }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(workplace.color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(String(workplace.name.prefix(1)))
                            .designFont(18, weight: .bold)
                            .foregroundStyle(Color.readable(onHex: workplace.colorHex))
                    }
                Text(workplace.name)
                    .designFont(18, weight: .bold)
                    .foregroundStyle(Color.white)
                Spacer()
                Menu {
                    Button("編集") { sheet = .edit(workplace.uuid) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("時給")
                    .designFont(13)
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(yenBody(workplace.hourlyWage))
                    .font(.doto(28))
                    .foregroundStyle(Theme.lime)
                Text("円")
                    .foregroundStyle(Color.white)
            }
            if !workplace.place.isEmpty {
                Label(workplace.place, systemImage: "mappin")
                    .designFont(12)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
            }
            HStack(spacing: 8) {
                capsule("MAP")
                capsule("電話")
                capsule("メッセージ")
            }
            if open {
                Text("シフトパターン")
                    .designFont(13)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .accessibilityIdentifier("patterns.heading")
                ForEach(mine) { part in
                    Button {
                        sheet = .partEdit(part.uuid)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Formatters.clock(part.startMinute))〜\(Formatters.clock(part.endMinute))  \(part.name)")
                                    .designFont(15, weight: .bold)
                                    .foregroundStyle(Theme.ink)
                                Text(PatternBreak.summary(modeRaw: part.breakModeRaw, fixedMinutes: part.breakMinutes, customRulesRaw: part.breakRulesRaw))
                                    .designFont(13)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(14)
                        .frame(minHeight: 56)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(part.name)を編集")
                }
                Button {
                    sheet = .partNew
                } label: {
                    Label("パターンを追加", systemImage: "plus")
                        .designFont(15, weight: .bold)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Theme.lime)
                        .clipShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("workplace.pattern.add")
            }
            Button {
                expanded = open ? nil : workplace.uuid
            } label: {
                // Recovered names are chevron.up / chevron.down. Which bit means open is unrecovered.
                // A collapsed card in the screenshot shows the downward chevron.
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .designFont(14, weight: .bold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(open ? "patterns.close" : "workplace.card")
            .accessibilityLabel("\(workplace.name)のパターン")
        }
        .padding(16)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func capsule(_ title: String) -> some View {
        Text(title)
            .designFont(13, weight: .bold)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(Capsule())
    }

    private func yenBody(_ value: Int) -> String {
        let body = Formatters.yen(value)
        return body.hasPrefix("¥") ? String(body.dropFirst()) : body
    }
}
