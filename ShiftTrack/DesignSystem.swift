import SwiftUI
import UIKit

// Shared building blocks of the redesign. Tokens and rules: docs/design/redesign.md.

/// Spacing scale on a 4-pt grid.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Side gutter of every scrolling screen.
    static let gutter: CGFloat = 16
    /// Gap between sections of a screen.
    static let section: CGFloat = 24
}

enum Radius {
    static let control: CGFloat = 12
    static let card: CGFloat = 20
    static let hero: CGFloat = 28
}

/// Reading measure for regular-width windows (iPad portrait and landscape,
/// and any other regular size class). Compact phones keep the full width.
enum Readable {
    static let column: CGFloat = 680
}

// MARK: - Containers

/// White card. The one container style for grouped content.
struct Card<Content: View>: View {
    var spacing: CGFloat = Space.s
    var padding: CGFloat = Space.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Title of a tab screen with optional trailing buttons.
struct ScreenHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.screenTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: Space.xs)
            trailing
        }
        .padding(.top, Space.xs)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Section title above a card, with an optional line that says what the section is for.
struct SectionHeader: View {
    var title: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.xs)
            if let actionTitle, let action {
                TextLinkButton(title: actionTitle, identifier: actionIdentifier, action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Space.xs)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Helper or warning text inside a card.
struct InfoNote: View {
    enum Tone { case plain, warning, error }
    var text: String
    var tone: Tone = .plain
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol = systemImage ?? defaultSymbol {
                Image(systemName: symbol)
                    .font(AppFont.helper.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(AppFont.helper)
                .foregroundStyle(tone == .plain ? Theme.ink2 : color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        switch tone {
        case .plain: Theme.ink2
        case .warning: Theme.ink
        case .error: Theme.danger
        }
    }

    private var defaultSymbol: String? {
        switch tone {
        case .plain: nil
        case .warning: "exclamationmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }
}

// MARK: - Rows

/// A row that opens something. Put it in a `Button` or `NavigationLink`.
struct NavRow: View {
    var systemImage: String? = nil
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var external = false

    var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.signalInk)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.xs)
            if let value {
                Text(value)
                    .font(AppFont.value)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
            }
            Image(systemName: external ? "arrow.up.right" : "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.ink2)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Label on the left, a value on the right. Read-only.
struct ValueRow: View {
    var title: String
    var value: String
    var emphasized = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppFont.body)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Space.xs)
            Text(value)
                .font(emphasized ? AppFont.value.weight(.bold) : AppFont.value)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inputs

/// Text field with its label always visible above it.
struct LabeledField: View {
    var label: String
    @Binding var text: String
    var prompt: String = ""
    var helper: String? = nil
    var error: String? = nil
    var keyboard: UIKeyboardType = .default
    var identifier: String? = nil
    var multiline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            Group {
                if multiline {
                    TextField(prompt, text: $text, axis: .vertical)
                        .lineLimit(2...6)
                } else {
                    TextField(prompt, text: $text)
                }
            }
            .font(AppFont.body)
            .foregroundStyle(Theme.ink)
            .keyboardType(keyboard)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(error == nil ? Theme.stroke : Theme.danger, lineWidth: 1)
            )
            .accessibilityLabel(label)
            .accessibilityHint(helper ?? "")
            .accessibilityIdentifier(identifier ?? "field.\(label)")
            if let error, !error.isEmpty {
                InfoNote(text: error, tone: .error)
            } else if let helper {
                InfoNote(text: helper)
            }
        }
    }
}

/// Amount field: visible label, “¥”, number pad, and the amount with separators.
struct YenField: View {
    var label: String
    @Binding var text: String
    var prompt: String = "0"
    var helper: String? = nil
    var error: String? = nil
    var signed = false
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            HStack(spacing: 6) {
                Text("¥")
                    .font(AppFont.value)
                    .foregroundStyle(Theme.ink2)
                    .accessibilityHidden(true)
                TextField(prompt, text: $text)
                    .font(AppFont.value)
                    .foregroundStyle(Theme.ink)
                    .keyboardType(signed ? .numbersAndPunctuation : .numberPad)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier ?? "field.\(label)")
                if let preview = YenField.preview(text, signed: signed) {
                    Text(preview)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Space.s)
            .frame(minHeight: 48)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .stroke(error == nil ? Theme.stroke : Theme.danger, lineWidth: 1)
            )
            if let error, !error.isEmpty {
                InfoNote(text: error, tone: .error)
            } else if let helper {
                InfoNote(text: helper)
            }
        }
    }

    /// `12,345円` for a typed `12345`; nil while empty.
    static func preview(_ raw: String, signed: Bool) -> String? {
        let digits = raw.filter(\.isNumber)
        guard let value = Int(digits), digits.count >= 4 else { return nil }
        let negative = signed && (raw.hasPrefix("-") || raw.hasPrefix("−"))
        return (negative ? "−" : "") + Formatters.yenDigits(value) + "円"
    }
}

