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
        東京都架空
        区窓辺1-2-3
        営業時間:10:00~18:00
        公式サイト:https://example.invalid/kitamado
        """
        let draft = WorkplaceRead.draft(from: raw)
        XCTAssertEqual(draft.name, "架空茶房 北窓")
        XCTAssertEqual(draft.phone, "099-000-0000")
        XCTAssertEqual(draft.address, "東京都架空区窓辺1-2-3")
        XCTAssertEqual(draft.hours, "10:00~18:00")
        XCTAssertEqual(draft.officialURL, "https://example.invalid/kitamado")
        XCTAssertEqual(draft.nameNote.confidence, .high)
        XCTAssertFalse(draft.nameChoices.contains(where: { $0.contains("あります") }))
        XCTAssertFalse(draft.nameChoices.contains("店舗情報"))
        XCTAssertFalse(draft.addressChoices.contains("東京都架空"))
        XCTAssertFalse(draft.hoursChoices.contains("22:05"))
        XCTAssertTrue(draft.locateFromAddress)
    }

    func testStatusBarDropsOnlyMatchingLinesInTheTopBand() {
        let lines = [
            ReadLine(id: 1, text: "9:41", x: 0.4, y: 0.01, width: 0.12, height: 0.02),
            ReadLine(id: 2, text: "架空茶房 北窓", x: 0.08, y: 0.02, width: 0.4, height: 0.03),
            ReadLine(id: 3, text: "84%", x: 0.8, y: 0.01, width: 0.08, height: 0.02)
        ]
        let draft = WorkplaceRead.draft(from: lines)
        XCTAssertEqual(draft.name, "架空茶房 北窓")
        XCTAssertFalse(draft.nameChoices.contains("9:41"))
        XCTAssertFalse(draft.nameChoices.contains("84%"))
    }

    func testAClockOutsideTheTopBandIsNotErasedAsChrome() {
        let lines = [
            ReadLine(id: 1, text: "架空茶房 北窓", y: 0.4, width: 0.4, height: 0.04),
            ReadLine(id: 2, text: "9:41", x: 0.1, y: 0.5, width: 0.1, height: 0.03)
        ]
        let draft = WorkplaceRead.draft(from: lines)
        XCTAssertEqual(draft.name, "架空茶房 北窓")
    }

    func testLongVowelStaysAndHyphensBetweenDigitsChange() {
        let draft = WorkplaceRead.draft(from: """
        コーヒー北窓
        電話
        03－1234－5678
        """)
        XCTAssertEqual(draft.name, "コーヒー北窓")
        XCTAssertEqual(draft.phone, "03-1234-5678")
    }

    func testFaxAndStationWalkAreLeftOut() {
        let draft = WorkplaceRead.draft(from: """
        架空茶房 北窓
        FAX
        03-0000-0000
        電話
        090-0000-0000
        住所
        東京都架空区窓辺1-2-3 北窓駅から徒歩5分
        """)
        XCTAssertEqual(draft.phone, "090-0000-0000")
        XCTAssertFalse(draft.phoneChoices.contains("03-0000-0000"))
        XCTAssertEqual(draft.address, "東京都架空区窓辺1-2-3")
        XCTAssertFalse(draft.address.contains("徒歩"))
    }

    func testTruncatedAddressJoinsWithoutASpace() {
        let draft = WorkplaceRead.draft(from: """
        千葉県木更
        津市架空1-2-3
        """)
        XCTAssertEqual(draft.address, "千葉県木更津市架空1-2-3")
    }

    func testAnAddressWithoutAMunicipalityIsDropped() {
        let draft = WorkplaceRead.draft(from: "千葉県木更")
        XCTAssertTrue(draft.address.isEmpty)
        XCTAssertEqual(draft.addressNote.confidence, .missing)
    }

    func testOpenAndClosedLabelsAreNotHours() {
        let draft = WorkplaceRead.draft(from: """
        架空茶房 北窓
        営業中
        営業終了
        営業時間:10:00~翌2:00
        10:00~26:00
        """)
        XCTAssertEqual(draft.hoursChoices, ["10:00~翌2:00"])
    }

    func testListingAndSocialLinksAreNotTheOfficialSite() {
        XCTAssertEqual(WorkplaceRead.urlClass("https://tabelog.com/example"), .listing)
        XCTAssertEqual(WorkplaceRead.urlClass("https://instagram.com/example"), .social)
        XCTAssertEqual(WorkplaceRead.urlClass("https://maps.google.com/?q=1,2"), .map)
        let draft = WorkplaceRead.draft(from: """
        架空茶房 北窓
        https://tabelog.com/example
        https://example.invalid/kitamado
        """)
        XCTAssertEqual(draft.officialURL, "https://example.invalid/kitamado")
        XCTAssertFalse(draft.urlChoices.contains("https://tabelog.com/example"))
    }

    func testInternationalPhoneBecomesADomesticNumber() {
        let draft = WorkplaceRead.draft(from: "電話:+81 90-1234-5678")
        XCTAssertEqual(draft.phone, "090-1234-5678")
    }

    func testModelAgreementIsHighAndALoneSideIsReview() {
        let lines = [
            ReadLine(id: 1, text: "架空茶房 北窓"),
            ReadLine(id: 2, text: "ここはお店です。")
        ]
        let agreed = WorkplaceRead.merge(WorkplaceRead.draft(from: lines), pick: LinePick(nameIDs: [1]), modelRan: true)
        XCTAssertEqual(agreed.name, "架空茶房 北窓")
        XCTAssertEqual(agreed.nameNote.confidence, .high)
        XCTAssertEqual(agreed.nameNote.origin, .image)
        let onlyModel = WorkplaceRead.merge(WorkplaceRead.draft(from: lines), pick: LinePick(nameIDs: [2]), modelRan: true)
        XCTAssertEqual(onlyModel.nameNote.confidence, .review)
    }

    func testMapsPlaceLinkKeepsTheNameAndNotGooglesAddress() {
        let url = URL(string: "https://www.google.com/maps/place/%E6%9E%B6%E7%A9%BA%E8%8C%B6%E6%88%BF+%E5%8C%97%E7%AA%93/@35.0,139.0,17z")!
        let pin = WorkplaceRead.pin(from: url)
        XCTAssertEqual(pin.name, "架空茶房 北窓")
        XCTAssertEqual(pin.latitude ?? 0, 35, accuracy: 0.001)
        XCTAssertEqual(pin.longitude ?? 0, 139, accuracy: 0.001)
        let draft = WorkplaceRead.draft(fromMapsLink: url.absoluteString)
        XCTAssertEqual(draft.name, "架空茶房 北窓")
        XCTAssertTrue(draft.address.isEmpty)
        XCTAssertTrue(draft.officialURL.isEmpty)
        XCTAssertTrue(draft.mapsNotice.isEmpty)
    }

    func testMapsQueryDropsTheAddressCarriedInTheLink() {
        let encoded = "https://maps.google.com/?q=" + "架空茶房 北窓 東京都架空区窓辺1-2-3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let draft = WorkplaceRead.draft(fromMapsLink: encoded)
        XCTAssertEqual(draft.name, "架空茶房 北窓")
        XCTAssertTrue(draft.address.isEmpty)
    }

    func testShortMapsLinkStaysEditable() {
        let draft = WorkplaceRead.draft(fromMapsLink: "https://maps.app.goo.gl/kitamado")
        XCTAssertEqual(draft.mapsNotice, WorkplaceDraft.mapsUnreadable)
        XCTAssertTrue(draft.name.isEmpty)
        XCTAssertTrue(draft.address.isEmpty)
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
}
