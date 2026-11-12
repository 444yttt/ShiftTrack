import SwiftUI

/// Tabs of the system tab bar, left to right. UI tests find them by title
/// (`app.tabBars.buttons["カレンダー"]`).
enum AppTab: Int, CaseIterable, Identifiable {
    case list, calendar, income, workplaces, settings
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .list: "ホーム"
        case .calendar: "カレンダー"
        case .income: "給料"
        case .workplaces: "勤務先"
        case .settings: "設定"
        }
    }

    /// Outline names; the tab bar shows the filled variant itself.
    var symbol: String {
        switch self {
        case .list: "house"
        case .calendar: "calendar"
        case .income: "yensign.circle"
        case .workplaces: "building.2"
        case .settings: "gearshape"
        }
    }
}

extension View {
    /// One tab of the root `TabView`: paper fills the whole tab (it shows through
    /// the bar's material), the status bar gets its cover, and the bar item is
    /// the standard title + SF Symbol.
    func appTab(_ tab: AppTab) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
            .topSafeAreaCover()
            .tabItem { Label(tab.title, systemImage: tab.symbol) }
            .tag(tab)
    }
}

/// Primary action (kept for existing call sites). Same look as `PrimaryButton`;
/// compact buttons size to their text.
struct LimeCapsuleButton: View {
    var title: String
    var fillWidth = false
    var identifier: String? = nil
    /// Kept for source compatibility; the redesign uses Dynamic Type text styles.
    var designSize: CGFloat? = nil
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(isEnabled ? Theme.onSignal : Theme.ink2)
                .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: fillWidth ? 52 : 44)
                .padding(.horizontal, Space.m)
                .background(isEnabled ? Theme.signal : Theme.sunken, in: Capsule())
                .overlay {
                    if !isEnabled {
                        Capsule().stroke(Theme.stroke, lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(large: fillWidth))
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Secondary action (kept for existing call sites): white pill, ink text, outline.
struct SecondaryPillButton: View {
    var title: String
    var systemImage: String? = nil
    var fillWidth = false
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        SecondaryButton(title: title, systemImage: systemImage, fillWidth: fillWidth, identifier: identifier, action: action)
    }
}

struct HelpButton: View {
    var action: () -> Void

    var body: some View {
        IconButton(systemImage: "questionmark", label: "ヘルプ", identifier: "help", action: action)
    }
}

enum ShiftSpeech {
    static func line(name: String, schedule: String, yen: String) -> String {
        "\(name)、\(schedule)、\(yen)"
    }

    /// What VoiceOver reads for a shift row: workplace, date and time, estimate, to-dos.
    static func card(_ shift: WorkShift, includeTransport: Bool) -> String {
        var text = line(
            name: shift.workplace?.name ?? "勤務先なし",
            schedule: shift.scheduleLabel,
            yen: Formatters.yen(shift.estimatedYen(includeTransport: includeTransport))
        )
        let todos = shift.todos.map(\.title)
        if !todos.isEmpty {
            text += "、やること " + todos.joined(separator: "、")
        }
        return text
    }
}

/// One shift in a list: colour bar, workplace, date and time, to-dos, estimate.
struct ShiftCard: View {
    var shift: WorkShift
    var includeTransport: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var workplaceName: String { shift.workplace?.name ?? "勤務先なし" }
    private var yenText: String { Formatters.yen(shift.estimatedYen(includeTransport: includeTransport)) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.s))
        layout {
            HStack(alignment: .top, spacing: Space.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workplaceName)
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text(shift.scheduleLabel)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                    if !shift.notes.isEmpty {
                        Text(shift.notes)
                            .font(AppFont.helper)
                            .foregroundStyle(Theme.ink2)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    if !shift.todos.isEmpty {
                        Label(shift.todos.map(\.title).joined(separator: "、"), systemImage: "checklist")
                            .font(AppFont.helper)
                            .foregroundStyle(Theme.ink2)
                            .accessibilityIdentifier("shift.todos")
                    }
                }
                .frame(minHeight: 44, alignment: .topLeading)
                .padding(.leading, 6 + Space.s)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(shift.workplace?.color ?? Theme.signal)
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Theme.ink.opacity(0.15), lineWidth: 1))
                        .frame(width: 6)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Space.xs)
                }
            }
            Text(yenText)
                .font(AppFont.value)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShiftSpeech.card(shift, includeTransport: includeTransport))
        .accessibilityHint("押すと編集できます")
    }
}

/// Workplace filter. Up to three workplaces share one row; more scroll sideways
/// so names stay readable instead of shrinking.
struct FilterChipBar: View {
    var workplaces: [Workplace]
    @Binding var selectedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("表示する勤務先")
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
                .accessibilityHidden(true)
            if workplaces.count <= 2 {
                HStack(spacing: 6) { chips }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { chips }
                        .padding(.vertical, 2)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("表示する勤務先")
    }

    @ViewBuilder private var chips: some View {
        ChipButton(title: "すべて", selected: selectedID == nil, identifier: "filter.all") {
            select(nil)
        }
        ForEach(workplaces) { workplace in
            ChipButton(title: workplace.name, selected: selectedID == workplace.uuid, identifier: "filter.\(workplace.name)") {
                select(workplace.uuid)
            }
        }
    }

    private func select(_ id: UUID?) {
        if reduceMotion {
            selectedID = id
        } else {
            withAnimation(Motion.chip) { selectedID = id }
        }
    }
}

/// Scrolling page with the standard gutter and a leading-aligned column.
struct ScreenScroll<Content: View>: View {
    var spacing: CGFloat = Space.s
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .presentationBackground(Theme.paper)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.hero)
            .toolbarBackground(Theme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    /// Name kept from the dark theme; it applies the paper sheet chrome.
    func darkSheet() -> some View { modifier(DarkSheetModifier()) }

    /// White rounded card used for grouped content.
    func surfaceCard(padding: CGFloat = Space.m, radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Content that scrolls up under the status bar would show through behind the
/// clock. This paints the top safe area in the paper colour so scrolled
/// content ends at the safe-area edge instead.
struct TopSafeAreaCover: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                Theme.paper
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
