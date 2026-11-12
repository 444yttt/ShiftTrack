# ShiftTrack (しふとらっく) — redesign spec

Status: implemented on branch `claude/sharp-keller-6rgbcn`. This file is the source of truth for the
redesign; the PR description summarises what was actually finished.

## 1. Goals and principles

1. **One look everywhere.** Warm paper background, white cards, ink text, one signal colour (lime) used
   only as a *fill*. No floating black cards in lists (the old settings notification card), no
   white-on-white leftovers from the old dark theme.
2. **Every control has a visible label.** A picker, stepper or text field never appears without a
   text label next to or above it. Helper text explains what a setting changes.
3. **Readable by default.** All text pairs meet WCAG 2.x AA (4.5:1); control boundaries and switch
   states meet 3:1 (WCAG 1.4.11). Text uses Dynamic Type text styles (up to AX3 in content; the
   system tab bar keeps its own sizes and long-press large-content viewer). Every tap target is at
   least 44×44 pt.
   Motion stops with “Reduce Motion”.
4. **Numbers you watch are dot-matrix.** The clock, shift times and money that changes live are set
   in Doto (Google Fonts, SIL OFL 1.1). Everything you *read* is the system font.
5. **Original work only.** The landscape is drawn in SwiftUI `Canvas`; copy is written for this app.
   Strings, layout constants and tutorial text that earlier work took from another app’s binary or
   screenshots are replaced (see §7). Demo data uses the fictional store 「架空茶房 北窓」.
6. **Data is safe.** Only additive, defaulted SwiftData changes. No field is renamed or removed.

## 2. Navigation map

The standard system tab bar (`TabView`), anchored to the bottom safe area at the system height,
per Apple’s Human Interface Guidelines. Each screen is a scroll view, so content scrolls under the
bar and its last row can be scrolled clear of it. The selected item uses the app tint (`signalInk`);
before iOS 26 the bar keeps the default blurred background and unselected items use `ink2`
(the default grey is under 4.5:1); iOS 26 draws its own glass bar. UI tests find tabs by title in
`app.tabBars`. The order changes to match how often each tab is used. (An earlier build of this
redesign had a custom floating capsule; owner feedback on build 22 was that it sat too high.)

```
Root  ─ tab bar ─────────────────────────────────────────────────────────────
├─ ホーム        TodayScreen
│   ├─ sheet  シフトを追加 / シフトの詳細      ShiftEditorView
│   │          └─ sheet 開始の時刻 / 終了の時刻 (TimeAdjustSheet), 日付を変更
│   ├─ sheet  勤務先を登録                    WorkplaceWizard        (no workplace yet)
│   ├─ sheet  メッセージを作る                 MessageComposerSheet   (quick action)
│   ├─ sheet  やること                        TodoEditor
│   ├─ sheet  確認していない勤務 → 勤務の確認    UnconfirmedList → ShiftCheckView
│   ├─ sheet  支給の見込み → 期間の詳細          PayPeriodsView → PayPeriodDetailView
│   ├─ sheet  パターンを作る / 編集 / 一覧       ShiftPartEditor, ShiftPartList
│   ├─ sheet  ヘルプ                          HelpSheet
│   └─ out    マップ / 電話 / メッセージ (system apps)
├─ カレンダー    CalendarScreen
│   ├─ sheet  シフトを追加 (方法を選ぶ) → 1件ずつ入力   ShiftAddChooser → ShiftEditorView
│   ├─ sheet  シフトの詳細                    ShiftEditorView
│   ├─ sheet  パターンを作る / 編集 / 一覧       ShiftPartEditor, ShiftPartList
│   ├─ sheet  曜日で入れる → 型を作る / 入れる    PatternListView → PatternEditorView / PatternApplyView
│   ├─ sheet  希望                            RequestEditorView
│   ├─ sheet  シフト表を取り込む → 候補を確認     ImportFlowView (chooser → review → CandidateEditor)
│   └─ sheet  ヘルプ
├─ 給料          IncomeScreen
│   ├─ sheet  目標を変える → 翌月以降にも使うか   GoalEditorSheet → confirmation dialog
│   ├─ sheet  支給の見込み → 期間の詳細          PayPeriodsView → PayPeriodDetailView
│   ├─ sheet  月の内訳                        PayBreakdownScreen
│   ├─ sheet  年収の壁                        WallsScreen
│   ├─ sheet  年収の目安                      IncomeGuideScreen
│   └─ sheet  ヘルプ
├─ 勤務先        WorkplaceDirectoryScreen
│   ├─ sheet  勤務先を登録 (3 steps) → 写真・リンクから読む   WorkplaceWizard → WorkplaceImportView
│   ├─ sheet  勤務先を編集                     WorkplaceEditorView
│   ├─ sheet  パターンを作る / 編集              ShiftPartEditor
│   ├─ sheet  メッセージを作る                  MessageComposerSheet
│   └─ sheet  ヘルプ
└─ 設定          SettingsScreen
    ├─ sheet  連絡メッセージのひな形             MessageTemplateEditor
    ├─ sheet  フォントのライセンス               LicenseSheet
    └─ out    設定アプリ (location / notifications)
Global: first-launch onboarding overlay, launch cover, import-router sheet, workplace-draft sheet (App Intents).
```

