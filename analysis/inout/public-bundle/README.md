# shifttrack-inout-analysis

許諾済み IN/OUT 実機バイナリの静的解析。元の Swift ソースではない。

`bin/IN-OUT` はコード署名領域をゼロにし、広告ユニット ID と埋め込みのメールアドレスを同じ長さの `X` で潰した Mach-O である。ShiftTrack 本体は含まれない。

`main` への push で GitHub Actions の標準 macOS runner（`macos-15`）が `tools/verify_macos.py` を実行する。確認内容は、法定休憩の初期値を書き込む命令、`CalendarTabView.body` の分岐先、`swift-demangle`、`dyld_info -fixups`、iPhoneOS SDK の SwiftUI.framework の有無。
