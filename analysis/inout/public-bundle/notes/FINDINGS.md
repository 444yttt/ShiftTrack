# 実行で確定した範囲

元の Swift ソースはバイナリに無い。以下は命令と Swift メタデータの読み取り結果である。

## SwiftUI.View.body の入口

witness の実装アドレスは 4 バイトの `b` で、本体は分岐先。

| 型 | thunk | 本体 |
| --- | --- | --- |
| CalendarTabView | `0x100071b20` | `0x1000541dc`（6536 バイト） |
| SlotTimePicker | `0x100028500` | `0x100027b88` |
| CalendarDayView | `0x100048f9c` | `0x10003cdd8` |
| IncomeView | `0x1000ba040` | `0x1000b2154` |
| WallEditorView | `0x1000c0280` | `0x1000bc9b8` |
| MinuteOfDayRow | `0x100088408` | 56 バイト。中で `0x100087f90` を呼ぶ |

本体は SwiftUI の view 構築で、給料式や週移動の独立した関数ではない。

## 法定休憩の初期値

`0x1000da43c`（312 バイト）がレコードを 2 つ書き、グローバル `0x1005d0a40` に格納する。

| 命令 | 即値 |
| --- | --- |
| `0x1000da508` `mov w9, #0x168` | 360 分 |
| `0x1000da514` `mov w9, #0x2d` | 45 分 |
| `0x1000da53c` `mov w9, #0x1e0` | 480 分 |
| `0x1000da548` `mov w9, #0x3c` | 60 分 |

これは初期化であって、分数と比較して休憩を選ぶ関数そのものではない。`PayRounding` の witness は Hashable / Codable で、丸め計算ではない。
