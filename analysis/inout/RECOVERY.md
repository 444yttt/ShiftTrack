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

X の公開投稿検索は `client-not-enrolled` で失敗し、同じ呼び出しは再試行していない。公開の解析用リポジトリは `gh repo create` が `Resource not accessible by integration` で作れなかった。private の ShiftTrack は公開していない。解析用の macOS runner は起動していない。デコンパイラ自体は Linux の Ghidra で、同じ Mach-O に対して動いた。

## 実行結果

| 項目 | 結果 |
| --- | --- |
| `LC_FUNCTION_STARTS` | 15672 関数。先頭 `0x100004000`、末尾付近 `0x1003fc950` |
| シンボル | `nsyms` 2273 のうち `N_SECT` は 1 |
| 画面の型 | `CalendarTabView`、`ShiftEntryEditor`、`SlotTimePicker` などは struct。クラス vtable の対象外 |
| `DataStore` | クラス。`NumFields` は 2 で、フィールド名 `url` と `lock` と一致。vtable の実装アドレスは `__text` に落ちなかった |
| ObjC メソッド | 相対メソッドリストから名前 2778。中身は広告 SDK、位置情報、写真選択が中心で、給料計算や週スワイプの実装名は無い |
| protocol witness | 652 conformance。当たった関数は Equatable / Codable 系の合成コード |
| 文字列 xref | 「開始と終了を異なる時刻」は `0x1001b960c`（2520 バイト）、「丸めるのは、お給料」は `0x10015df8c`（604 バイト）。週スワイプの説明文 `0x1004fc4f0` は ADRP+ADD でも chained fixup でも参照が無かった |

Ghidra の疑似コード（元ソースではない）:

- `0x1001e6a70`（84 バイト）はタグで `"name"` / `"address"` / `"location"` を返す合成コード。全文は `PSEUDOCODE.md`。
- `0x10015df8c` はスタック上の値コピーが並ぶだけで、除算や丸めは無い。ヘルプ文を出す側である。
- `0x1001b960c` は Swift のマングリング `__s7SwiftUI5StateV12wrappedValuexvg`（`SwiftUI.State.wrappedValue` の getter）を呼び、二つの値を比較している。`uStack_1b0._4_4_ = (uint)(lVar3 != alStack_f0[0]);` までで、開始と終了の不一致を画面に出す SwiftUI の body であり、保存処理そのものではない。

## 不足しているもの

関数の開始位置と、文字列や protocol witness に繋がる一部の関数は取れた。名前の付いた給料計算、週移動、時刻ホイールの本体は残っていない。struct のメソッドは vtable に載らず、シンボルも削られている。15,672 個を片端から疑似コードにしても、どれが元の `body` や計算関数かは対応が付かない。システムフレームワークが無いので、SwiftUI 呼び出しは解決できない。

したがって元ソース、計算アルゴリズムの疑似コード、それに基づく Swift 再構成は、いずれも製品へ統合していない。
