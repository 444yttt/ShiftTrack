import Foundation

/// A workplace read from a shop card or a maps link, before it is saved.
struct WorkplaceDraft: Equatable, Codable {
    var name = ""
    var phone = ""
    var address = ""
    var hours = ""
    var officialURL = ""
    var nameChoices: [String] = []
    var phoneChoices: [String] = []
    var addressChoices: [String] = []
    var hoursChoices: [String] = []
    var urlChoices: [String] = []
    var transcript = ""
    var locateFromAddress = true
    var mapsNotice = ""
    var latitude = 0.0
    var longitude = 0.0
    var hasCoordinate = false

    static let mapsUnreadable = "Google マップのリンクから店舗の情報を読めませんでした。店名や住所を直接入力してください。"
}

enum WorkplaceRead {
    static func draft(from raw: String) -> WorkplaceDraft {
        let transcript = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = joined(dropNoise(transcript.components(separatedBy: "\n").map(trim)))
        let labeled = labeledValues(lines)
        var names = labeled.name + lines.filter(isShopName) + namesBeforeAddresses(lines)
        var phones = labeled.phone + phones(in: lines.joined(separator: "\n"))
        var addresses = labeled.address.flatMap(addressCores) + lines.flatMap(addressCores)
        var hours = labeled.hours + hourRanges(in: lines.joined(separator: "\n"))
        var urls = labeled.url + links(in: lines.joined(separator: "\n"))
        absorbDetector(transcript, phones: &phones, addresses: &addresses, urls: &urls)
        names = rank(names.filter(isShopName))
        phones = rank(phones.map(normalizePhone).filter(isPhone))
        addresses = rank(addresses.filter(isCompleteAddress))
        hours = rank(hours.map(normalizeHours).filter { !$0.isEmpty })
        urls = rank(urls.map(cleanURL).filter(isOfficialURL))
        var draft = WorkplaceDraft()
        draft.transcript = transcript
        draft.nameChoices = names
        draft.phoneChoices = phones
        draft.addressChoices = addresses
        draft.hoursChoices = hours
        draft.urlChoices = urls
        draft.name = names.first ?? ""
        draft.phone = phones.first ?? ""
        draft.address = addresses.first ?? ""
        draft.hours = hours.first ?? ""
        draft.officialURL = urls.first ?? ""
        return draft
    }

    static func draft(fromMapsLink raw: String) -> WorkplaceDraft {
        let trimmed = trim(raw)
        guard let url = firstURL(in: trimmed), isMapsHost(url) else {
            var draft = WorkplaceDraft()
            draft.transcript = trimmed
            draft.mapsNotice = WorkplaceDraft.mapsUnreadable
            return draft
        }
        let place = mapsPlace(url)
        let query = mapsQuery(url)
        let text = [place, query].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        var draft = text.isEmpty ? WorkplaceDraft() : draft(from: text)
        draft.transcript = trimmed
        if draft.name.isEmpty, let place, isShopName(place) {
            draft.name = place
            draft.nameChoices = rank([place] + draft.nameChoices)
        }
        if draft.name.isEmpty, draft.address.isEmpty, draft.phone.isEmpty {
            draft.mapsNotice = WorkplaceDraft.mapsUnreadable
        }
        return draft
    }

    // MARK: - Lines

    private static let chrome: Set<String> = [
        "キャンセル", "反映", "質問する", "閉じる", "検索", "戻る", "店舗情報",
        "読み取り結果", "読み取った文字", "名前", "店舗名", "店名", "電話番号",
        "住所", "位置", "営業時間", "公式サイト", "連絡先", "電話", "所在地",
        "ホームページ", "公式", "url", "URL", "マップで探す", "写真から読み取る",
        "撮影する", "写真から選ぶ", "ショップカード", "反映する内容", "営業"
    ]

    private static func dropNoise(_ lines: [String]) -> [String] {
        lines.filter { line in
            let text = trim(line)
            if text.isEmpty { return false }
            if chrome.contains(text) { return false }
            if isStatusChrome(text) { return false }
            if text.hasPrefix("あります") { return false }
            if text.hasPrefix("や、") || text.hasPrefix("や→") { return false }
            if text.contains("について詳しく") || text.contains("知りたい") { return false }
            if text.contains("質問する") { return false }
            if text.hasPrefix("候補を選ぶ") || text.contains("空欄の項目") { return false }
            if text.contains("反映しません") { return false }
            return true
        }
    }

    private static func isStatusChrome(_ line: String) -> Bool {
        if line.range(of: #"^\d{1,2}[:：]\d{2}$"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^\d{1,2}[:：]\d{2}(\s+\d{1,3})+$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func joined(_ lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < lines.count {
            var current = lines[index]
            while index + 1 < lines.count {
                let next = lines[index + 1]
                if shouldJoinAddress(current, next) || shouldJoinPhone(current, next) {
                    current += next
                    index += 1
                } else {
                    break
                }
            }
            result.append(current)
            index += 1
        }
        return result
    }

