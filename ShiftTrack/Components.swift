import SwiftUI

/// Tab order: 一覧, カレンダー, 勤務先, 年収, 設定.
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

/// Spacing scale shared by the screens so gaps stay consistent.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    /// Side gutter of every scrolling screen.
    static let gutter: CGFloat = 16
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
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol)
                            .designFont(17, weight: .semibold)
                            .symbolRenderingMode(.monochrome)
                            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : selection == tab)
                            .foregroundStyle(selection == tab ? Theme.ink : Color.white)
                            .frame(width: 40, height: 32)
                            .background(selection == tab ? Theme.lime : Color.clear)
                            .clipShape(Capsule())
                        Text(tab.title)
                            .designFont(11, weight: .semibold)
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier(tab.accessibilityID)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.tabBar)
        .clipShape(Capsule())
        // The bar sits inside the bottom safe area inset, so it already clears the home indicator.
        .padding(.horizontal, Space.l)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Theme.background)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Primary action. Ink text on lime is 13.8:1. The label scales with Dynamic Type
/// and the target is never shorter than 44pt.
struct LimeCapsuleButton: View {
    var title: String
    var fillWidth = false
    var identifier: String? = nil
    /// Design size override. Unset uses 17 for full-width and 15 for compact buttons.
    var designSize: CGFloat? = nil
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .designFont(designSize ?? (fillWidth ? 17 : 15), weight: .bold)
                .multilineTextAlignment(.center)
                .foregroundStyle(isEnabled ? Theme.ink : Theme.muted)
                .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: fillWidth ? 52 : 44)
                .padding(.horizontal, 16)
                .background(isEnabled ? Theme.lime : Theme.track)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableStyle(large: fillWidth))
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Secondary action: white pill, ink text, visible outline.
struct SecondaryPillButton: View {
    var title: String
    var systemImage: String? = nil
    var fillWidth = false
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .designFont(14, weight: .bold)
                }
                Text(title)
                    .designFont(15, weight: .bold)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, 16)
            .background(Theme.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(identifier ?? title)
    }
}

struct HelpButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white)
                Circle().stroke(Theme.border, lineWidth: 1)
                Image(systemName: "questionmark")
                    .designFont(18, weight: .bold)
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(PressableStyle())
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
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 52

    private var workplaceName: String { shift.workplace?.name ?? "勤務先なし" }
    private var yenText: String { Formatters.yen(shift.estimatedYen(includeTransport: includeTransport)) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(shift.workplace?.color ?? Theme.lime)
                    .frame(width: 6, height: barHeight)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workplaceName)
                        .designFont(17, weight: .bold)
                        .foregroundStyle(Theme.ink)
                    Text(shift.scheduleLabel)
                        .designFont(14)
                        .foregroundStyle(Theme.muted)
                    if !shift.notes.isEmpty {
                        Text(shift.notes)
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    if !shift.todos.isEmpty {
                        Text(shift.todos.map(\.title).joined(separator: "、"))
                            .designFont(13)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("shift.todos")
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                }
            }
            Text(yenText)
                .designFont(17, weight: .bold)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShiftSpeech.line(name: workplaceName, schedule: shift.scheduleLabel, yen: yenText))
    }
}

/// Workplace filter. Up to three workplaces share one row; more scroll sideways
/// so names stay readable instead of shrinking.
struct FilterChipBar: View {
    var workplaces: [Workplace]
    @Binding var selectedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if workplaces.count <= 3 {
            HStack(spacing: 6) { chips(equalWidth: true) }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { chips(equalWidth: false) }
                    .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private func chips(equalWidth: Bool) -> some View {
        chip(title: "全て", selected: selectedID == nil, equalWidth: equalWidth) {
            selectedID = nil
        }
        ForEach(workplaces) { workplace in
            chip(title: workplace.name, selected: selectedID == workplace.uuid, equalWidth: equalWidth) {
                selectedID = workplace.uuid
            }
        }
    }

    private func chip(title: String, selected: Bool, equalWidth: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if reduceMotion {
                action()
            } else {
                withAnimation(Motion.chip) { action() }
            }
        } label: {
            Text(title)
                .designFont(14, weight: .bold)
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: equalWidth ? .infinity : nil, minHeight: 44)
                .background(selected ? Theme.ink : Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Theme.ink : Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.xl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Sheet chrome shared by every editor: paper background, drag handle, readable bar.
struct DarkSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationBackground(Theme.background)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }
}

extension View {
    func darkSheet() -> some View { modifier(DarkSheetModifier()) }

    /// White rounded card used for grouped content.
    func surfaceCard(padding: CGFloat = 14, radius: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Content that scrolls up under the status bar and notch would show through the
/// clock. This paints the top safe area in the paper colour so scrolled content
/// ends at the safe-area edge instead.
struct TopSafeAreaCover: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                Theme.background
                    .frame(height: proxy.safeAreaInsets.top)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func topSafeAreaCover() -> some View { modifier(TopSafeAreaCover()) }
}
