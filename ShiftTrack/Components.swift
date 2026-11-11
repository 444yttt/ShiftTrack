import SwiftUI

/// Root destinations. `InOutTab` cases in the reference binary are
/// list / calendar / workplaces / income / settings. The Japanese titles
/// below are words that appear in that binary. No screenshot shows the tab bar,
/// so this is not a pixel match.
enum AppTab: Int, CaseIterable, Identifiable {
    case list, calendar, workplaces, income, settings
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .list: "今日"
        case .calendar: "カレンダー"
        case .workplaces: "勤務先"
        case .income: "収入"
        case .settings: "設定"
        }
    }

    var symbol: String {
        switch self {
        // `0x1000253f0` builds the tab symbol from w21. 1, 2, and 3 are
        // calendar, building.2, and yensign. w21 == 0 does not confirm
        // slider.horizontal.3, so the list symbol stays sun.max.
        case .list: "sun.max"
        case .calendar: "calendar"
        case .workplaces: "building.2"
        case .income: "yensign"
        case .settings: "gearshape"
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(selection == tab ? Theme.lime : Theme.muted)
                            .frame(width: 28, height: 24)
                        Text(tab.title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(selection == tab ? Theme.lime : Theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier(tab.accessibilityID)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.tabBar.ignoresSafeArea(edges: .bottom))
    }
}

struct LimeCapsuleButton: View {
    var title: String
    var fillWidth = false
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fillWidth ? 15 : 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .padding(.horizontal, 14)
                .padding(.vertical, fillWidth ? 14 : 10)
                .background(Theme.lime)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

struct HelpButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.chip)
                Image(systemName: "questionmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ヘルプ")
    }
}

struct ShiftCard: View {
    var shift: WorkShift
    var includeTransport: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(shift.workplace?.color ?? Theme.lime)
                .frame(width: 6, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.workplace?.name ?? "勤務先なし")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(shift.scheduleLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                if !shift.notes.isEmpty {
                    Text(shift.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                if !shift.todos.isEmpty {
                    Text(shift.todos.map(\.title).joined(separator: "、"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("shift.todos")
                }
            }
            Spacer(minLength: 8)
            Text(Formatters.yen(shift.estimatedYen(includeTransport: includeTransport)))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.lime)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func darkSheet() -> some View { modifier(DarkSheetModifier()) }
}
