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
