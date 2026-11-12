import Testing
@testable import ShiftTrack

struct LateMessageFillTests {
    @Test
    func replacesTheThreeTokens() {
        let text = LateMessageFill.apply(
            template: LateMessageFill.polite,
            addressee: "店長",
            reason: "電車の遅延のため",
            delay: "15分ほど遅れます"
        )
        #expect(text == "申し訳ありません。\n店長\n電車の遅延のため、15分ほど遅れます")
    }

    @Test
    func anEmptyNameDropsOnlyLinesThatStillNameTheAddressee() {
        let text = LateMessageFill.apply(
            template: "すみません。\n{宛名}へ\n{理由}",
            addressee: "  ",
            reason: "寝坊してしまい",
            delay: ""
        )
        #expect(text == "すみません。\n寝坊してしまい")
    }

    @Test
    func unknownBracesStay() {
        let text = LateMessageFill.apply(
            template: "{店名} {理由}",
            addressee: "店長",
            reason: "体調が悪くて",
            delay: "10分ほど遅れます"
        )
        #expect(text == "{店名} 体調が悪くて")
    }
}

struct PaydaySetupTests {
    @Test
    func onlyAWeekWithoutAWeekdayAsksForAPayday() {
        let place = Workplace(name: "架空茶房 北窓", colorHex: "C6F24E", hourlyWage: 1_600, transportAllowance: 0)
        #expect(PayWindows.needsPaydaySetup(place) == false)
        place.payCycle = .week
        #expect(PayWindows.needsPaydaySetup(place))
        place.payWeekday = 2
        #expect(PayWindows.needsPaydaySetup(place) == false)
    }
}