Removed screens (they only showed copied strings or did nothing): `PayBreakdownView`, `PayTermsNote`,
`PayScheduleNote`, `CalendarAccessView`, `LocationNoteView`, `AboutSheet` + speech bubble,
`RequestPlannerView` (“テキスト生成” stub), `HoursStockSheet` (“時間のストック” stub), the coach-mark
`GuideCard` overlays (replaced by `HelpSheet`), and the decorative non-working “マップで探す” field in the
wizard.

## 3. Tokens

### Colour (light only; `Theme` / `ThemeHex`)

| token | hex | use | contrast (verified) |
| --- | --- | --- | --- |
| `paper` | `#F4F2EC` | screen background | ink 16.2:1 |
| `surface` | `#FFFFFF` | cards, sheets’ cards | ink 18.1, ink2 7.4 |
| `sunken` | `#ECE9E1` | fields, inset chips, off chips | ink 14.9, ink2 6.1 |
| `ink` | `#161616` | primary text, selected chips | — |
| `ink2` | `#55555C` | secondary text, helper text | 6.6 on paper, 6.1 on sunken |
| `line` | `#E2DED5` | hairline separators (decorative) | — |
| `stroke` | `#8C887E` | control outlines (fields, secondary buttons) | 3.5 on surface, 3.2 on paper (≥3:1) |
| `signal` | `#C8F04B` | primary button fill, progress fill | ink on signal 13.8 |
| `signalInk` | `#3D5A0A` | links/accent text, switch “on” track, selected tab item | 7.0 on paper, 7.9 on surface, 6.5 vs off track |
| `danger` | `#B3261E` | errors, destructive text | 5.8 on paper, 5.4 on sunken |

Rules: lime is never a text colour on light surfaces. Switches use `signalInk` for “on” so the
state reads at a glance against the grey “off” track (fixes the old olive-on-black notification
toggles). Workplace colours pick ink or white text by luminance (`Color.readable`), tested ≥4.5:1.

### Type scale (Dynamic Type text styles via `AppFont`)

| token | style | weight | used for |
| --- | --- | --- | --- |
| `screenTitle` | `.title2` | bold | tab screen titles |
| `sectionTitle` | `.headline` | semibold | section headers (`isHeader` trait) |
| `rowTitle` | `.body` | semibold | card/row titles |
| `body` | `.body` | regular | text, field values |
| `label` | `.subheadline` | semibold | control labels |
| `helper` | `.footnote` | regular | helper text, captions (never smaller for content) |
| `badge` | `.caption` | bold | tiny badges (給, 希) only |

### Doto (dot-matrix) usage

`Doto-BlackRound.ttf` is the official Google Fonts Doto variable font instanced at `wght 900`,
`ROND 100` (all 320 glyph outlines verified identical to that instance). `OFL.txt` ships next to it
and is shown in Settings → フォントのライセンス.

- Only for numerals at display sizes: home clock (≈64 pt), live earnings (≈44 pt), shift time range
  on the home card (≈30 pt), money/time figures in hero tiles (≈28–34 pt), calendar month number.
- Glyph set is Latin only: strings rendered in Doto must use `0-9 : ¥ , . % / – +` and spaces. Kanji
  (年 月 日 時 分) stay in the system font next to the Doto run. (The old clock replaced `:` with
  `∶`, which Doto lacks, so it fell back to the system font.)
- Doto scales with Dynamic Type relative to `.largeTitle` but is capped (`DotoText`) and shrinks to
  fit one line; every Doto element has a spoken `accessibilityLabel` (e.g. 「14時05分」).

