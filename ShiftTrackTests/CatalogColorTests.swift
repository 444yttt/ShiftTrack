import UIKit
import XCTest
@testable import ShiftTrack

final class CatalogColorTests: XCTestCase {
    private var bundle: Bundle {
        Bundle(identifier: "app.shifttrack.ios") ?? .main
    }

    func testAccentIsBlackAndWhiteAndLaunchHasNoDarkVariant() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let accentLight = UIColor(named: "AccentColor", in: bundle, compatibleWith: light)
        let accentDark = UIColor(named: "AccentColor", in: bundle, compatibleWith: dark)
        let launchLight = UIColor(named: "LaunchBackground", in: bundle, compatibleWith: light)
        let launchDark = UIColor(named: "LaunchBackground", in: bundle, compatibleWith: dark)
        XCTAssertEqual(bytes(accentLight, light), [0, 0, 0, 255])
        XCTAssertEqual(bytes(accentDark, dark), [255, 255, 255, 255])
        XCTAssertEqual(bytes(launchLight, light), [195, 255, 119, 255])
        XCTAssertEqual(bytes(launchDark, dark), [195, 255, 119, 255])
    }

    func testDotoBlackRoundIsTheOfficialFace() {
        let font = UIFont(name: "Doto-BlackRound", size: 36)
        XCTAssertNotNil(font)
        XCTAssertEqual(font?.fontName, "Doto-BlackRound")
        XCTAssertEqual(font?.pointSize, 36)
    }

    private func bytes(_ color: UIColor?, _ trait: UITraitCollection) -> [Int] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let resolved = color?.resolvedColor(with: trait)
        XCTAssertNotNil(resolved)
        resolved?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha].map { Int(($0 * 255).rounded()) }
    }
}
