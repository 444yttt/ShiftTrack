import XCTest
@testable import ShiftTrack

final class WorkplaceDraftTests: XCTestCase {
    func testNoisyCardDropsChromeAndKeepsTheShop() {
        let raw = """
        22:05
        90
        キャンセル
        読み取り結果
        反映
        名前
        あります。架空茶房の場所はこちら
        店舗情報
        架空県架空
        市窓辺1-2-3
        や、現在の情報について詳しく知りたい場合
        質問する
        反映する内容
        架空茶房 北窓
        候補を選ぶか、入力して直してください。空欄の項目は反映しません。
        電話番号
        099-000-
        0000
        住所
        架空県架空
        市窓辺1-2-3
        営業時間:10:00~18:00
        公式サイト:https://example.invalid/kitamado
        """
        let draft = WorkplaceRead.draft(from: raw)
        XCTAssertEqual(draft.name, "架空茶房 北窓")
        XCTAssertEqual(draft.phone, "099-000-0000")
        XCTAssertEqual(draft.address, "架空県架空市窓辺1-2-3")
        XCTAssertEqual(draft.hours, "10:00–18:00")
        XCTAssertEqual(draft.officialURL, "https://example.invalid/kitamado")
        XCTAssertFalse(draft.nameChoices.contains(where: { $0.contains("あります") }))
        XCTAssertFalse(draft.nameChoices.contains("店舗情報"))
        XCTAssertFalse(draft.nameChoices.contains("質問する"))
        XCTAssertFalse(draft.addressChoices.contains("架空県架空"))
        XCTAssertFalse(draft.hoursChoices.contains("22:05"))
        XCTAssertFalse(draft.nameChoices.contains(where: { $0.contains("知りたい") || $0.contains("候補") }))
    }

    func testBestCandidateIsFirstAndFragmentsStayOut() {
        let draft = WorkplaceRead.draft(from: """
        店名:架空茶房 北窓
        架空茶房
        電話:099-000-0000
        住所:架空県架空市窓辺1-2-3
        """)
        XCTAssertEqual(draft.nameChoices.first, "架空茶房 北窓")
        XCTAssertFalse(draft.nameChoices.contains("架空茶房"))
        XCTAssertEqual(draft.phoneChoices.first, "099-000-0000")
        XCTAssertEqual(draft.addressChoices.first, "架空県架空市窓辺1-2-3")
    }

    func testMapsPlaceLinkFillsTheSameDraft() {
        let draft = WorkplaceRead.draft(fromMapsLink: "https://www.google.com/maps/place/%E6%9E%B6%E7%A9%BA%E8%8C%B6%E6%88%BF+%E5%8C%97%E7%AA%93/@35.0,139.0,17z")
        XCTAssertEqual(draft.name, "架空茶房 北窓")
        XCTAssertTrue(draft.mapsNotice.isEmpty)
    }

    func testMapsQueryCanCarryTheAddress() {
        let encoded = "https://maps.google.com/?q=" + "架空茶房 北窓 架空県架空市窓辺1-2-3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let draft = WorkplaceRead.draft(fromMapsLink: encoded)
        XCTAssertEqual(draft.name, "架空茶房 北窓")
        XCTAssertEqual(draft.address, "架空県架空市窓辺1-2-3")
    }

    func testMonthForecastSumsOnlyThatMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11))!
        let inside = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let outside = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30))!
        let yen = MonthForecastMath.yen(
            days: [(inside, 1200), (outside, 9000), (now, 300)],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(yen, 1500)
    }

    func testShortMapsLinkStaysEditable() {
        let draft = WorkplaceRead.draft(fromMapsLink: "https://maps.app.goo.gl/kitamado")
        XCTAssertEqual(draft.mapsNotice, WorkplaceDraft.mapsUnreadable)
        XCTAssertTrue(draft.name.isEmpty)
        XCTAssertTrue(draft.address.isEmpty)
    }
}
