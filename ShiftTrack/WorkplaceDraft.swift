import Foundation

/// One OCR line. `x` and `y` are the top-left of a normalized box. A zero size means the line has no box.
struct ReadLine: Equatable, Codable, Identifiable {
    var id: Int
    var text: String
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
    var detected: Bool = false

    var hasBox: Bool { width > 0 && height > 0 }
}

enum ReadConfidence: String, Equatable, Codable {
    case high
    case review
    case missing
}

enum ReadOrigin: String, Equatable, Codable {
    case image
    case intelligence
    case map

    var footnote: String {
        switch self {
        case .image: return "画像から"
        case .intelligence: return "AIが判断"
        case .map: return "地図データから"
        }
    }
}

struct FieldNote: Equatable, Codable {
    var choices: [String] = []
    var lineIDs: [Int] = []
    var confidence: ReadConfidence = .missing
    var origin: ReadOrigin? = nil
    var edited: Bool = false
}

struct DetectedHints: Equatable {
    var phones: [String] = []
    var addresses: [String] = []
    var urls: [String] = []
}

struct LinePick: Equatable {
    var nameIDs: [Int] = []
    var phoneIDs: [Int] = []
    var addressIDs: [Int] = []
    var hoursIDs: [Int] = []
    var urlIDs: [Int] = []
}

struct MapsPin: Equatable {
    var name = ""
    var latitude: Double?
    var longitude: Double?
}

/// A workplace read from a shop card or a maps link, before it is saved.
struct WorkplaceDraft: Equatable, Codable {
    var name = ""
    var phone = ""
    var address = ""
    var hours = ""
    var officialURL = ""
    var nameNote = FieldNote()
    var phoneNote = FieldNote()
    var addressNote = FieldNote()
    var hoursNote = FieldNote()
    var urlNote = FieldNote()
    var lines: [ReadLine] = []
    var imageJPEG: Data?
    var locateFromAddress = false
    var mapsNotice = ""
    var latitude = 0.0
    var longitude = 0.0
    var hasCoordinate = false
    var locatedName = ""

    var nameChoices: [String] { nameNote.choices }
    var phoneChoices: [String] { phoneNote.choices }
    var addressChoices: [String] { addressNote.choices }
    var hoursChoices: [String] { hoursNote.choices }
    var urlChoices: [String] { urlNote.choices }
    var transcript: String { lines.map(\.text).joined(separator: "\n") }

    static let mapsUnreadable = "Google マップのリンクから店舗の情報を読めませんでした。店名や住所を直接入力してください。"
    static let imageUnreadable = "画像から文字を見つけられませんでした。店名や住所を直接入力してください。"

    enum CodingKeys: String, CodingKey {
        case name, phone, address, hours, officialURL
        case nameNote, phoneNote, addressNote, hoursNote, urlNote
        case lines, imageJPEG, locateFromAddress, mapsNotice
        case latitude, longitude, hasCoordinate, locatedName
    }

    var namesDiffer: Bool {
        let shop = WorkplaceRead.compact(name)
        let found = WorkplaceRead.compact(locatedName)
        guard !shop.isEmpty, !found.isEmpty else { return false }
        return !shop.contains(found) && !found.contains(shop)
    }
}

