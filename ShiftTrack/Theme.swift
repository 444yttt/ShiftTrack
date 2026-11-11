import SwiftUI

enum Theme {
    /// Paper, white cards, and black pills follow the reference screenshots.
    /// Stacking distances were not recovered from the binary.
    static let background = Color(hex: 0xF3F1EC)
    static let card = Color(hex: 0xFFFFFF)
    static let cardRaised = Color(hex: 0xE6E3DC)
    static let chip = Color(hex: 0xF7F6F2)
    static let dayFilled = Color(hex: 0x111111)
    static let tabBar = Color(hex: 0x1C1C1E)
    static let lime = Color(hex: 0xC6F24E)
    static let ink = Color(hex: 0x111111)
    static let onDark = Color.white
    static let muted = Color(hex: 0x8E8E93)
    static let line = Color(hex: 0xE4E1DA)
    static let border = Color(hex: 0xD5D2CB)
    static let track = Color(hex: 0xE6E3DC)
    static let behind = Color(hex: 0xFF6B9A)
    static let destructive = Color(hex: 0xFF5A5A)

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
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16

    init(_ size: CGFloat, weight: Font.Weight = .regular) {
        self.weight = weight
        self._size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func designFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(DesignFont(size, weight: weight))
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
