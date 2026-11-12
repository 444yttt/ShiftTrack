import SwiftUI

/// The raw values behind `Theme`, kept so the contrast tests read the same numbers.
enum ThemeHex {
    static let background: UInt = 0xF3F1EC
    static let card: UInt = 0xFFFFFF
    static let cardRaised: UInt = 0xE6E3DC
    static let tabBar: UInt = 0x1C1C1E
    static let lime: UInt = 0xC6F24E
    static let ink: UInt = 0x111111
    static let muted: UInt = 0x5C5C63
    static let accentText: UInt = 0x41570A
    static let danger: UInt = 0xB3261E
}

enum Theme {
    /// Paper, white cards, and black pills follow the reference screenshots.
    /// Stacking distances were not recovered from the binary.
    static let background = Color(hex: ThemeHex.background)
    static let card = Color(hex: ThemeHex.card)
    static let cardRaised = Color(hex: ThemeHex.cardRaised)
    static let chip = Color(hex: 0xF7F6F2)
    static let dayFilled = Color(hex: 0x111111)
    static let tabBar = Color(hex: ThemeHex.tabBar)
    static let lime = Color(hex: ThemeHex.lime)
    static let ink = Color(hex: ThemeHex.ink)
    static let onDark = Color.white
    /// Secondary text. 5.9:1 on `background` and 6.7:1 on white (WCAG AA needs 4.5:1).
    static let muted = Color(hex: ThemeHex.muted)
    /// Lime is a fill colour only. Text and icons drawn in the accent on a light
    /// surface use this deep olive: 7.2:1 on `background`, 8.1:1 on white.
    static let accentText = Color(hex: ThemeHex.accentText)
    static let line = Color(hex: 0xE4E1DA)
    static let border = Color(hex: 0xA9A59C)
    static let track = Color(hex: 0xE6E3DC)
    /// Error and "behind goal" text. 6.5:1 on white.
    static let behind = Color(hex: ThemeHex.danger)
    static let destructive = Color(hex: ThemeHex.danger)

    static let palette = ["C6F24E", "111111", "F4A7A0", "B7D7C5", "F3C1D3", "A9C7F5", "C7B6E4", "F3D98A"]
}

extension Font {
    /// Official Google Fonts Doto, instantiated at Black and maximum roundness.
    /// The reference calls this face `Doto-BlackRound`. The file is not from the IPA.
    /// Those calls are `Font.custom`, not `scaledValueForValue:`, so they stay fixed.
    static func doto(_ size: CGFloat) -> Font {
        .custom("Doto-BlackRound", size: size)
    }
}

/// Design size passed to `scaledValueForValue:`. At the default content size the
/// drawn size is this number. Dynamic Type changes it. Which string uses which
/// number was not identified, so the choice follows the screenshot.
struct DesignFont: ViewModifier {
    var weight: Font.Weight
    var design: Font.Design
    var digits: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16

    init(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, digits: Bool = false) {
        self.weight = weight
        self.design = design
        self.digits = digits
        self._size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        let base = Font.system(size: size, weight: weight, design: design)
        return content.font(digits ? base.monospacedDigit() : base)
    }
}

extension View {
    func designFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, digits: Bool = false) -> some View {
        modifier(DesignFont(size, weight: weight, design: design, digits: digits))
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Ink on light fills and white on dark ones, chosen from relative luminance
    /// so a label on a workplace colour always clears 4.5:1 where possible.
    static func readable(onHex hex: String) -> Color {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        func channel(_ shift: UInt64) -> Double {
            let c = Double((value >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        return luminance > 0.18 ? Theme.ink : Color.white
    }

    init(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(hex: UInt(value))
    }
}

enum Formatters {
    private static let yenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func yen(_ value: Int) -> String {
        let body = yenFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "¥" + body
    }

    static func hours(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let hour = safe / 60
        let minute = safe % 60
        if safe == 0 { return "0時間" }
        if hour == 0 { return "\(minute)分" }
        if minute == 0 { return "\(hour)時間" }
        return "\(hour)時間\(minute)分"
    }

    static func clock(_ minutes: Int) -> String {
        let parts = InOutRecovered.minuteOfDay(minutes)
        return String(format: "%d:%02d", parts.hour, parts.minute)
    }

    static func monthDayWeekday(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let names = ["", "日", "月", "火", "水", "木", "金", "土"]
        let symbol = names.indices.contains(weekday) ? names[weekday] : ""
        return "\(month)/\(day) (\(symbol))"
    }

    static func longDay(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let names = ["", "日", "月", "火", "水", "木", "金", "土"]
        let symbol = names.indices.contains(weekday) ? names[weekday] : ""
        return "\(month)月\(day)日 (\(symbol))"
    }

    static func monthTitle(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        return "\(month)月 \(year)"
    }

    static func percent(_ ratio: Double, decimals: Bool) -> String {
        guard ratio.isFinite else { return "0%" }
        let pct = ratio * 100
        if !decimals || abs(pct.rounded() - pct) < 0.05 {
            return "\(Int(pct.rounded()))%"
        }
        return String(format: "%.1f%%", pct)
    }
}
