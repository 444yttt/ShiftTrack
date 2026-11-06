import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0B0B0B)
    static let card = Color(hex: 0x161616)
    static let cardRaised = Color(hex: 0x1C1C1C)
    static let chip = Color(hex: 0x2A2A2A)
    static let dayFilled = Color(hex: 0x1A1A1A)
    static let tabBar = Color(hex: 0x111111)
    static let lime = Color(hex: 0xC8FF00)
    static let ink = Color(hex: 0x0B0B0B)
    static let muted = Color(hex: 0x8A8A8A)
    static let line = Color(hex: 0x2A2A2A)
    static let border = Color(hex: 0x3A3A3A)
    static let track = Color(hex: 0x2A2A2A)
    static let behind = Color(hex: 0xFF6B9A)
    static let destructive = Color(hex: 0xFF5A5A)
    static let unselectedDot = Color(hex: 0x5A5A5A)

    static let palette = ["C8FF00", "5B8CFF", "FF6B9A", "FFB020", "C084FC", "FFFFFF"]
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
        let wrapped = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        return String(format: "%d:%02d", wrapped / 60, wrapped % 60)
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