### Spacing, radii, sizes (`Space`, `Radius`)

- Spacing scale (4-pt grid): `xxs 4`, `xs 8`, `s 12`, `m 16`, `l 20`, `xl 24`, `xxl 32`.
  Screen gutter 16; card padding 16; gap between sections 24; between rows in a card 12.
- Radii: `control 12` (fields, small buttons), `card 20`, `hero 28` (landscape header),
  capsule for chips, pills and primary buttons.
- Minimum tap target 44×44; primary buttons are 52 pt tall.

### Motion (`Motion`)

`press` 0.16 s, `chip` 0.20 s snappy, `layout` 0.25 s snappy, `settle` spring 0.42 s. All animations go
through `Motion.allowed(_:reduce:)` and are dropped with Reduce Motion. The live earnings number uses
`.contentTransition(.numericText())` (also dropped with Reduce Motion).

## 4. Components (`DesignSystem.swift`)

| component | replaces | notes |
| --- | --- | --- |
| `ScreenHeader(title:, trailing:)` | wordmark + loose buttons | title is a header; trailing icon buttons are 44 pt with labels |
| `SectionHeader(_:, detail:)` | ad-hoc `Text` titles | `.isHeader`, optional helper line |
| `Card { }` | `surfaceCard`, many inline copies | white, radius 20, padding 16 |
| `NavRow(icon:, title:, subtitle:, value:)` | `settingsRow`, `rowLink`, `editorLink` | chevron, ≥52 pt, one tap target |
| `LabeledField(label:, text:, prompt:, helper:, error:)` | unlabeled `TextField`s | visible label above, helper below |
| `YenField` | `numberRow`, `yenField`, `field(number:)` | “¥” prefix, number pad, separator preview |
| `PickerRow(label:, selection:)` | unlabeled menu `Picker`s | label left, current value right (menu) |
| `ToggleRow(title:, helper:, isOn:)` | black notification card toggles | `signalInk` tint, helper shows what “on” does |
| `StepperRow(label:, value:)` | `Stepper("…\(x)")` | label and value in separate texts |
| `SegmentedRow(label:, selection:)` | unlabeled segmented pickers | visible label above |
| `PrimaryButton`, `SecondaryButton`, `DestructiveButton` | `LimeCapsuleButton`, `SecondaryPillButton`, red text | 52/44 pt, disabled state keeps 4.5:1 text |
| `QuickActionTile(title:, systemImage:, disabledHint:)` | “MAP/電話/メッセージ” capsules that did nothing | disabled shows the reason under the icon |
| `ChipButton` | `patternChip`, `kindChip`, segment buttons | selected = ink fill + white text, else white + stroke |
| `WeekdayPicker` | two copies with white-on-white text | labelled, `isSelected` trait |
| `DotoText` | `.font(.doto(n))` | capped Dynamic Type + spoken label |
| `ProgressBar` | three copies | track `sunken`, fill `signal`, value exposed to VoiceOver |
| `EmptyState` | ad-hoc empty texts | message + optional primary action |
| `LandscapeHeader(date:)` | `DayIllustration` gradient | original Canvas landscape, 4 times of day |
| `HelpSheet` | `GuideCard` overlays with copied tutorial text | rewritten copy per screen |

## 5. Screens — before → after

### ホーム (TodayScreen)
- **Before:** wordmark, week strip, a second hidden 1-pt clock text, Doto clock with a `∶` that fell
  back to the system font, shift card with a gradient “sky”, a number that was *not* earnings
  (`ScheduledPay`, the whole scheduled interval, ¥0 for most workplaces), three map/phone/message
  links only when data existed, to-dos as plain text, pay cards (black card with lime text), pattern
  chips.
- **After:** `LandscapeHeader` (original Canvas: sky, sun/moon, stars, clouds, hills, a small town and
  a road; dawn 5–9, day 9–16, dusk 16–19, night) with a paper plate holding the date and the Doto clock.
  Week strip (tap a day; swipe or arrows change the week; “今日に戻る” when away from today).
  Shift card per shift of the viewed day: workplace, status chip (勤務中 / あとN分で開始 / 終了),
  Doto time range, duration and break. **Live earnings** for the shift in progress
  (「いままでの稼ぎ」, ticks every second, progress toward the shift’s wage total, “終わりまで あと…”),
  “この勤務の見込み” before start, “この勤務の稼ぎ” after the end. Overnight shifts that started
  yesterday are found as “in progress”. Quick actions for the current workplace: 地図 (Apple Maps with
  the address or saved pin), 電話 (`tel:`), メッセージ (composer from the template → Messages); each is
  disabled with a visible reason (「住所が未登録です」「電話番号が未登録です」) and an “勤務先を編集” link.
  「今日のやること」 with real checkboxes (toggle done) and add. 「今月」 summary card with links to
  支給の見込み and 確認していない勤務. Pattern chips stay (“パターンで追加”).

