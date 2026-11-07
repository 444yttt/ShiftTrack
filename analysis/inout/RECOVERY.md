# IN/OUT からの回収範囲

対象は許諾済みの実機バイナリ `IN-OUT`（`com.graff.inout`、表示名 IN/OUT、1.0 build 3、iOS 17+）。ShiftTrack のソースではない。Bundle ID、表示名、署名、広告 ID は転用していない。

この文書の結論は未達である。元の Swift 実装は回収できておらず、基礎コードの直接流用もしていない。前回 Build 8 に入っている日付と時刻の変更は、画面文言と型名から起こした同機能の再実装であり、ここの疑似コードからの移植ではない。

## 前回まで

Linux 上の Python で `__swift5_types` から名義型 271 件（クラス 19、構造体 180、列挙 72）とフィールド名を読んだ。定義済みシンボルは `__mh_execute_header` の 1 個だけだった。疑似コードは作っていない。

## 今回実行した公知手法

採用した手順は、Derek Selander の dsdump 解説（名義型ディスクリプタ、`LC_FUNCTION_STARTS`、ObjC メソッド）、Ghidra の Mach-O `LC_FUNCTION_STARTS` 対応（NationalSecurityAgency/ghidra#3668）、Apple の `MetadataValues.h`（Swift 5.10.1 の `ContextDescriptorKind` と `Class_HasVTable`）、dyld の `DYLD_CHAINED_PTR_64_OFFSET`（pointer format 6）である。Ghidra 12.2 は JDK 25 必須で、この環境の JDK 21 では起動しなかった。代わりに Ghidra 11.4 PUBLIC（`application.java.min=21`）を headless で実行した。

```text
/tmp/ghidra_11.4_PUBLIC/support/analyzeHeadless /tmp/ghidra-proj InOut \
  -import IN-OUT -loader MachoLoader -noanalysis \
  -postScript DecompileSpots.java
```

ローダは `AARCH64:LE:64:AppleSilicon:swift` を選び、chained pointer 36904 個を解決した。SwiftUI.framework などシステムライブラリはこの環境に無いので、外部呼び出しは名前のない `func_0x...` になる。

X の公開投稿検索は `client-not-enrolled` で失敗し、同じ呼び出しは再試行していない。公開リポジトリ `444yttt/shifttrack-inout-analysis` は親コネクタが作成済みである。この環境の `gh` トークン（アカウント `cursor`）は `permissions.push=false` で、ファイルを置けない。macOS runner はそのため未実行。デコンパイラ自体は Linux の Ghidra で動いた。private の ShiftTrack は公開していない。

## 実行結果

| 項目 | 結果 |
| --- | --- |
| `LC_FUNCTION_STARTS` | 15672 関数。先頭 `0x100004000`、末尾付近 `0x1003fc950` |
| シンボル | `nsyms` 2273 のうち `N_SECT` は 1 |
| 画面の型 | `CalendarTabView`、`ShiftEntryEditor`、`SlotTimePicker` などは struct。クラス vtable の対象外 |
| `DataStore` | クラス。`NumFields` は 2 で、フィールド名 `url` と `lock` と一致。vtable の実装アドレスは `__text` に落ちなかった |
| ObjC メソッド | 相対メソッドリストから名前 2778。中身は広告 SDK、位置情報、写真選択が中心で、給料計算や週スワイプの実装名は無い |
| protocol witness | 652 conformance。`SwiftUI.View.body` まで名前が付いた。モデル型の witness は Equatable / Codable |
| chained fixup | このバイナリの format 6 は bind が bit 63、next が bit 51–62。36904 個を解決 |
| 文字列 xref | 「開始と終了を異なる時刻」は `0x1001b960c`。「丸めるのは、お給料」は `0x10015df8c`。週スワイプの説明はファイル `0x4fc53e` にあるが、`__cstring` 起点の ADRP+ADD では関数に結び付かない |

Ghidra の疑似コード（元ソースではない）:

- `0x1001e6a70`（84 バイト）はタグで `"name"` / `"address"` / `"location"` を返す合成コード。全文は `PSEUDOCODE.md`。
- `0x10015df8c` はスタック上の値コピーが並ぶだけで、除算や丸めは無い。ヘルプ文を出す側である。
- `0x1001b960c` は Swift のマングリング `__s7SwiftUI5StateV12wrappedValuexvg`（`SwiftUI.State.wrappedValue` の getter）を呼び、二つの値を比較している。`uStack_1b0._4_4_ = (uint)(lVar3 != alStack_f0[0]);` までで、開始と終了の不一致を画面に出す SwiftUI の body であり、保存処理そのものではない。

## View.body と休憩の初期値

`SwiftUI.View` の resilient witness から `body` の入口を特定した。4 バイトの `b` の先が本体。

| 型 | thunk | 本体 |
| --- | --- | --- |
| CalendarTabView | `0x100071b20` | `0x1000541dc`（6536 バイト） |
| SlotTimePicker | `0x100028500` | `0x100027b88` |
| CalendarDayView | `0x100048f9c` | `0x10003cdd8` |
| IncomeView | `0x1000ba040` | `0x1000b2154` |
| WallEditorView | `0x1000c0280` | `0x1000bc9b8` |
| MinuteOfDayRow | `0x100088408`（56 バイト） | `0x100087f90` を呼ぶ |

`0x1000da43c` は法定休憩の初期値を書く。`mov w9, #0x168` と `#0x2d`、続く `#0x1e0` と `#0x3c` で、360 分→45 分、480 分→60 分の組をグローバル `0x1005d0a40` に置く。比較して休憩を選ぶ関数は、このグローバルの直接読み出し先（`0x1000de2b0` と `0x1000df388`）ではポインタをモデルへコピーしているだけで、除算は無い。

`PayRounding` のフィールドは `unitMinutes` / `start` / `end`。witness は `hashValue` と `encode` / `init(from:)` で、丸め式ではない。15 で割る小さい関数は Swift ランタイムの剰余で、給料計算ではない。

## 不足しているもの

名前の付いた給料計算、週の選択更新、時刻ホイールの計算本体は残っていない。struct メソッドは vtable に載らない。`body` 本体は数千バイトの SwiftUI 構築で、そこから保存式は分離できていない。

元ソース、計算アルゴリズムの疑似コード、それに基づく Swift 再構成は、製品へ統合していない。法定休憩の定数だけを新しい給料規則として足すことは、選択関数が未回収なのでしていない。

## 公開リポジトリへ置くファイル

このトークンでは push できない。`analysis/inout/public-bundle/` を `444yttt/shifttrack-inout-analysis` の `main` 直下へコミットすると、`macos-verify` が標準の `macos-15` runner で動く。バイナリは署名領域をゼロにし、広告 ID と埋め込みメールを同じ長さで潰してある。Linux 上では命令バイトの検査だけ通り、`swift-demangle` と `dyld_info` と SwiftUI.framework はこの環境に無い。
