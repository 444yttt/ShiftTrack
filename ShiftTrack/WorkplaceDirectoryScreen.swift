import SwiftData
import SwiftUI

/// Workplace cards follow the reference screenshots: a black card, wage in Doto,
/// and an expanding pattern list. Creating a workplace opens the 3-step wizard.
struct WorkplaceDirectoryScreen: View {
    private enum Sheet: Identifiable {
        case wizard
        case edit(UUID)

        var id: String {
            switch self {
            case .wizard: "wizard"
            case .edit(let id): "edit-\(id.uuidString)"
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
                Text("勤務先はまだ登録されていません")
                    .font(.system(size: 14))
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

            Button {
                sheet = .wizard
            } label: {
                Label("勤務先を追加", systemImage: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.lime)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.ink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityIdentifier("workplace.add")
            .accessibilityLabel("勤務先を追加")
        }
        .background(Theme.background)
        .onAppear {
            if !GuideMemory.suppressed && !GuideMemory.seen("workplaces") {
                showGuide = true
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .wizard:
                WorkplaceWizard()
            case .edit(let id):
                WorkplaceEditorView(existingID: id)
            }
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
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                Text(workplace.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                Menu {
                    Button("編集") { sheet = .edit(workplace.uuid) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("時給")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text(yenBody(workplace.hourlyWage))
                    .font(.doto(28))
                    .foregroundStyle(Theme.lime)
                Text("円")
                    .foregroundStyle(Color.white)
            }
            if !workplace.place.isEmpty {
                Label(workplace.place, systemImage: "mappin")
                    .font(.system(size: 12))
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
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .accessibilityIdentifier("patterns.heading")
                ForEach(mine) { part in
                    HStack {
                        Text("\(Formatters.clock(part.startMinute))〜\(Formatters.clock(part.endMinute))  \(part.name)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Button {
                    sheet = .edit(workplace.uuid)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Theme.lime)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Button {
                expanded = open ? nil : workplace.uuid
            } label: {
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .bold))
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
            .font(.system(size: 13, weight: .bold))
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
