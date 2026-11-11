import SwiftUI

/// Tab order is the screenshot: 一覧, カレンダー, 勤務先, 年収, 設定.
/// `calendar`, `building.2`, and `yensign` are the recovered names for the
/// middle three. `slider.horizontal` is the recovered 17-byte name and sits on
/// 設定; `w21 == 0` is not the leftmost tab. 一覧's symbol name is not in that
/// switch, so the glyph follows the screenshot (`archivebox.fill`).
enum AppTab: Int, CaseIterable, Identifiable {
    case list, calendar, workplaces, income, settings
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .list: "一覧"
        case .calendar: "カレンダー"
        case .workplaces: "勤務先"
        case .income: "年収"
        case .settings: "設定"
        }
    }

    var symbol: String {
        switch self {
        case .list: "archivebox.fill"
        case .calendar: "calendar"
        case .workplaces: "building.2"
        case .income: "yensign"
        case .settings: "slider.horizontal"
        }
    }

    var accessibilityID: String {
        switch self {
        case .list: "tab.today"
        case .calendar: "tab.calendar"
        case .workplaces: "tab.workplaces"
        case .income: "tab.income"
        case .settings: "tab.settings"
        }
    }
}

struct CustomTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    if reduceMotion {
                        selection = tab
                    } else {
                        withAnimation(Motion.chip) { selection = tab }
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .designFont(16, weight: .semibold)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(selection == tab ? Theme.ink : Color.white)
                            .frame(width: 36, height: 36)
                            .background(selection == tab ? Theme.lime : Color.clear)
                            .clipShape(Circle())
                        // The screenshot shows the label smaller than the symbol.
                        // Root's only recovered design size is 16, used on the symbol above.
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier(tab.accessibilityID)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.tabBar)
        .clipShape(Capsule())
        .padding(ScreenInsets.root)
        .padding(.bottom, 8)
        .background(Theme.background)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct LimeCapsuleButton: View {
    var title: String
    var fillWidth = false
    var identifier: String? = nil
    /// Design size for screens whose text goes through Dynamic Type scaling.
    /// Screens outside that list leave this unset.
    var designSize: CGFloat? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .padding(.horizontal, 14)
                .padding(.vertical, fillWidth ? 14 : 10)
                .background(Theme.lime)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableStyle(large: fillWidth))
        .accessibilityIdentifier(identifier ?? title)
    }

    @ViewBuilder private var label: some View {
        if let designSize {
            Text(title).designFont(designSize, weight: .bold)
        } else {
            Text(title).font(.system(size: fillWidth ? 15 : 13, weight: .bold))
        }
    }
}

struct HelpButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white)
                Image(systemName: "questionmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ヘルプ")
    }
}

enum ShiftSpeech {
    static func line(name: String, schedule: String, yen: String) -> String {
        "\(name)、\(schedule)、\(yen)"
    }
}

struct ShiftCard: View {
    var shift: WorkShift
    var includeTransport: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var workplaceName: String { shift.workplace?.name ?? "勤務先なし" }
    private var yenText: String { Formatters.yen(shift.estimatedYen(includeTransport: includeTransport)) }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(shift.workplace?.color ?? Theme.lime)
                .frame(width: 6, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(workplaceName)
                    .designFont(15, weight: .bold)
                    .foregroundStyle(Theme.ink)
                Text(shift.scheduleLabel)
                    .designFont(12)
                    .foregroundStyle(Theme.muted)
                if !shift.notes.isEmpty {
                    Text(shift.notes)
                        .designFont(11)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                if !shift.todos.isEmpty {
                    Text(shift.todos.map(\.title).joined(separator: "、"))
                        .designFont(11)
                        .foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("shift.todos")
                }
            }
            Spacer(minLength: 8)
            Text(yenText)
                .designFont(14, weight: .bold)
                .foregroundStyle(Theme.lime)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShiftSpeech.line(name: workplaceName, schedule: shift.scheduleLabel, yen: yenText))
    }
}

struct FilterChipBar: View {
    var workplaces: [Workplace]
    @Binding var selectedID: UUID?

    var body: some View {
        HStack(spacing: 6) {
            chip(title: "全て", selected: selectedID == nil) {
                selectedID = nil
            }
            ForEach(workplaces) { workplace in
                chip(title: workplace.name, selected: selectedID == workplace.uuid) {
                    selectedID = workplace.uuid
                }
            }
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Theme.lime : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(selected ? Theme.chip : Theme.cardRaised)
                .clipShape(Capsule())
                .overlay {
                    if !selected {
                        Capsule().stroke(Theme.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

struct DarkSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationBackground(Theme.background)
            .presentationDragIndicator(.visible)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }
}

extension View {
    func darkSheet() -> some View { modifier(DarkSheetModifier()) }
}
