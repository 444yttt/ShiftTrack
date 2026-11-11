#!/usr/bin/env python3
"""Check recovered IN/OUT sites, then macOS-only tools when they exist.

The byte checks run anywhere. swift-demangle, dyld_info, and the iPhoneOS
SwiftUI.framework are expected on a GitHub macOS runner. This does not
reconstruct Swift source.
"""

from __future__ import annotations

import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "bin" / "IN-OUT"
SYMBOLS = ROOT / "symbols" / "swiftui-view.txt"

# File offsets of instructions identified on the original Mach-O.
MOVZ_W9_360 = (0xDA508, bytes.fromhex("092d8052"))
MOVZ_W9_45 = (0xDA514, bytes.fromhex("a9058052"))
MOVZ_W9_480 = (0xDA53C, bytes.fromhex("093c8052"))
MOVZ_W9_60 = (0xDA548, bytes.fromhex("89078052"))
CALENDAR_BODY_THUNK = 0x71B20
CALENDAR_BODY = 0x1000541DC
THUNK_VA = 0x100071B20


def fail(message: str) -> None:
    print("FAIL", message)
    sys.exit(1)


def main() -> None:
    data = BINARY.read_bytes()
    if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
        fail("not a little-endian 64-bit Mach-O")
    if b"ca-app-pub-" in data:
        fail("ad publisher id is still present")
    for off, expected in (MOVZ_W9_360, MOVZ_W9_45, MOVZ_W9_480, MOVZ_W9_60):
        got = data[off : off + 4]
        if got != expected:
            fail(f"initializer instruction at {off:#x} is {got.hex()}")
    print("byte-check statutory break initializer (360,45) and (480,60) ok")

    insn = struct.unpack_from("<I", data, CALENDAR_BODY_THUNK)[0]
    if insn >> 26 != 0b000101:
        fail(f"calendar body thunk is not B: {insn:#x}")
    imm = insn & 0x3FFFFFF
    if imm & (1 << 25):
        imm -= 1 << 26
    target = THUNK_VA + imm * 4
    if target != CALENDAR_BODY:
        fail(f"calendar body branch target {target:#x}")
    print(f"byte-check CalendarTabView.body thunk -> {target:#x} ok")

    demangle = shutil.which("swift-demangle")
    dyld_info = shutil.which("dyld_info")
    sdk = None
    if shutil.which("xcrun"):
        try:
            sdk = subprocess.check_output(
                ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True
            ).strip()
        except subprocess.CalledProcessError as exc:
            print("xcrun iphoneos sdk failed", exc.returncode)
    swiftui = Path(sdk) / "System/Library/Frameworks/SwiftUI.framework" if sdk else None
    print("swift-demangle", demangle or "absent")
    print("dyld_info", dyld_info or "absent")
    print("SwiftUI.framework", swiftui if swiftui and swiftui.exists() else "absent")

    if demangle:
        names = SYMBOLS.read_text(encoding="utf-8").split()
        out = subprocess.check_output([demangle, *names], text=True, errors="replace")
        print(out.strip())
        if "SwiftUI.View.body" not in out:
            fail("swift-demangle did not name SwiftUI.View.body")
        print("swift-demangle View.body ok")
    if dyld_info:
        proc = subprocess.run(
            [dyld_info, "-fixups", str(BINARY)],
            text=True,
            errors="replace",
            capture_output=True,
        )
        print("dyld_info exit", proc.returncode, "stdout_lines", len(proc.stdout.splitlines()))
        if proc.returncode != 0:
            print(proc.stderr[-500:])
            fail("dyld_info failed")
        if "bind" not in proc.stdout and "rebase" not in proc.stdout:
            fail("dyld_info printed no fixups")
        print("dyld_info fixups ok")
    if not (demangle and dyld_info and swiftui and swiftui.exists()):
        print("macos-only tools incomplete; byte checks passed")
        if sys.platform == "darwin":
            fail("this Darwin host is missing a required tool or SwiftUI.framework")
        print("non-darwin host: macOS portion not executed here")
        return
    print("macos verification passed")


if __name__ == "__main__":
    main()