### カレンダー (CalendarScreen)
- **Before:** wordmark, Doto month title with kanji falling back, black capsules with lime digits,
  “給/希” glyphs on top of digits, a long stack of pills (曜日でまとめて入れる, 希望を追加, 取り込む),
  shift list and pattern section interleaved.
- **After:** `ScreenHeader("カレンダー")` with add and help; workplace filter chips; month switcher
  (Doto “2026.11” with spoken 「2026年11月」, 44-pt chevrons, “今月” chip); white month card: weekday
  row, day cells (≥48 pt, system digits, today ring, selected ink fill, up to three workplace dots,
  給/希 badges below the digit); selected-day section (shifts, “この日に追加”, pattern chips);
  pattern section (place on picked days, undo, pending clashes); “ほかの追加方法” card with rows:
  曜日で入れる, 希望を追加, シフト表から取り込む.

### 給料 (IncomeScreen)
- **Before:** wordmark, Doto year with “年” in another font, black forecast card, a donut whose
  centre colour lime-on-white was unreadable, chevrons black on black, many same-looking cards.
- **After:** `ScreenHeader("給料")`; labelled 月/年 segmented control and period switcher; hero card
  (この期間に入る給料, Doto total, 働いた分 / これからの分, hours); goal card (edit, progress, remaining);
  by-workplace card (donut + rows); payday cards per workplace; links 内訳 / 年収の壁 / 年収の目安; a
  footnote on how months are counted. The ¥0-base bug in 支給の見込み is fixed (§6).

### 勤務先 (WorkplaceDirectoryScreen + editor + wizard)
- **Before:** black cards, decorative “MAP/電話/メッセージ” capsules that did nothing, the editor had two
  places for the closing day (links “締め日と支払日”, “土日の支払日” to stub screens *and* a card with
  unlabeled menu pickers), a “時給の履歴と時間帯” card whose wage history and bands only fed the broken
  `ScheduledPay`, seven unlabeled-looking percent steppers.
- **After (directory):** white cards: colour chip, name, wage and pay rhythm lines, working quick
  actions (same tiles as home), patterns (expand/collapse kept), 編集.
- **After (editor):** sections — 基本 (名前, 表示色, ジャンル), 連絡先と場所 (住所, 電話番号, 営業時間,
  公式サイト, “現在地から住所を入れる”), 給料 (時給/日給 segmented with label, amount, 交通費),
  **締め日と給料日 (the only place)** — 支払いの周期, then for 月払い 締め日 / 給料日の月 / 給料日 as
  labelled rows plus a plain-language summary and the next payday; 週払い 支払う曜日; 日払い note.
  割増 (深夜・休日・休日深夜・残業; each with an explicit mode: 割増率 or 金額), 休憩 (法定の目安 /
  この勤務先の決まり), 詳細 (打刻の丸め), メモ, 削除.
- **After (wizard):** three labelled steps (お店 → 時給と給料日 → よく入る時間) with “ステップ 1 / 3”, no
  fake search field, real labels on every field, photo/link import kept.

### 設定 (SettingsScreen)
- **Before:** the only black card (通知) with olive switches on black, “メッセージの文章” with no
  explanation, location “設定を開く” styled as plain text, an about row with a speech bubble.
- **After:** grouped white cards with section headers, in this order: 通知 (two `ToggleRow`s with what
  they do), 連絡メッセージ (row “メッセージのひな形” + one-line explanation + live preview; second so it is
  on screen without scrolling), カレンダーとリマインダー, シフトの重なり (移動にかかる時間), カレンダーの表示,
  給料の計算 (交通費, 目標), 新しい勤務先の初期値, 位置情報 (status chip + a real bordered button
  “設定アプリを開く” / “位置情報を許可する”), Siri とショートカット, このアプリについて (privacy line, version,
  フォントのライセンス).
