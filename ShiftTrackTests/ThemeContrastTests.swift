import XCTest
@testable import ShiftTrack

/// WCAG 2.x AA needs 4.5:1 for normal text. Every text/background pair the
/// screens use is listed here so a palette change cannot quietly break it.
final class ThemeContrastTests: XCTestCase {
    private func channel(_ value: UInt, shift: UInt) -> Double {
        let c = Double((value >> shift) & 0xFF) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ hex: UInt) -> Double {
        0.2126 * channel(hex, shift: 16) + 0.7152 * channel(hex, shift: 8) + 0.0722 * channel(hex, shift: 0)
    }

    private func ratio(_ a: UInt, _ b: UInt) -> Double {
        let high = max(luminance(a), luminance(b))
        let low = min(luminance(a), luminance(b))
        return (high + 0.05) / (low + 0.05)
    }

    func testTextPairsMeetAA() {
        let white: UInt = 0xFFFFFF
        let pairs: [(String, UInt, UInt)] = [
            ("ink on paper", ThemeHex.ink, ThemeHex.background),
            ("ink on card", ThemeHex.ink, ThemeHex.card),
            ("ink on raised", ThemeHex.ink, ThemeHex.cardRaised),
            ("ink on lime button", ThemeHex.ink, ThemeHex.lime),
            ("muted on paper", ThemeHex.muted, ThemeHex.background),
            ("muted on card", ThemeHex.muted, ThemeHex.card),
            ("muted on raised", ThemeHex.muted, ThemeHex.cardRaised),
            ("accent on paper", ThemeHex.accentText, ThemeHex.background),
            ("accent on card", ThemeHex.accentText, ThemeHex.card),
            ("accent on raised", ThemeHex.accentText, ThemeHex.cardRaised),
            // System tab bar items (before iOS 26) on the light bar material.
            ("selected tab item", ThemeHex.accentText, 0xF7F7F7),
            ("unselected tab item", ThemeHex.muted, 0xF7F7F7),
            ("error on paper", ThemeHex.danger, ThemeHex.background),
            ("error on card", ThemeHex.danger, ThemeHex.card),
            ("white on ink", white, ThemeHex.ink),
            ("lime on ink", ThemeHex.lime, ThemeHex.ink),
        ]
        for (name, foreground, background) in pairs {
            XCTAssertGreaterThanOrEqual(ratio(foreground, background), 4.5, name)
        }
    }

    func testReadableLabelOnWorkplaceColoursClearsAA() {
        for hex in Theme.palette {
            let value = UInt(hex, radix: 16) ?? 0
            let darkText = ratio(ThemeHex.ink, value)
            let lightText = ratio(0xFFFFFF, value)
            XCTAssertGreaterThanOrEqual(max(darkText, lightText), 4.5, hex)
        }
    }
}
