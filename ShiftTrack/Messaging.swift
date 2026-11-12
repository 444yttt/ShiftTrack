import SwiftUI
import UIKit

/// Links for the three workplace actions: 地図, 電話, メッセージ.
/// Each returns nil when the workplace lacks the data, and the screens then
/// disable the button and show the matching reason.
enum WorkplaceContact {
    static let missingAddress = "住所が未登録です"
    static let missingPhone = "電話番号が未登録です"

    /// Digits of a phone number (full-width folded), with a leading “+” kept.
    static func phoneDigits(_ raw: String) -> String {
        let folded = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        var digits = ""
        for character in folded where character.isASCII {
            if character.isNumber {
                digits.append(character)
            } else if character == "+", digits.isEmpty {
                digits.append(character)
            }
        }
        return digits
    }

    static func hasPhone(_ raw: String) -> Bool {
        phoneDigits(raw).filter(\.isNumber).count >= 3
    }

    /// Apple Maps: the saved pin when there is one, otherwise the address as a search.
    static func mapURL(name: String, address: String, latitude: Double, longitude: Double, hasCoordinate: Bool) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "https://maps.apple.com/")
        if hasCoordinate, latitude != 0 || longitude != 0 {
            components?.queryItems = [
                URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)),
                URLQueryItem(name: "q", value: name.isEmpty ? trimmed : name),
            ]
        } else if !trimmed.isEmpty {
            components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        } else {
            return nil
        }
        return components?.url
    }

    static func mapURL(for workplace: Workplace) -> URL? {
        mapURL(
            name: workplace.name,
            address: workplace.place,
            latitude: workplace.latitude,
            longitude: workplace.longitude,
            hasCoordinate: workplace.hasMapCoordinate
        )
    }

    static func telURL(_ phone: String) -> URL? {
        guard hasPhone(phone) else { return nil }
        return URL(string: "tel:\(phoneDigits(phone))")
    }

    /// Messages with the text filled in. iOS reads the body after `&body=`.
    static func smsURL(_ phone: String, body: String) -> URL? {
        guard hasPhone(phone) else { return nil }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))
        let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "sms:\(phoneDigits(phone))&body=\(encoded)")
    }

    static func mapReason(for workplace: Workplace) -> String? {
        mapURL(for: workplace) == nil ? missingAddress : nil
    }

    static func phoneReason(for workplace: Workplace) -> String? {
        hasPhone(workplace.phone) ? nil : missingPhone
    }
}

/// The message template: stored text plus the choices offered when composing.
enum MessageTemplate {
    static let reasons = [
        "電車が遅れているため",
        "道が混んでいるため",
        "体調がすぐれないため",
        "寝過ごしてしまったため",
        "家の用事が長引いたため",
    ]
    static let sampleAddressee = "架空茶房 北窓"

    static var current: String {
        let stored = UserDefaults.standard.string(forKey: LateMessageFill.templateKey) ?? ""
        return stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LateMessageFill.polite : stored
    }

    static func save(_ template: String) {
        UserDefaults.standard.set(template, forKey: LateMessageFill.templateKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: LateMessageFill.templateKey)
    }

    static func delayText(minutes: Int) -> String {
        "\(minutes)分ほど遅れます"
    }

    static func preview(_ template: String) -> String {
        LateMessageFill.apply(
            template: template,
            addressee: sampleAddressee,
            reason: reasons[0],
            delay: delayText(minutes: 15)
        )
    }

    /// First line of the filled sample, for the settings row.
    static var summary: String {
        preview(current)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
    }
}

/// Builds the message from the template and hands it to Messages.
struct MessageComposerSheet: View {
    var workplace: Workplace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var addressee = ""
    @State private var reason = MessageTemplate.reasons[0]
    @State private var ownReason = ""
    @State private var minutes = 15
    @State private var template = MessageTemplate.current
    @State private var copied = false
    @State private var editTemplate = false
    @State private var loaded = false

    private var reasonText: String {
        let typed = ownReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? reason : typed
    }