- **Message template editor:** title 「連絡メッセージのひな形」. Explains that it is the text used by
  the ホーム/勤務先 “メッセージ” button and for late notices; token chips 「宛名」「理由」「遅れ」 insert
  `{宛名}` `{理由}` `{遅れ}`; a live preview with a sample (架空茶房 北窓, 電車の遅延のため, 15分ほど遅れます);
  “元に戻す”. The composer (from the quick action) picks reason and delay, shows the final text, and
  opens Messages with it (or copies it).

### Sheets and the rest
- **Shift editor:** labelled sections (勤務先, 日付, 時間, 休憩, 給料の調整, メモ, 行き先, コピー), large
  time buttons, the swipe-to-change-date fix and per-pattern breaks unchanged.
- **Add chooser:** four labelled ways (1件ずつ入力, パターンで追加, 履歴から追加, 文字で入力).
- **Pattern editor / list, weekday patterns:** labelled fields; weekday chips readable (were white on
  light grey); break mode with label.
- **Request editor:** labelled 種類 / 日付 / 勤務先 / 時間 / 休憩 / メモ; removes the meaningless
  “予定はありません” line and the dead “時間指定” text.
- **Import (shift table, workplace card/link):** labelled sources, readable candidate rows, `signalInk`
  checkmarks instead of lime-on-white.
- **Pay periods / breakdown / walls / guide:** shared cards and rows, labelled slip fields, amounts
  from the one pay engine (§6).
- **Attendance check:** original copy, labelled break stepper, primary “この内容で確定”.
- **To-dos:** checkboxes with `isSelected`, labelled add field.
- **Onboarding:** 3 pages, original copy, the landscape as the hero, page dots, skip.
- **Help:** one `HelpSheet` per tab with rewritten copy.

## 6. Pay engine and the live-earnings fix (summary; details in the PR)

- `PayRates` (new, pure): the per-minute rate used everywhere. Base = `hourlyWage`. Night/holiday
  minutes use the explicit wage when it is set, otherwise base × (100 + percent) / 100; an enabled
  premium with neither never drops below the base wage. Overtime adds the yen amount or the percent.
- `EarningsSoFar` (new, pure): finds the shift in progress (including one that started yesterday),
  and accrues paid minutes in proportion to elapsed time (break spread evenly), using `PayRates`, so
  the value at the end equals the shift’s wage in the monthly totals. Daily wage / custom pay accrue
  linearly. Unit tests cover ¥0 regressions, overnight lookup, breaks, monotonic ticks.
- `PayMath.quote` keeps its formula; only the night/holiday fallback above changes the result, and
  only for workplaces that had premium pay on with an empty amount (they used to be paid ¥0 for those
  minutes).

## 7. Copy and provenance

Rewritten in this app’s own words: tutorial/guide text, late-message section labels, attendance-check
copy, wizard step titles, clash/overlap phrases, “IN/OUT について”-style rows and the stub screens’
strings. Tests that pinned reverse-engineered layout constants (`ScreenInsets`, `SpacingTokens`) are
replaced by tests for the new tokens. Generic UI vocabulary (保存, 閉じる, 勤務先, カレンダー …) stays.

## 8. Data and migration

- No model field is renamed, retyped or removed. New settings live in `UserDefaults`
  (`@AppStorage`) or as new defaulted SwiftData properties only.
- A round-trip test writes a store with 「架空茶房 北窓」 data, reopens it with the current schema and
  checks every field the redesign reads.

## 9. Out of scope (this pass)

Dark mode, iPad layouts, a widget/Live Activity UI (the plan code stays untouched), dated wage
changes as a pay input (the stored history is kept but no longer shown), wage time-bands, and
per-weekday holiday percents (one percent for the chosen weekdays is editable). `ScheduledPay` and `LivePay` were not SwiftData models and no screen used them, so they
were removed. `InOutRecovered` stays; screens and the break rules still use it.

## 10. Numbers that change for existing data

- A premium that was switched on with no yen amount (what the old setup wizard stored for night
  pay) now pays the hourly wage plus its percent instead of ¥0 for those minutes.
- Overtime switched on with no yen amount now adds its percent (the wizard stored 25%).
- 支給の見込み now subtracts 天引 (negative adjustments) like the shift estimates already did, and
  月の内訳 uses the same engine (premiums included, transport only when the setting is on).
