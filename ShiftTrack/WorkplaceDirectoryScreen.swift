import SwiftData
import SwiftUI

/// Workplace cards. The reference help string says a card opens that workplace's
/// shift patterns. There is no screenshot of this screen.
struct WorkplaceDirectoryScreen: View {
    private enum Sheet: Identifiable {
        case create
        case edit(UUID)
        case patterns(UUID)

        var id: String {
            switch self {
            case .create:
                "create"
            case .edit(let id):
                "edit-\(id.uuidString)"
            case .patterns(let id):
                "patterns-\(id.uuidString)"
            }
        }
    }

    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @State private var sheet: Sheet?

    var body: some View {
        ScreenScroll {
            Text("勤務先")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .accessibilityIdentifier("workplaces.title")
            Text("カードを押すと、その勤務先のシフトパターンが開きます。パターンを保存しても、入っているシフトは変わりません。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if workplaces.isEmpty {
                Text("勤務先はまだ登録されていません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(workplaces) { workplace in
                        workplaceRow(workplace)
                    }
                }
                .padding(.top, 8)
            }

            LimeCapsuleButton(title: "勤務先を追加", fillWidth: true) {
                sheet = .create
            }
            .padding(.top, 8)
            .accessibilityIdentifier("workplace.add")

        }
        .background(Theme.background)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .create:
                WorkplaceEditorView(existingID: nil)
            case .edit(let id):
                WorkplaceEditorView(existingID: id)
            case .patterns(let id):
                PatternListView(onlyWorkplaceID: id)
                    .presentationBackground(Theme.background)
                    .presentationDetents([.large])
            }
        }
    }

    private func workplaceRow(_ workplace: Workplace) -> some View {
        HStack(spacing: 8) {
            Button {
                sheet = .patterns(workplace.uuid)
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(workplace.color)
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workplace.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text(workplace.payIsDaily ? "日給 \(Formatters.yen(workplace.dailyWage))" : "時給 \(Formatters.yen(workplace.hourlyWage))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(workplace.name)のパターン")
            .accessibilityIdentifier("workplace.card")
            Button("編集") { sheet = .edit(workplace.uuid) }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.lime)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