/// A menu picker that always shows what it is for.
struct PickerRow<Value: Hashable, Options: View>: View {
    var label: String
    @Binding var selection: Value
    var helper: String? = nil
    var identifier: String? = nil
    @ViewBuilder var options: Options
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Space.xs))
            layout {
                Text(label)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Space.xs)
                }
                Picker(label, selection: $selection) {
                    options
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Theme.signalInk)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier ?? "picker.\(label)")
            }
            .frame(minHeight: 44)
            if let helper {
                InfoNote(text: helper)
            }
        }
    }
}

/// Segmented choice with a visible label. Falls back to a menu at the largest text sizes.
struct SegmentedRow<Value: Hashable, Options: View>: View {
    var label: String
    @Binding var selection: Value
    var helper: String? = nil
    var identifier: String? = nil
    @ViewBuilder var options: Options
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Picker(label, selection: $selection) { options }
                        .pickerStyle(.menu)
                        .tint(Theme.signalInk)
                } else {
                    Picker(label, selection: $selection) { options }
                        .pickerStyle(.segmented)
                }
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier ?? "segment.\(label)")
            if let helper {
                InfoNote(text: helper)
            }
        }
    }
}

/// Switch with a title and a line that says what “on” does. The “on” track is
/// the deep olive so the state reads at a glance against the grey “off” track.
struct ToggleRow: View {
    var title: String
    var helper: String? = nil
    @Binding var isOn: Bool
    var identifier: String? = nil

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let helper {
                    Text(helper)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.signalInk)
        .frame(minHeight: 44)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Stepper whose label and value are separate texts.
struct StepperRow: View {
    var label: String
    var valueText: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var helper: String? = nil
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: $value, in: range, step: step) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: Space.xs)
                    Text(valueText)
                        .font(AppFont.value)
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(minHeight: 44)
            .accessibilityValue(valueText)
            .accessibilityIdentifier(identifier ?? label)
            if let helper {
                InfoNote(text: helper)
            }
        }
    }
}

/// Seven weekday chips with a visible label. 1 = Sunday.
struct WeekdayPicker: View {
    var label: String
    @Binding var days: Set<Int>
    var helper: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            WeekdaySelector(days: $days)
            if let helper {
                InfoNote(text: helper)
            }
        }
    }
}

// MARK: - Buttons

