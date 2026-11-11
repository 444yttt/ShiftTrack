# Ghidra 11.4 の疑似コード

これはデコンパイラ出力である。元の Swift ソースでも、ShiftTrack へ入れた再実装でもない。`-noanalysis` で関数範囲だけ切っているので、型はほぼ `undefined` のままである。

## 0x1001e6a70

`ShiftPart` の witness から到達した 84 バイト。小文字列の即値は `name`、`address`、`location` で、コンパイラが生成した CodingKey である。

```c
undefined1 [16] fn_1001e6a70(void)
{
  char tag = *unaff_x20;
  ulong word = 0x73736572646461;       /* "address" */
  if (tag != 1) word = 0x6e6f697461636f6c; /* "location" */
  ulong name = 0x656d616e;             /* "name" */
  if (tag != 0) name = word;
  return (undefined1 [16]){ name, /* discriminator */ };
}
```

## 0x10015df8c

604 バイト。給料の丸め説明の文字列を ADRP+ADD で参照する。疑似コードに `udiv` や丸めは無く、スタックへ値をコピーして別関数へ渡す。画面用の関数である。

## 0x1001b960c

2520 バイト。「開始と終了を異なる時刻にしてください」を参照する。デコンパイラが残した呼び出し名は `SwiftUI.State.wrappedValue` の getter で、比較は次の 1 行である。

```c
uStack_1b0._4_4_ = (uint)(lVar3 != alStack_f0[0]);
```

前後は SwiftUI の view 構築で、シフトの保存式にはなっていない。
