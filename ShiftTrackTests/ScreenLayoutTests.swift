import XCTest
@testable import ShiftTrack

final class ScreenLayoutTests: XCTestCase {
    func testConfirmedInsetsStayOnTheirScreens() {
        XCTAssertEqual(ScreenInsets.root, 16)
        XCTAssertEqual(ScreenInsets.rootWide, 20)
        XCTAssertEqual(ScreenInsets.settingsInsets(includeOptional: true), [12, 8])
        XCTAssertEqual(ScreenInsets.settingsInsets(includeOptional: false), [12])
        XCTAssertEqual(ScreenInsets.shiftEditor, 4)
        XCTAssertEqual(ScreenInsets.todo, 12)
        XCTAssertEqual(ScreenInsets.aboutBubbleCorner, 16)
        XCTAssertTrue(SpacingTokens.root.contains(ScreenInsets.root))
        XCTAssertTrue(SpacingTokens.root.contains(ScreenInsets.rootWide))
        XCTAssertEqual(SpacingTokens.tabs, [4, 6, 9, 18])
        XCTAssertEqual(SpacingTokens.onboarding, [8, 12, 16, 20])
        XCTAssertEqual(SpacingTokens.list.prefix(21).map { Int($0) }, Array(4...24))
        XCTAssertEqual(SpacingTokens.list.suffix(3).map { Int($0) }, [-8, -6, -4])
        XCTAssertEqual(SpacingTokens.directory, [4, 8, 12, 16, 20, 24])
        XCTAssertEqual(SpacingTokens.locationPicker, [16])
        XCTAssertEqual(SpacingTokens.calendar, [2, 3, 5, 8, 12, 16, 20])
        XCTAssertEqual(SpacingTokens.day, [4, 8, 12, 20, 24])
        XCTAssertEqual(SpacingTokens.calendarPermission, [24])
        XCTAssertEqual(SpacingTokens.annualIncome, [8, 20, 24])
        XCTAssertEqual(SpacingTokens.incomeWalls, [10, 14])
        XCTAssertEqual(SpacingTokens.settings, [8, 12, 20, 24])
        XCTAssertTrue(SpacingTokens.settings.contains(ScreenInsets.settings))
        XCTAssertTrue(SpacingTokens.settings.contains(ScreenInsets.settingsOptional))
        XCTAssertEqual(SpacingTokens.guide, [20])
        XCTAssertEqual(SpacingTokens.patternEditor, [4])
        XCTAssertEqual(SpacingTokens.shiftRequest, [10])
        XCTAssertEqual(SpacingTokens.requestPlanner, [6, 8, 10, 12, 16])
        XCTAssertEqual(SpacingTokens.confirm, [8, 20])
        XCTAssertEqual(SpacingTokens.templateSheet, [10])
        XCTAssertEqual(SpacingTokens.shiftEditor, [ScreenInsets.shiftEditor])
        XCTAssertEqual(SpacingTokens.todo, [ScreenInsets.todo])
        XCTAssertEqual(SpacingTokens.hoursStockShared, [20, 8, 12])
        XCTAssertEqual(SpacingTokens.importShared, [20, 12])
    }

    func testLateMessageSectionsHideIndependently() {
        XCTAssertEqual(
            LateMessageLayout.sections().map(\.rawValue),
            [
                "① 遅れる理由",
                "② 遅れる時間",
                "③ 言葉づかい",
                "文章はここで直せます。①〜③の答えを変えると作り直します。",
            ]
        )
        XCTAssertEqual(
            LateMessageLayout.sections(hidden: [.delay]),
            [.reason, .tone, .note]
        )
        XCTAssertEqual(
            LateMessageLayout.sections(hidden: [.reason, .note]),
            [.delay, .tone]
        )
        XCTAssertEqual(
            LateMessageLayout.sections(hidden: [.tone]),
            [.reason, .delay, .note]
        )
    }

    func testImportSectionsStayInOrderAndHideIndependently() {
        XCTAssertEqual(ImportSectionLayout.sections(), [.mapNote, .readText])
        XCTAssertEqual(ImportSection.mapNote.rawValue, "住所を Apple のマップサービスに送ります。位置の検索以外には使いません。")
        XCTAssertEqual(ImportSection.readText.rawValue, "読み取った文字")
        XCTAssertEqual(ImportSectionLayout.sections(hidden: [.mapNote]), [.readText])
        XCTAssertEqual(ImportSectionLayout.sections(hidden: [.readText]), [.mapNote])
    }

    func testAboutBubbleUsesTheSentenceReadAfterTheTitle() {
        XCTAssertTrue(AboutBubble.body.hasPrefix("シフトはカレンダーアプリに、やることはリマインダーに保存します。"))
        XCTAssertTrue(AboutBubble.body.hasSuffix("金額はすべて概算です。"))
        XCTAssertFalse(AboutBubble.body.contains("IN/OUT について"))
    }
}
