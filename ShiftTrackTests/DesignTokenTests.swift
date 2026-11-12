import SwiftUI
import UIKit
import XCTest
@testable import ShiftTrack

/// The redesign's tokens and bundled assets. Replaces the old tests that pinned
/// layout numbers taken from another app.
final class DesignTokenTests: XCTestCase {
    func testDotoIsBundledRegisteredAndLicensed() {
        XCTAssertTrue(FontRegistry.ensureDoto())
        XCTAssertNotNil(UIFont(name: Font.dotoName, size: 20))
        let license = FontRegistry.dotoLicense() ?? ""
        XCTAssertTrue(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        XCTAssertTrue(license.contains("The Doto Project Authors"))
    }

    func testSpacingIsOnTheFourPointGrid() {
        let steps: [CGFloat] = [Space.xxs, Space.xs, Space.s, Space.m, Space.l, Space.xl, Space.xxl, Space.gutter, Space.section]
        for step in steps {
            XCTAssertEqual(step.truncatingRemainder(dividingBy: 4), 0, "\(step)")
        }
        XCTAssertEqual(steps.prefix(7).map { $0 }, [4, 8, 12, 16, 20, 24, 32])
        XCTAssertLessThan(Radius.control, Radius.card)
        XCTAssertLessThan(Radius.card, Radius.hero)
    }

    func testDotoStringsUseOnlyGlyphsTheFontHas() {
        // Doto covers Latin only. Strings the screens set in Doto must stay inside this set.
        let allowed = Set("0123456789:¥,.%/–+- ")
        let samples = [
            Formatters.clock(of: Date(timeIntervalSince1970: 0)),
            "\(Formatters.clock(9 * 60))–\(Formatters.clock(17 * 60 + 30))",
            "¥" + Formatters.yenDigits(1_234_567),
            Formatters.dotoMonth(Date(timeIntervalSince1970: 0)),
        ]
        for sample in samples {
            XCTAssertTrue(Set(sample).isSubset(of: allowed), sample)
        }
    }

    func testFormattersSpeakClocksAndDurations() {
        XCTAssertEqual(Formatters.spokenClock(9 * 60), "9時")
        XCTAssertEqual(Formatters.spokenClock(22 * 60 + 5), "22時5分")
        XCTAssertEqual(Formatters.remaining(59), "1分")
        XCTAssertEqual(Formatters.remaining(3_600), "1時間")
        XCTAssertEqual(Formatters.yenDigits(12_345), "12,345")
    }

    func testLandscapePhasesCoverTheWholeDay() {
        XCTAssertEqual(LandscapePalette.Phase(hour: 4), .night)
        XCTAssertEqual(LandscapePalette.Phase(hour: 5), .dawn)
        XCTAssertEqual(LandscapePalette.Phase(hour: 9), .day)
        XCTAssertEqual(LandscapePalette.Phase(hour: 16), .dusk)
        XCTAssertEqual(LandscapePalette.Phase(hour: 19), .night)
        XCTAssertTrue(LandscapePalette.palette(for: .night).isMoon)
        XCTAssertFalse(LandscapePalette.palette(for: .day).isMoon)
    }

    func testContactLinksNeedTheirData() {
        XCTAssertEqual(WorkplaceContact.phoneDigits("０３－１２３４－５６７８"), "0312345678")
        XCTAssertEqual(WorkplaceContact.phoneDigits("+81 90-0000-0000"), "+819000000000")
        XCTAssertNil(WorkplaceContact.telURL(""))
        XCTAssertEqual(WorkplaceContact.telURL("03-1234-5678")?.absoluteString, "tel:0312345678")
        XCTAssertNil(WorkplaceContact.mapURL(name: "架空茶房 北窓", address: "  ", latitude: 0, longitude: 0, hasCoordinate: false))
        let byAddress = WorkplaceContact.mapURL(name: "架空茶房 北窓", address: "架空県北窓町1-2", latitude: 0, longitude: 0, hasCoordinate: false)
        XCTAssertEqual(byAddress?.host, "maps.apple.com")
        XCTAssertTrue(byAddress?.absoluteString.contains("q=") ?? false)
        let byPin = WorkplaceContact.mapURL(name: "架空茶房 北窓", address: "", latitude: 35.5, longitude: 139.5, hasCoordinate: true)
        XCTAssertTrue(byPin?.absoluteString.contains("ll=35.500000,139.500000") ?? false)
        let sms = WorkplaceContact.smsURL("03-1234-5678", body: "遅れます & すみません")
        XCTAssertTrue(sms?.absoluteString.hasPrefix("sms:0312345678&body=") ?? false)
        XCTAssertFalse(sms?.absoluteString.contains(" & ") ?? true)

        let place = Workplace(name: "架空茶房 北窓", colorHex: "C6F24E", hourlyWage: 1_600, transportAllowance: 0)
        XCTAssertEqual(WorkplaceContact.mapReason(for: place), WorkplaceContact.missingAddress)
        XCTAssertEqual(WorkplaceContact.phoneReason(for: place), WorkplaceContact.missingPhone)
        place.place = "架空県北窓町1-2"
        place.phone = "03-0000-0000"
        XCTAssertNil(WorkplaceContact.mapReason(for: place))
        XCTAssertNil(WorkplaceContact.phoneReason(for: place))
    }

    func testDarkPairsClearTheContrastFloors() {
        func ratio(_ hex: UInt, _ other: UInt) -> Double {
            func lum(_ value: UInt) -> Double {
                func channel(_ shift: UInt) -> Double {
                    let c = Double((value >> shift) & 0xFF) / 255
                    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
                }
                return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
            }
            let hi = max(lum(hex), lum(other))
            let lo = min(lum(hex), lum(other))
            return (hi + 0.05) / (lo + 0.05)
        }
        let paper = ThemeDarkHex.background
        let surface = ThemeDarkHex.card
        XCTAssertGreaterThan(ratio(ThemeDarkHex.ink, paper), 4.5)
        XCTAssertGreaterThan(ratio(ThemeDarkHex.muted, paper), 4.5)
        XCTAssertGreaterThan(ratio(ThemeDarkHex.muted, surface), 4.5)
        XCTAssertGreaterThan(ratio(ThemeDarkHex.accentText, paper), 4.5)
        XCTAssertGreaterThan(ratio(ThemeDarkHex.danger, paper), 4.5)
        XCTAssertGreaterThan(ratio(ThemeDarkHex.stroke, surface), 3)
        XCTAssertGreaterThan(ratio(ThemeDarkHex.onInk, ThemeDarkHex.ink), 4.5)
        XCTAssertGreaterThan(ratio(ThemeHex.ink, ThemeDarkHex.lime), 4.5)
        XCTAssertGreaterThan(ratio(ThemeDarkHex.saturday, paper), 4.5)
    }

    func testMessageTemplatePreviewFillsEveryToken() {
        let preview = MessageTemplate.preview(LateMessageFill.polite)
        XCTAssertFalse(preview.contains("{"))
        XCTAssertTrue(preview.contains(MessageTemplate.sampleAddressee))
        XCTAssertTrue(preview.contains("15分ほど遅れます"))
    }
}
