import SwiftUI

/// The raw values behind `Theme`, kept so the contrast tests read the same numbers.
/// See docs/design/redesign.md §3 for every pair and its ratio.
enum ThemeHex {
    /// Paper. Screen background.
    static let background: UInt = 0xF4F2EC
    /// White cards.
    static let card: UInt = 0xFFFFFF
    /// Sunken fields and off chips.
    static let cardRaised: UInt = 0xECE9E1
    /// Signal lime. A fill colour only; never text on a light surface.
    static let lime: UInt = 0xC8F04B
    static let ink: UInt = 0x161616
    /// Secondary text: 6.6:1 on paper, 6.1:1 on sunken. Also the unselected
    /// tab bar items before iOS 26.
    static let muted: UInt = 0x55555C
    /// Accent text, links, the switch “on” track and the selected tab bar
    /// item (the app tint): 7.0:1 on paper.
    static let accentText: UInt = 0x3D5A0A
    static let danger: UInt = 0xB3261E
    /// Control outlines (fields, secondary buttons): 3.5:1 on white, 3.2:1 on paper.
    static let stroke: UInt = 0x8C887E
    /// Decorative hairlines between rows.
    static let line: UInt = 0xE2DED5
}

enum Theme {
    // Semantic names used by the redesigned screens.
    static let paper = Color(hex: ThemeHex.background)
    static let surface = Color(hex: ThemeHex.card)
    static let sunken = Color(hex: ThemeHex.cardRaised)
    static let ink = Color(hex: ThemeHex.ink)
    static let ink2 = Color(hex: ThemeHex.muted)
    static let signal = Color(hex: ThemeHex.lime)
    static let signalInk = Color(hex: ThemeHex.accentText)
    static let stroke = Color(hex: ThemeHex.stroke)
    static let line = Color(hex: ThemeHex.line)
    static let danger = Color(hex: ThemeHex.danger)
    static let onDark = Color.white

    // Older names, kept so every screen reads the same tokens.
    static let background = paper
    static let card = surface
    static let cardRaised = sunken
    static let chip = surface
    static let dayFilled = ink
    static let lime = signal
    static let muted = ink2
    static let accentText = signalInk
    static let border = stroke
    static let track = sunken
    static let behind = danger
    static let destructive = danger

    /// Workplace colours. Stored as hex on each workplace, so existing values stay.
    static let palette = ["C6F24E", "111111", "F4A7A0", "B7D7C5", "F3C1D3", "A9C7F5", "C7B6E4", "F3D98A"]
}

extension Font {
    /// PostScript name of the bundled Doto instance (Google Fonts Doto, SIL OFL 1.1,
    /// instanced at wght 900 / ROND 100; `Fonts/OFL.txt`). Latin glyphs only:
    /// use it for `0-9 : ¥ , . % / – +` and spaces. Prefer `DotoText`, which
    /// caps Dynamic Type growth and gives VoiceOver a spoken label.
    static let dotoName = "Doto-BlackRound"

    static func doto(_ size: CGFloat) -> Font {
        .custom(dotoName, size: size, relativeTo: .largeTitle)
    }
}

/// Text styles of the redesign. They follow Dynamic Type.
enum AppFont {
    static let screenTitle = Font.title2.weight(.bold)
    static let sectionTitle = Font.headline
    static let rowTitle = Font.body.weight(.semibold)
    static let body = Font.body
    static let label = Font.subheadline.weight(.semibold)
    static let helper = Font.footnote
    static let badge = Font.caption.weight(.bold)
    static let value = Font.body.weight(.semibold).monospacedDigit()
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
        return "\(year)年\(month)月"
    }

    /// `2026.11`, for Doto (which has no kanji). Pair it with `monthTitle` for VoiceOver.
    static func dotoMonth(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        return String(format: "%d.%02d", year, month)
    }

    /// `14:05` from a date, for Doto.
    static func clock(of date: Date, calendar: Calendar = .current) -> String {
        String(format: "%d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    /// 「14時5分」, what VoiceOver should say for a clock.
    static func spokenClock(_ minutes: Int) -> String {
        let parts = InOutRecovered.minuteOfDay(minutes)
        return parts.minute == 0 ? "\(parts.hour)時" : "\(parts.hour)時\(parts.minute)分"
    }

    static func spokenClock(of date: Date, calendar: Calendar = .current) -> String {
        spokenClock(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
    }

    /// Yen without the sign, e.g. `12,345`.
    static func yenDigits(_ value: Int) -> String {
        let text = yen(value)
        return text.hasPrefix("¥") ? String(text.dropFirst()) : text
    }

    /// 「1時間20分」 from seconds, rounded up to the minute so a running shift never reads 0.
    static func remaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "0分" }
        return hours(Int((seconds / 60).rounded(.up)))
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