    private var draft: String {
        LateMessageFill.apply(
            template: template,
            addressee: addressee,
            reason: reasonText,
            delay: MessageTemplate.delayText(minutes: minutes)
        )
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                InfoNote(text: "設定の「連絡メッセージのひな形」から文章を作ります。送る前に、ここで中身を確かめられます。")
                    .padding(.top, Space.xs)
                Card {
                    LabeledField(
                        label: "宛名",
                        text: $addressee,
                        prompt: "例：店長",
                        helper: "ひな形の {宛名} に入ります。空にすると、その行を省きます。",
                        identifier: "message.addressee"
                    )
                }
                Card {
                    PickerRow(label: "遅れる理由", selection: $reason, identifier: "message.reason") {
                        ForEach(MessageTemplate.reasons, id: \.self) { Text($0).tag($0) }
                    }
                    LabeledField(
                        label: "理由を自分で書く（任意）",
                        text: $ownReason,
                        prompt: "例：バスが来ないため",
                        helper: "書いたときは、上で選んだ理由の代わりに使います。",
                        identifier: "message.ownReason"
                    )
                    RowDivider()
                    StepperRow(
                        label: "遅れる時間",
                        valueText: "\(minutes)分",
                        value: $minutes,
                        range: 5...120,
                        step: 5,
                        identifier: "message.minutes"
                    )
                }
                Card {
                    SectionHeader(title: "送る文章")
                    Text(draft)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("message.preview")
                    TextLinkButton(title: "ひな形を直す", systemImage: "square.and.pencil", identifier: "message.template") {
                        editTemplate = true
                    }
                }
                PrimaryButton(title: "メッセージで送る", systemImage: "message.fill", identifier: "message.send") {
                    if let url = WorkplaceContact.smsURL(workplace.phone, body: draft) {
                        openURL(url)
                        dismiss()
                    }
                }
                .disabled(!WorkplaceContact.hasPhone(workplace.phone))
                if !WorkplaceContact.hasPhone(workplace.phone) {
                    InfoNote(text: "\(WorkplaceContact.missingPhone)。勤務先の編集で電話番号を入れると、メッセージで送れます。", tone: .warning)
                }
                SecondaryButton(title: copied ? "コピーしました" : "文章をコピー", systemImage: "doc.on.doc", identifier: "message.copy") {
                    UIPasteboard.general.string = draft
                    copied = true
                }
            }
            .background(Theme.paper)
            .navigationTitle("メッセージを作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onAppear {
                guard !loaded else { return }
                loaded = true
                addressee = workplace.name
            }
            .onChange(of: draft) { _, _ in copied = false }
            .sheet(isPresented: $editTemplate, onDismiss: { template = MessageTemplate.current }) {
                MessageTemplateEditor()
            }
        }
    }
}

/// Settings → 連絡メッセージのひな形. The text the メッセージ button starts from.
struct MessageTemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var template = MessageTemplate.current
    @State private var saved = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                Card {
                    Label("このひな形について", systemImage: "info.circle")
                        .font(AppFont.rowTitle)
                        .foregroundStyle(Theme.ink)
                    Text("ホームと勤務先の「メッセージ」ボタンで、遅れるときの連絡を作るときに使う文章です。送る前に毎回、宛名・理由・時間を選んで中身を確かめられます。")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.xs)
                Card {
                    SectionHeader(title: "ひな形", detail: "次の部品は、送るときに置き換わります。")
                    VStack(alignment: .leading, spacing: 4) {
                        tokenLine("{宛名}", "宛名（空のときは、その行ごと省きます）")
                        tokenLine("{理由}", "遅れる理由")
                        tokenLine("{遅れ}", "遅れる時間（例：15分ほど遅れます）")
                    }
                    TextField("ひな形", text: $template, axis: .vertical)
                        .lineLimit(4...10)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .focused($typing)
                        .padding(Space.s)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                        .accessibilityLabel("ひな形")
                        .accessibilityIdentifier("late.template")
                    Text("部品を文の最後に足す")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: Space.xs) {
                        ForEach([LateMessageFill.addressee, LateMessageFill.reason, LateMessageFill.delay], id: \.self) { token in
                            SecondaryButton(title: token, fillWidth: true, identifier: "late.token.\(token)") {
                                template += token
                            }
                        }
                    }
                    Text("ひな形を選び直す")
                        .font(AppFont.label)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: Space.xs) {
                        SecondaryButton(title: "ていねい", fillWidth: true, identifier: "late.polite") { template = LateMessageFill.polite }
                        SecondaryButton(title: "短め", fillWidth: true, identifier: "late.casual") { template = LateMessageFill.casual }
                    }
                }
                Card {
                    SectionHeader(title: "プレビュー", detail: "例として、宛名「\(MessageTemplate.sampleAddressee)」、理由「\(MessageTemplate.reasons[0])」、15分の遅れで表示しています。")
                    Text(MessageTemplate.preview(template))
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.s)
                        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .accessibilityIdentifier("late.preview")
                }
                PrimaryButton(title: "保存", identifier: "late.save") {
                    MessageTemplate.save(template)
                    saved = true
                    typing = false
                }
                .disabled(template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if saved {
                    InfoNote(text: "保存しました。次にメッセージを作るときから使います。", systemImage: "checkmark.circle")
                }
                DestructiveButton(title: "最初の文章に戻す", identifier: "late.reset") {
                    MessageTemplate.reset()
                    template = MessageTemplate.current
                    saved = false
                }
            }
            .background(Theme.paper)
            .navigationTitle("連絡メッセージのひな形")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { typing = false }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
            .onChange(of: template) { _, _ in saved = false }
        }
    }

    private func tokenLine(_ token: String, _ meaning: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(token)
                .font(AppFont.label.monospaced())
                .foregroundStyle(Theme.ink)
            Text(meaning)
                .font(AppFont.helper)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
