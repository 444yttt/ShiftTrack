import SwiftData
import SwiftUI

/// Workplace cards. The reference help string says a card opens that workplace's
/// shift patterns. There is no screenshot of this screen.
struct WorkplaceDirectoryScreen: View {
    @Query(sort: \Workplace.createdAt) private var workplaces: [Workplace]
    @State private var editorID: UUID?
    @State private var showCreator = false
    @State private var patternsFor: UUID?

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
                        HStack(spacing: 8) {
                            Button {
                                patternsFor = workplace.uuid
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
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(workplace.name)のパターン")
                            .accessibilityIdentifier("workplace.card")
                            Button("編集") { editorID = workplace.uuid }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.lime)
                        }
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.top, 8)
            }

            LimeCapsuleButton(title: "勤務先を追加", fillWidth: true) {
                showCreator = true
            }
            .padding(.top, 8)
            .accessibilityIdentifier("workplace.add")

        }
        .background(Theme.background)
        .sheet(isPresented: $showCreator) {
            WorkplaceEditorView(existingID: nil)
        }
        .sheet(isPresented: Binding(
            get: { editorID != nil },
            set: { if !$0 { editorID = nil } }
        )) {
            WorkplaceEditorView(existingID: editorID)
        }
        .sheet(isPresented: Binding(
            get: { patternsFor != nil },
            set: { if !$0 { patternsFor = nil } }
        )) {
            PatternListView(onlyWorkplaceID: patternsFor)
                .presentationBackground(Theme.background)
        }
    }
}