    private static func shouldJoinAddress(_ current: String, _ next: String) -> Bool {
        guard !isCompleteAddress(current) else { return false }
        guard hasPrefecture(current) || current.hasSuffix("市") || current.hasSuffix("区") else { return false }
        if next.hasPrefix("市") || next.hasPrefix("区") || next.hasPrefix("町") || next.hasPrefix("村") { return true }
        if next.range(of: #"^[0-9０-９\-－]"#, options: .regularExpression) != nil, isAddressFragment(current) { return true }
        return false
    }

    private static func shouldJoinPhone(_ current: String, _ next: String) -> Bool {
        let digits = current.filter(\.isNumber)
        guard digits.count < 10, digits.count >= 2, current.hasPrefix("0") else { return false }
        guard current.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "－" }) else { return false }
        let more = next.filter(\.isNumber)
        guard !more.isEmpty, next.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "－" }) else { return false }
        return digits.count + more.count <= 11
    }

    private struct Labeled {
        var name: [String] = []
        var phone: [String] = []
        var address: [String] = []
        var hours: [String] = []
        var url: [String] = []
    }

    private enum Slot {
        case name, phone, address, hours, url
    }

    private static func labeledValues(_ lines: [String]) -> Labeled {
        var labeled = Labeled()
        var index = 0
        while index < lines.count {
            guard let slot = labelSlot(lines[index]) else {
                index += 1
                continue
            }
            var value = slot.value ?? ""
            if value.isEmpty {
                var follow: [String] = []
                var cursor = index + 1
                while cursor < lines.count, labelSlot(lines[cursor]) == nil, !isStatusChrome(lines[cursor]) {
                    follow.append(lines[cursor])
                    cursor += 1
                    if slot.slot != .address { break }
                    if follow.contains(where: isCompleteAddress) { break }
                }
                value = follow.joined()
                index = max(index, cursor - 1)
            }
            let text = trim(value)
            switch slot.slot {
            case .name: labeled.name.append(text)
            case .phone: labeled.phone.append(text)
            case .address: labeled.address.append(text)
            case .hours: labeled.hours.append(text)
            case .url: labeled.url.append(text)
            }
            index += 1
        }
        return labeled
    }

    private static func labelSlot(_ line: String) -> (slot: Slot, value: String?)? {
        let pairs: [(String, Slot)] = [
            ("公式サイト", .url), ("公式URL", .url), ("ホームページ", .url),
            ("営業時間", .hours), ("店舗名", .name), ("電話番号", .phone),
            ("所在地", .address), ("反映する内容", .name), ("店名", .name),
            ("名前", .name), ("住所", .address), ("電話", .phone), ("TEL", .phone),
            ("URL", .url), ("営業", .hours)
        ]
        for (label, slot) in pairs {
            if line.caseInsensitiveCompare(label) == .orderedSame { return (slot, nil) }
            if line.lowercased().hasPrefix(label.lowercased()) {
                let rest = trim(String(line.dropFirst(label.count)).trimmingCharacters(in: CharacterSet(charactersIn: ":：・")))
                if rest.isEmpty { return (slot, nil) }
                return (slot, rest)
            }
        }
        return nil
    }

    // MARK: - Fields

    private static func namesBeforeAddresses(_ lines: [String]) -> [String] {
        lines.flatMap { line in
            addressCores(in: line).compactMap { address -> String? in
                guard let range = line.range(of: address) else { return nil }
                let prefix = trim(String(line[..<range.lowerBound]))
                return isShopName(prefix) ? prefix : nil
            }
        }
    }

    private static func isShopName(_ line: String) -> Bool {
        let text = trim(line)
        guard text.count >= 2, text.count <= 32 else { return false }
        if chrome.contains(text) { return false }
        if isStatusChrome(text) { return false }
        if isCompleteAddress(text) || isPhone(text) || isOfficialURL(text) { return false }
        if !hourRanges(in: text).isEmpty, text.count < 16 { return false }
        let banned = ["です", "ます", "について", "場合", "詳しく", "質問", "あります", "候補", "反映", "選ぶ", "入力", "空欄", "知りたい"]
        if banned.contains(where: { text.contains($0) }) { return false }
        if text.hasPrefix("や、") || text.hasPrefix("→") || text.hasPrefix("●") { return false }
        let letters = text.filter { $0.isLetter || $0.isNumber }
        return letters.count >= 2
    }

    private static func phones(in text: String) -> [String] {
        matches(#"0\d{1,4}-\d{1,4}-\d{3,4}"#, in: text)
    }

    private static func isPhone(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        return (10...11).contains(digits.count) && text.hasPrefix("0")
    }

    private static func normalizePhone(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        if text.contains("-"), isPhone(text) { return text.filter { $0.isNumber || $0 == "-" } }
        if digits.count == 11 {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(4)
            let c = digits.suffix(4)
            return "\(a)-\(b)-\(c)"
        }
        if digits.count == 10 {
            let a = digits.prefix(3)
            let b = digits.dropFirst(3).prefix(3)
            let c = digits.suffix(4)
            return "\(a)-\(b)-\(c)"
        }
        return text
    }

    private static func addressCores(in text: String) -> [String] {
        let pattern = #"(?:北海道|東京都|大阪府|京都府|.{2,3}県)[^\n]{0,40}?[0-9０-９]+(?:-[0-9０-９]+){0,3}"#
        return matches(pattern, in: text)
    }

    private static func hasPrefecture(_ text: String) -> Bool {
        if text.contains("北海道") || text.contains("東京都") || text.contains("大阪府") || text.contains("京都府") {
            return true
        }
        return text.range(of: #".{2,3}県"#, options: .regularExpression) != nil
    }

    private static func hasMunicipality(_ text: String) -> Bool {
        text.contains("市") || text.contains("区") || text.contains("町") || text.contains("村")
    }

    private static func isAddressFragment(_ text: String) -> Bool {
        hasPrefecture(text) || hasMunicipality(text)
    }

    private static func isCompleteAddress(_ text: String) -> Bool {
        let value = trim(text)
        guard value.count >= 8, value.count <= 80 else { return false }
        guard hasPrefecture(value), hasMunicipality(value) else { return false }
        return value.contains(where: \.isNumber)
    }

    private static func hourRanges(in text: String) -> [String] {
        let pattern = #"(\d{1,2})[:：](\d{2})\s*[~〜\-－–—]+\s*(\d{1,2})[:：](\d{2})"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let h1 = ns.substring(with: match.range(at: 1))
            let m1 = ns.substring(with: match.range(at: 2))
            let h2 = ns.substring(with: match.range(at: 3))
            let m2 = ns.substring(with: match.range(at: 4))
            return "\(h1):\(m1)–\(h2):\(m2)"
        }
    }

    private static func normalizeHours(_ text: String) -> String {
        hourRanges(in: text).first ?? ""
    }

    private static func links(in text: String) -> [String] {
        matches(#"https?://[^\s　<>]+"#, in: text).map(cleanURL)
    }

    private static func isOfficialURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let host = url.host?.lowercased() else { return false }
        if host.contains("google.") || host.contains("goo.gl") || host == "maps.app" { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    private static func cleanURL(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "。、.,);）」"))
    }

    private static func absorbDetector(
        _ text: String,
        phones: inout [String],
        addresses: inout [String],
        urls: inout [String]
    ) {
        let kinds = NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
        guard let detector = try? NSDataDetector(types: kinds) else { return }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        detector.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            switch match.resultType {
            case .phoneNumber:
                if let phone = match.phoneNumber { phones.append(phone) }
            case .link:
                if let url = match.url?.absoluteString { urls.append(url) }
            case .address:
                addresses.append(ns.substring(with: match.range))
            default:
                break
            }
        }
    }

    private static func rank(_ values: [String]) -> [String] {
        var kept: [String] = []
        for value in values.map(trim) where !value.isEmpty {
            if kept.contains(value) { continue }
            if kept.contains(where: { $0.contains(value) }) { continue }
            kept.removeAll { value.contains($0) }
            kept.append(value)
        }
        return kept
    }

    // MARK: - Maps

    private static func firstURL(in text: String) -> URL? {
        if let direct = URL(string: text), direct.scheme != nil { return direct }
        guard let found = matches(#"https?://[^\s　]+"#, in: text).first else { return nil }
        return URL(string: cleanURL(found))
    }

    private static func isMapsHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        return host.contains("google.") || host.contains("goo.gl") || host.contains("maps.app")
    }

    private static func mapsPlace(_ url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "place"), parts.indices.contains(index + 1) else { return nil }
        return decodeMaps(parts[index + 1])
    }

    private static func mapsQuery(_ url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let value = items.first { $0.name == "q" || $0.name == "query" }?.value
        guard let value, !value.isEmpty else { return nil }
        if value.range(of: #"^-?\d+(\.\d+)?\s*,\s*-?\d+"#, options: .regularExpression) != nil, !value.contains(where: \.isLetter) {
            return nil
        }
        return decodeMaps(value)
    }

    private static func decodeMaps(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return trim((spaced.removingPercentEncoding ?? spaced).components(separatedBy: "/@").first ?? spaced)
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