enum WorkplaceRead {
    static let prefectures = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
        "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
        "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
        "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
        "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
        "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
        "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県"
    ]

    static func draft(from raw: String) -> WorkplaceDraft {
        let rows = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let lines = rows.enumerated().map { ReadLine(id: $0.offset, text: String($0.element)) }
        return draft(from: lines)
    }

    static func draft(from lines: [ReadLine], detected: DetectedHints = DetectedHints()) -> WorkplaceDraft {
        let prepared = prepare(lines)
        var names: [Candidate] = []
        var phones: [Candidate] = []
        var addresses: [Candidate] = []
        var hours: [Candidate] = []
        var urls: [Candidate] = []
        collect(prepared, into: &names, phones: &phones, addresses: &addresses, hours: &hours, urls: &urls)
        absorbDetector(prepared.map(\.text).joined(separator: "\n"), phones: &phones, addresses: &addresses, urls: &urls)
        for phone in detected.phones {
            if let value = validPhone(phone) {
                phones.append(Candidate(value: value, lineIDs: [], fromProse: false))
            }
        }
        for address in detected.addresses {
            if let value = validAddress(address) {
                addresses.append(Candidate(value: value, lineIDs: [], fromProse: false))
            }
        }
        for url in detected.urls where urlClass(url) == .official {
            urls.append(Candidate(value: cleanURL(url), lineIDs: [], fromProse: false))
        }
        names = rank(names.filter { isShopName($0.value) })
        phones = rank(phones)
        addresses = rank(addresses.filter { validAddress($0.value) != nil })
        hours = rank(hours)
        urls = rank(urls.filter { urlClass($0.value) == .official })
        var draft = WorkplaceDraft()
        draft.lines = lines
        draft.nameNote = note(names)
        draft.phoneNote = note(phones)
        draft.addressNote = note(addresses)
        draft.hoursNote = note(hours)
        draft.urlNote = note(urls)
        draft.name = draft.nameNote.choices.first ?? ""
        draft.phone = draft.phoneNote.choices.first ?? ""
        draft.address = draft.addressNote.choices.first ?? ""
        draft.hours = draft.hoursNote.choices.first ?? ""
        draft.officialURL = draft.urlNote.choices.first ?? ""
        draft.locateFromAddress = draft.addressNote.confidence == .high && !draft.address.isEmpty
        return draft
    }

    /// The model may only choose line ids. A value both sides accept is high.
    /// A value only one side accepts is review. Invented strings are dropped.
    static func merge(_ draft: WorkplaceDraft, pick: LinePick, modelRan: Bool) -> WorkplaceDraft {
        guard modelRan else { return draft }
        var copy = draft
        copy.nameNote = mergeField(draft.nameNote, ids: pick.nameIDs, lines: draft.lines) { isShopName($0) ? $0 : nil }
        copy.phoneNote = mergeField(draft.phoneNote, ids: pick.phoneIDs, lines: draft.lines, accept: validPhone)
        copy.addressNote = mergeField(draft.addressNote, ids: pick.addressIDs, lines: draft.lines, accept: validAddress)
        copy.hoursNote = mergeField(draft.hoursNote, ids: pick.hoursIDs, lines: draft.lines) { hourValue($0) }
        copy.urlNote = mergeField(draft.urlNote, ids: pick.urlIDs, lines: draft.lines) { urlClass($0) == .official ? cleanURL($0) : nil }
        copy.name = copy.nameNote.choices.first ?? ""
        copy.phone = copy.phoneNote.choices.first ?? ""
        copy.address = copy.addressNote.choices.first ?? ""
        copy.hours = copy.hoursNote.choices.first ?? ""
        copy.officialURL = copy.urlNote.choices.first ?? ""
        if copy.address.isEmpty { copy.locateFromAddress = false }
        else if !copy.addressNote.edited { copy.locateFromAddress = copy.addressNote.confidence == .high }
        return copy
    }

    static func pin(from url: URL) -> MapsPin {
        var pin = MapsPin()
        pin.name = placeName(url)
        if let coordinate = coordinate(url) {
            pin.latitude = coordinate.0
            pin.longitude = coordinate.1
        }
        return pin
    }

    static func draft(fromMapsLink raw: String) -> WorkplaceDraft {
        let trimmed = trim(raw)
        guard let url = firstURL(in: trimmed), isMapsHost(url) else {
            var draft = WorkplaceDraft()
            draft.mapsNotice = WorkplaceDraft.mapsUnreadable
            return draft
        }
        let pin = pin(from: url)
        var draft = WorkplaceDraft()
        if pin.name.isEmpty, pin.latitude == nil {
            draft.mapsNotice = WorkplaceDraft.mapsUnreadable
            return draft
        }
        draft.name = pin.name
        if !pin.name.isEmpty {
            draft.nameNote = FieldNote(choices: [pin.name], confidence: .review, origin: nil)
        }
        return draft
    }

    static func isShortMapLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host == "maps.app.goo.gl" || host == "goo.gl" || host.hasSuffix(".app.goo.gl")
    }

    enum URLClass: Equatable {
        case official, map, listing, social, other
    }

    static func urlClass(_ raw: String) -> URLClass {
        let cleaned = cleanURL(raw)
        guard let url = URL(string: cleaned), let host = url.host?.lowercased() else { return .other }
        guard url.scheme == "http" || url.scheme == "https" else { return .other }
        if host.contains("google.") || host.contains("goo.gl") || host == "maps.app" || host.hasSuffix(".app.goo.gl") || host.contains("maps.apple") {
            return .map
        }
        let listings = ["tabelog.com", "hotpepper.jp", "gnavi.co.jp", "retty.me", "yelp.com", "tripadvisor."]
        if listings.contains(where: { host.contains($0) }) { return .listing }
        let social = ["instagram.com", "twitter.com", "x.com", "facebook.com", "fb.com", "line.me", "tiktok.com"]
        if social.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .social }
        return .official
    }

    static func compact(_ text: String) -> String {
        trim(text).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    }

    // MARK: - Lines

    private struct Candidate: Equatable {
        var value: String
        var lineIDs: [Int]
        var fromProse: Bool
    }

    private static let labels: [(String, Slot)] = [
        ("公式サイト", .url), ("公式URL", .url), ("ホームページ", .url), ("ウェブサイト", .url),
        ("営業時間", .hours), ("店舗名", .name), ("電話番号", .phone), ("ファックス", .fax),
        ("所在地", .address), ("店名", .name), ("名前", .name), ("住所", .address),
        ("FAX", .fax), ("TEL", .phone), ("電話", .phone), ("URL", .url)
    ]

    private static let chrome: Set<String> = [
        "キャンセル", "反映", "質問する", "閉じる", "検索", "戻る", "店舗情報",
        "読み取り結果", "読み取った文字", "位置", "営業", "マップで探す",
        "写真から読み取る", "撮影する", "写真から選ぶ", "ショップカード",
        "反映する内容", "営業中", "営業終了", "営業時間外"
    ]

    private enum Slot {
        case name, phone, address, hours, url, fax
    }

    private static func prepare(_ lines: [ReadLine]) -> [ReadLine] {
        var rows = lines.map { line -> ReadLine in
            var copy = line
            copy.text = normalize(line.text)
            return copy
        }
        rows = rows.filter { !isStatusBar($0) && !trim($0.text).isEmpty }
        rows = rows.filter { line in
            let text = trim(line.text)
            if labelSlot(text) != nil { return true }
            return !chrome.contains(text)
        }
        return withoutFax(joined(rows))
    }

    private static func withoutFax(_ lines: [ReadLine]) -> [ReadLine] {
        var drop = Set<Int>()
        for (index, line) in lines.enumerated() {
            guard let slot = labelSlot(line.text), slot.slot == .fax else { continue }
            drop.insert(line.id)
            if slot.value == nil, index + 1 < lines.count {
                drop.insert(lines[index + 1].id)
            }
        }
        return lines.filter { line in
            if drop.contains(line.id) { return false }
            let text = line.text
            return !text.localizedCaseInsensitiveContains("fax") && !text.contains("ファックス")
        }
    }

    private static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping
        var scalars: [Character] = []
        let characters = Array(folded)
        for (index, character) in characters.enumerated() {
            let previousDigit = index > 0 && characters[index - 1].isNumber
            let nextDigit = index + 1 < characters.count && characters[index + 1].isNumber
            if previousDigit && nextDigit && isHyphen(character) {
                scalars.append("-")
            } else {
                scalars.append(character)
            }
        }
        return trim(String(scalars))
    }

    private static func isHyphen(_ character: Character) -> Bool {
        "‐-‒–—―−－".contains(character)
    }

    private static func isStatusBar(_ line: ReadLine) -> Bool {
        guard line.hasBox, line.y < 0.07 else { return false }
        let text = trim(line.text)
        if text.range(of: #"^\d{1,2}[:：]\d{2}$"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"^\d{1,3}\s*%$"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"(?i)^(5G|4G|LTE|Wi-?Fi)$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func joined(_ lines: [ReadLine]) -> [ReadLine] {
        var result: [ReadLine] = []
        var index = 0
        while index < lines.count {
            var current = lines[index]
            var used = 1
            while used < 3, index + 1 < lines.count {
                let next = lines[index + 1]
                if shouldJoinPhone(current, next) || shouldJoinAddress(current, next) {
                    current.text += next.text
                    current.width = max(current.width, next.width)
                    index += 1
                    used += 1
                } else {
                    break
                }
            }
            result.append(current)
            index += 1
        }
        return result
    }

    private static func shouldJoinPhone(_ current: ReadLine, _ next: ReadLine) -> Bool {
        let digits = current.text.filter(\.isNumber)
        guard (2..<10).contains(digits.count), current.text.hasPrefix("0") || current.text.hasPrefix("+") else { return false }
        guard current.text.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " || $0 == "(" || $0 == ")" }) else { return false }
        let more = next.text.filter(\.isNumber)
        guard !more.isEmpty, next.text.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) else { return false }
        return digits.count + more.count <= 11
    }

    private static func shouldJoinAddress(_ current: ReadLine, _ next: ReadLine) -> Bool {
        guard prefecture(in: current.text) != nil || current.text.hasPrefix("〒") else { return false }
        guard validAddress(current.text) == nil else { return false }
        if labelSlot(next.text) != nil { return false }
        if isProse(next.text) { return false }
        if next.text.contains("駅から徒歩") { return false }
        if let box = near(current, next), box == false { return false }
        return true
    }

    /// Nil when either line has no box. Otherwise whether the next line sits close, on a similar left edge.
    private static func near(_ current: ReadLine, _ next: ReadLine) -> Bool? {
        guard current.hasBox, next.hasBox else { return nil }
        let gap = next.y - (current.y + current.height)
        let left = abs(current.x - next.x)
        return gap < max(current.height, 0.04) * 1.6 && left < 0.08
    }

    private static func collect(
        _ lines: [ReadLine],
        into names: inout [Candidate],
        phones: inout [Candidate],
        addresses: inout [Candidate],
        hours: inout [Candidate],
        urls: inout [Candidate]
    ) {
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let slot = labelSlot(line.text) {
                let partner = partnerLine(of: index, in: lines)
                let value = slot.value ?? partner?.text ?? ""
                let ids = [line.id] + (partner.map { [$0.id] } ?? [])
                absorb(value, ids: ids, slot: slot.slot, prose: false, names: &names, phones: &phones, addresses: &addresses, hours: &hours, urls: &urls)
                if let partner, slot.value == nil, index + 1 < lines.count, partner.id == lines[index + 1].id {
                    index += 1
                }
                index += 1
                continue
            }
            absorb(line.text, ids: [line.id], slot: nil, prose: isProse(line.text), names: &names, phones: &phones, addresses: &addresses, hours: &hours, urls: &urls)
            index += 1
        }
    }

    private static func partnerLine(of index: Int, in lines: [ReadLine]) -> ReadLine? {
        let line = lines[index]
        if line.hasBox {
            let right = lines.enumerated().filter { offset, other in
                offset != index && other.hasBox && abs(other.y - line.y) < 0.02 && other.x > line.x + 0.02
            }.min { $0.element.x < $1.element.x }
            if let right { return right.element }
        }
        if index + 1 < lines.count { return lines[index + 1] }
        return nil
    }

    private static func absorb(
        _ raw: String,
        ids: [Int],
        slot: Slot?,
        prose: Bool,
        names: inout [Candidate],
        phones: inout [Candidate],
        addresses: inout [Candidate],
        hours: inout [Candidate],
        urls: inout [Candidate]
    ) {
        let text = trim(raw)
        guard !text.isEmpty else { return }
        if slot == .fax || text.localizedCaseInsensitiveContains("fax") || text.contains("ファックス") {
            if slot == .fax || slot == .phone { return }
        }
        if slot == nil, prose {
            if let phone = validPhone(text) { phones.append(Candidate(value: phone, lineIDs: ids, fromProse: true)) }
            if let address = validAddress(text) { addresses.append(Candidate(value: address, lineIDs: ids, fromProse: true)) }
            if let hour = hourValue(text) { hours.append(Candidate(value: hour, lineIDs: ids, fromProse: true)) }
            return
        }
        switch slot {
        case .name:
            if isShopName(text) { names.append(Candidate(value: text, lineIDs: ids, fromProse: false)) }
        case .phone:
            if let phone = validPhone(text) { phones.append(Candidate(value: phone, lineIDs: ids, fromProse: false)) }
        case .address:
            if let address = validAddress(text) { addresses.append(Candidate(value: address, lineIDs: ids, fromProse: false)) }
        case .hours:
            if let hour = hourValue(text) { hours.append(Candidate(value: hour, lineIDs: ids, fromProse: false)) }
        case .url:
            if urlClass(text) == .official { urls.append(Candidate(value: cleanURL(text), lineIDs: ids, fromProse: false)) }
        case .fax, nil:
            if let phone = validPhone(text), !text.localizedCaseInsensitiveContains("fax") {
                phones.append(Candidate(value: phone, lineIDs: ids, fromProse: prose))
            }
            if let address = validAddress(text) { addresses.append(Candidate(value: address, lineIDs: ids, fromProse: prose)) }
            if let hour = hourValue(text) { hours.append(Candidate(value: hour, lineIDs: ids, fromProse: prose)) }
            if urlClass(text) == .official { urls.append(Candidate(value: cleanURL(text), lineIDs: ids, fromProse: prose)) }
            if slot == nil, isShopName(text) { names.append(Candidate(value: text, lineIDs: ids, fromProse: false)) }
        }
    }

    private static func labelSlot(_ line: String) -> (slot: Slot, value: String?)? {
        for (label, slot) in labels {
            if line.caseInsensitiveCompare(label) == .orderedSame { return (slot, nil) }
            if line.lowercased().hasPrefix(label.lowercased()) {
                let rest = trim(String(line.dropFirst(label.count)).trimmingCharacters(in: CharacterSet(charactersIn: ":：・ ")))
                if rest.isEmpty { return (slot, nil) }
                return (slot, rest)
            }
        }
        return nil
    }

    private static func isProse(_ text: String) -> Bool {
        if text.contains("。") { return true }
        if text.contains("です") || text.contains("ます") || text.contains("にあります") { return true }
        return text.count > 40
    }

    private static func isShopName(_ line: String) -> Bool {
        let text = trim(line)
        guard text.count >= 2, text.count <= 32 else { return false }
        if chrome.contains(text) { return false }
        if labels.contains(where: { text.caseInsensitiveCompare($0.0) == .orderedSame }) { return false }
        if "都道府県市区町村郡〒".contains(where: { text.contains($0) }) { return false }
        if isProse(text) || validAddress(text) != nil || validPhone(text) != nil { return false }
        if hourValue(text) != nil, text.count < 18 { return false }
        if urlClass(text) == .official || urlClass(text) == .map { return false }
        if text.hasPrefix("や、") || text.hasPrefix("や→") || text.hasPrefix("●") || text.hasPrefix("→") { return false }
        let banned = ["について", "詳しく", "質問", "候補", "反映", "選ぶ", "入力", "空欄", "知りたい", "店舗情報"]
        if banned.contains(where: { text.contains($0) }) { return false }
        return text.contains(where: { $0.isLetter })
    }

    static func validPhone(_ text: String) -> String? {
        if text.localizedCaseInsensitiveContains("fax") || text.contains("ファックス") { return nil }
        if text.range(of: #"\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil { return nil }
        if text.contains("〒") { return nil }
        if text.range(of: #"\d{4}[./年\-]\d{1,2}[./月\-]\d{1,2}"#, options: .regularExpression) != nil { return nil }
        var digits = text.filter(\.isNumber)
        if text.contains("+81") || (digits.hasPrefix("81") && digits.count >= 12) {
            if digits.hasPrefix("81") { digits = "0" + digits.dropFirst(2) }
        }
        guard digits.count == 10 || digits.count == 11 else { return nil }
        guard digits.hasPrefix("0") else { return nil }
        if digits.count == 11 {
            let head = String(digits.prefix(3))
            guard ["070", "080", "090", "050"].contains(head) else { return nil }
            return "\(digits.prefix(3))-\(digits.dropFirst(3).prefix(4))-\(digits.suffix(4))"
        }
        if text.contains("-"), text.filter({ $0.isNumber || $0 == "-" }).count == text.filter({ !$0.isWhitespace }).count {
            return text.filter { $0.isNumber || $0 == "-" }
        }
        return "\(digits.prefix(3))-\(digits.dropFirst(3).prefix(3))-\(digits.suffix(4))"
    }

    static func validAddress(_ text: String) -> String? {
        var value = trim(text)
        if let range = value.range(of: #"[^\s　]*駅から徒歩\d*分?"#, options: .regularExpression) {
            value = trim(String(value[..<range.lowerBound]))
        }
        guard let prefecture = prefecture(in: value) else { return nil }
        guard value.contains("市") || value.contains("区") || value.contains("町") || value.contains("村") else { return nil }
        guard value.contains(prefecture) else { return nil }
        guard value.count >= 8, value.count <= 80 else { return nil }
        return value
    }

    private static func prefecture(in text: String) -> String? {
        prefectures.first { text.contains($0) }
    }

    static func hourValue(_ text: String) -> String? {
        let trimmed = trim(text)
        if trimmed == "営業中" || trimmed == "営業終了" || trimmed == "営業時間外" { return nil }
        if trimmed.contains("営業中") || trimmed.contains("営業終了"), hourRanges(in: trimmed).isEmpty { return nil }
        return hourRanges(in: trimmed).first
    }

    private static func hourRanges(in text: String) -> [String] {
        let pattern = #"((?:翌)?\d{1,2})[:：](\d{2})\s*[~〜\-－–—]+\s*((?:翌)?\d{1,2})[:：](\d{2})"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let original = String(text[range])
            if original.contains("営業") { return nil }
            return original
        }
    }

    private static func hourKey(_ text: String) -> String {
        text.replacingOccurrences(of: #"翌(\d{1,2})"#, with: "$1+24", options: .regularExpression)
            .replacingOccurrences(of: #"(\d{1,2}):(\d{2})"#, with: "$1:$2", options: .regularExpression)
            .replacingOccurrences(of: "26:00", with: "2+24:00")
    }

    private static func absorbDetector(
        _ text: String,
        phones: inout [Candidate],
        addresses: inout [Candidate],
        urls: inout [Candidate]
    ) {
        let kinds = NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
        guard let detector = try? NSDataDetector(types: kinds) else { return }
        let ns = text as NSString
        detector.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            switch match.resultType {
            case .phoneNumber:
                if let phone = match.phoneNumber, let value = validPhone(phone) {
                    phones.append(Candidate(value: value, lineIDs: [], fromProse: false))
                }
            case .link:
                if let url = match.url?.absoluteString, urlClass(url) == .official {
                    urls.append(Candidate(value: cleanURL(url), lineIDs: [], fromProse: false))
                }
            case .address:
                let value = ns.substring(with: match.range)
                if let address = validAddress(value) {
                    addresses.append(Candidate(value: address, lineIDs: [], fromProse: false))
                }
            default:
                break
            }
        }
    }

    private static func cleanURL(_ text: String) -> String {
        trim(text).trimmingCharacters(in: CharacterSet(charactersIn: "。、.,);）」"))
    }

    private static func note(_ values: [Candidate]) -> FieldNote {
        let kept = Array(values.prefix(3))
        guard let first = kept.first else {
            return FieldNote(confidence: .missing)
        }
        return FieldNote(
            choices: kept.map(\.value),
            lineIDs: first.lineIDs,
            confidence: first.fromProse ? .review : .high,
            origin: .image,
            edited: false
        )
    }

    private static func rank(_ values: [Candidate]) -> [Candidate] {
        var kept: [Candidate] = []
        for value in values where !trim(value.value).isEmpty {
            if kept.contains(where: { $0.value == value.value || hourKey($0.value) == hourKey(value.value) }) { continue }
            if kept.contains(where: { $0.value.contains(value.value) && $0.value != value.value }) { continue }
            kept.removeAll { value.value.contains($0.value) && value.value != $0.value }
            kept.append(value)
        }
        return kept
    }

    private static func mergeField(
        _ note: FieldNote,
        ids: [Int],
        lines: [ReadLine],
        accept: (String) -> String?
    ) -> FieldNote {
        let picked = ids.compactMap { id in lines.first { $0.id == id } }
        let accepted = picked.compactMap { line -> String? in accept(normalize(line.text)) }
        let rule = Set(note.choices)
        let model = Set(accepted)
        var choices: [String] = []
        var confidence = ReadConfidence.missing
        var origin: ReadOrigin? = nil
        let agreed = accepted.filter { rule.contains($0) }
        if let first = agreed.first ?? note.choices.first(where: { model.isEmpty ? true : model.contains($0) }) {
            choices.append(first)
            confidence = model.contains(first) && rule.contains(first) ? .high : .review
            origin = model.contains(first) && !rule.contains(first) ? .intelligence : .image
        }
        for value in accepted where !choices.contains(value) && choices.count < 3 {
            choices.append(value)
            if confidence == .missing {
                confidence = .review
                origin = .intelligence
            }
        }
        for value in note.choices where !choices.contains(value) && choices.count < 3 {
            choices.append(value)
            if confidence == .missing {
                confidence = .review
                origin = .image
            }
        }
        if choices.isEmpty { return FieldNote(confidence: .missing) }
        if confidence == .missing { confidence = .review }
        let lineIDs = picked.isEmpty ? note.lineIDs : picked.map(\.id)
        return FieldNote(choices: choices, lineIDs: lineIDs, confidence: confidence, origin: origin, edited: false)
    }

    // MARK: - Maps URL

    private static func firstURL(in text: String) -> URL? {
        if let direct = URL(string: text), direct.scheme != nil { return direct }
        guard let found = matches(#"https?://[^\s　]+"#, in: text).first else { return nil }
        return URL(string: cleanURL(found))
    }

    private static func isMapsHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("google.") || host.contains("goo.gl") || host.contains("maps.app")
    }

    private static func placeName(_ url: URL) -> String {
        let parts = url.path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(of: "place"), parts.indices.contains(index + 1) {
            return shopTitle(decodeMaps(parts[index + 1]))
        }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return "" }
        let value = items.first { $0.name == "q" || $0.name == "query" }?.value ?? ""
        return shopTitle(decodeMaps(value))
    }

    private static func shopTitle(_ text: String) -> String {
        let trimmed = trim(text.components(separatedBy: "/@").first ?? text)
        guard !trimmed.isEmpty else { return "" }
        if coordinateText(trimmed) != nil { return "" }
        if let prefecture = prefecture(in: trimmed), let range = trimmed.range(of: prefecture) {
            return trim(String(trimmed[..<range.lowerBound]))
        }
        return trimmed
    }

    private static func coordinate(_ url: URL) -> (Double, Double)? {
        let absolute = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        if let found = coordinateText(absolute) { return found }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["ll", "q", "query"] {
            if let value = items.first(where: { $0.name == name })?.value, let found = coordinateText(value) {
                return found
            }
        }
        return nil
    }

    private static func coordinateText(_ text: String) -> (Double, Double)? {
        let patterns = [
            #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#,
            #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#,
            #"^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            guard let match = expression.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
                  let lat = Double(ns.substring(with: match.range(at: 1))),
                  let lon = Double(ns.substring(with: match.range(at: 2))) else { continue }
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { continue }
            return (lat, lon)
        }
        return nil
    }

    private static func decodeMaps(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return trim(spaced.removingPercentEncoding ?? spaced)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