/// The main action of a screen. Ink on lime is 13.8:1.
struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var identifier: String? = nil
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .multilineTextAlignment(.center)
            }
            .font(.body.weight(.bold))
            .foregroundStyle(isEnabled ? Theme.ink : Theme.ink2)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, Space.m)
            .background(isEnabled ? Theme.signal : Theme.sunken, in: Capsule())
            .overlay {
                if !isEnabled {
                    Capsule().stroke(Theme.stroke, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(large: true))
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Second-level action: white, outlined, ink text.
struct SecondaryButton: View {
    var title: String
    var systemImage: String? = nil
    var fillWidth = true
    var identifier: String? = nil
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .multilineTextAlignment(.center)
            }
            .font(AppFont.label)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.ink2)
            .frame(maxWidth: fillWidth ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, Space.m)
            .background(isEnabled ? Theme.surface : Theme.sunken, in: Capsule())
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Destructive action, written out in red text so it is not mistaken for the main action.
struct DestructiveButton: View {
    var title: String
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Text-only action in the accent ink, at least 44 pt tall.
struct TextLinkButton: View {
    var title: String
    var systemImage: String? = nil
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(AppFont.label)
            .foregroundStyle(Theme.signalInk)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Round 44-pt icon button with a spoken label.
struct IconButton: View {
    var systemImage: String
    var label: String
    var prominent = false
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(prominent ? Theme.signal : Theme.surface, in: Circle())
                .overlay {
                    if !prominent {
                        Circle().stroke(Theme.stroke, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? label)
    }
}

/// Selectable chip. Selected is an ink fill with white text; otherwise white with an outline.
struct ChipButton: View {
    var title: String
    var selected: Bool
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, Space.m)
                .frame(minHeight: 44)
                .background(selected ? Theme.ink : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.ink : Theme.stroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// One of the three workplace actions (地図 / 電話 / メッセージ). When the workplace
/// lacks the data, the tile is disabled and says why under the icon.
struct QuickActionTile: View {
    var title: String
    var systemImage: String
    /// nil when the action is available.
    var disabledReason: String?
    var identifier: String
    var action: () -> Void

    private var enabled: Bool { disabledReason == nil }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(enabled ? Theme.ink : Theme.ink2)
                    .frame(width: 48, height: 48)
                    .background(enabled ? Theme.signal : Theme.sunken, in: Circle())
                    .overlay {
                        if !enabled {
                            Circle().stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(enabled ? Theme.ink : Theme.ink2)
                if let disabledReason {
                    Text(disabledReason)
                        .font(AppFont.helper)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.xxs)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.control + 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control + 4, style: .continuous)
                    .stroke(enabled ? Color.clear : Theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        // Keep the button's own element so the disabled state reaches VoiceOver
        // (“dimmed”) and UI tests; the label replaces the reason text inside.
        .accessibilityLabel(title)
        .accessibilityHint(disabledReason ?? "")
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Figures

/// Dot-matrix numerals. Grows with Dynamic Type (relative to `.largeTitle`) but
/// is capped, stays on one line, and is read by VoiceOver as `spoken`.
struct DotoText: View {
    var text: String
    var size: CGFloat
    var spoken: String?
    var color: Color = Theme.ink
    var maxScale: CGFloat = 1.5
    @ScaledMetric(relativeTo: .largeTitle) private var scaled: CGFloat = 40

    init(_ text: String, size: CGFloat, spoken: String? = nil, color: Color = Theme.ink, maxScale: CGFloat = 1.5) {
        self.text = text
        self.size = size
        self.spoken = spoken
        self.color = color
        self.maxScale = maxScale
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
    }

    var body: some View {
        Text(text)
            .font(.custom(Font.dotoName, fixedSize: min(scaled, size * maxScale)))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel(spoken ?? text)
    }
}

/// Track and fill. The fill is the accent ink so the amount reads at 3:1 or more.
struct ProgressBar: View {
    var value: Double
    var label: String
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sunken)
                Capsule()
                    .fill(Theme.signalInk)
                    .frame(width: max(0, proxy.size.width * min(1, max(0, value.isFinite ? value : 0))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Formatters.percent(value.isFinite ? min(1, max(0, value)) : 0, decimals: false))
    }
}

/// Small figure with a caption, used in summary cards.
struct StatTile: View {
    var title: String
    var value: String
    var spoken: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
            Text(value)
                .font(AppFont.value)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(spoken ?? value)")
    }
}

/// Empty content with one optional next step.
struct EmptyState: View {
    var systemImage: String = "tray"
    var message: String
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Theme.ink2)
                .accessibilityHidden(true)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, identifier: actionIdentifier, action: action)
                    .padding(.top, Space.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
        .padding(.horizontal, Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// Small status pill, e.g. 勤務中.
struct StatusChip: View {
    var text: String
    var emphasized = false

    var body: some View {
        Text(text)
            .font(AppFont.badge)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(emphasized ? Theme.signal : Theme.sunken, in: Capsule())
    }
}

/// Ends text editing wherever the focus is (fields wrapped in `LabeledField`
/// are not bound to a screen's own focus state).
enum Keyboard {
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Button style for whole rows: dims a little while pressed.
struct RowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.allowed(Motion.press, reduce: reduce), value: configuration.isPressed)
    }
}
