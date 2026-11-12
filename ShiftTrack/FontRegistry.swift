import CoreText
import SwiftUI
import UIKit

/// Makes sure the bundled Doto is available and reads its licence.
///
/// Info.plist lists `Fonts/Doto-BlackRound.ttf`, but a synchronized Xcode
/// folder can copy resources to the bundle root. When `UIAppFonts` did not
/// register the face, it is registered here from wherever it was copied.
enum FontRegistry {
    @discardableResult
    static func ensureDoto(bundle: Bundle = .main) -> Bool {
        if UIFont(name: Font.dotoName, size: 12) != nil { return true }
        guard let url = resource("Doto-BlackRound", "ttf", bundle: bundle) else { return false }
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return UIFont(name: Font.dotoName, size: 12) != nil
    }

    /// The SIL Open Font License shipped next to the font.
    static func dotoLicense(bundle: Bundle = .main) -> String? {
        guard let url = resource("OFL", "txt", bundle: bundle) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func resource(_ name: String, _ ext: String, bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fonts")
    }
}

/// Settings → このアプリについて → フォントのライセンス.
struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: Space.m) {
                Card {
                    Text("時計や金額の点の数字には、Google Fonts の Doto を使っています。Doto は SIL Open Font License 1.1 で公開されているフォントです。")
                        .font(AppFont.body)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    DotoText("0123456789", size: 28, spoken: "Doto の数字の見本")
                }
                .padding(.top, Space.xs)
                Card {
                    SectionHeader(title: "ライセンス全文")
                    Text(FontRegistry.dotoLicense() ?? "ライセンスの文書を読み込めませんでした。")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("license.text")
                }
            }
            .background(Theme.paper)
            .navigationTitle("フォントのライセンス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(Theme.signalInk)
                }
            }
            .darkSheet()
        }
    }
}
