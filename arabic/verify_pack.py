#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify Arabic Hesham's language pack for the WWHD-UWP Arabic runtime.

Reads the staged pack exactly the way the runtime does when the game opens it
(runtime/src/overlay/game_font.cpp: SARC -> CKingMsg_bffnt.szs -> Yaz0 -> SARC -> CKingMsg.bffnt
-> CMAP) and reports the font's Arabic coverage: base letters, presentation Forms-A/B, lam-alef
ligatures, harakat. Then it applies the runtime's activation rule and the shaping engine's
fallback rule, so you know before playing what the runtime will decide and how much of the
alphabet renders in its connected forms.

Usage:
    python3 verify_pack.py Mods/content.arabic_hesham/content/Common/Pack/permanent_2d_UsEnglish.pack
"""
import struct
import sys
from pathlib import Path


def read_u16(data: bytes, at: int, big: bool) -> int:
    return struct.unpack_from(">H" if big else "<H", data, at)[0]


def read_u32(data: bytes, at: int, big: bool) -> int:
    return struct.unpack_from(">I" if big else "<I", data, at)[0]


def yaz0(data: bytes) -> bytes:
    if len(data) < 16 or data[:4] != b"Yaz0":
        return data
    size = read_u32(data, 4, True)
    out = bytearray()
    i = 16
    while len(out) < size and i < len(data):
        code = data[i]
        i += 1
        for bit in range(8):
            if len(out) >= size:
                break
            if code & (0x80 >> bit):
                out.append(data[i])
                i += 1
                continue
            dist = ((data[i] & 0x0F) << 8 | data[i + 1]) + 1
            length = data[i] >> 4
            i += 2
            if length == 0:
                length = data[i] + 0x12
                i += 1
            else:
                length += 2
            if dist > len(out):
                raise ValueError("corrupt Yaz0 stream")
            for _ in range(length):
                if len(out) >= size:
                    break
                out.append(out[-dist])
    return bytes(out)


def sarc_find(data: bytes, name: str):
    """Offset and length of `name` in a SARC archive, or None (game_font.cpp sarc_find)."""
    if len(data) < 0x20 or data[:4] != b"SARC":
        return None
    big = data[6] == 0xFE
    data_off = read_u32(data, 0x0C, big)
    count = read_u16(data, 0x1A, big)
    names = 0x20 + count * 16 + 8  # after the SFAT entries and the SFNT header
    for k in range(count):
        entry = 0x20 + k * 16
        attr = read_u32(data, entry + 4, big)
        begin, end = read_u32(data, entry + 8, big), read_u32(data, entry + 12, big)
        at = names + (attr & 0xFFFF) * 4
        if at + len(name) + 1 > len(data):
            continue
        if data[at:at + len(name) + 1] == name.encode() + b"\0":
            if end < begin or data_off + begin > len(data) or data_off + end > len(data):
                return None
            return data_off + begin, end - begin
    return None


def bffnt_glyphs(data: bytes) -> set:
    """The codepoints a BFFNT font maps (game_font.cpp parse_bffnt: CMAP methods 0, 1, 2).

    CMAP block, as the runtime reads it: magic + size (8 bytes), first @+8, last @+10, method
    @+12, next block @+16, payload @+20. The FINF's CMAP pointer is the block's body (magic+8).
    """
    if len(data) < 0x14 or data[:4] not in (b"FFNT", b"CFNT"):
        raise ValueError("not a BFFNT/CFNT font")
    big = data[4] == 0xFE
    finf = read_u16(data, 6, big)  # the header's size: FINF follows
    if finf + 32 > len(data) or data[finf:finf + 4] != b"FINF":
        raise ValueError("no FINF block")
    cmap = read_u32(data, finf + 0x1C, big)
    out = set()
    guard = 0
    while cmap >= 8 and guard < 4096:
        guard += 1
        block = cmap - 8
        if block + 20 > len(data) or data[block:block + 4] != b"CMAP":
            raise ValueError("bad CMAP block")
        first, last, method = (read_u16(data, block + 8, big), read_u16(data, block + 10, big),
                               read_u16(data, block + 12, big))
        payload = block + 20
        if method == 0:  # direct: a run of codes
            out.update(range(first, last + 1))
        elif method == 1:  # table: one glyph index per code, 0xFFFF for none
            for c in range(first, last + 1):
                at = payload + (c - first) * 2
                if at + 2 <= len(data) and read_u16(data, at, big) != 0xFFFF:
                    out.add(c)
        elif method == 2:  # scan: count, then (code, index) pairs
            count = read_u16(data, payload, big)
            for k in range(count):
                at = payload + 2 + k * 4
                if at + 4 <= len(data):
                    out.add(read_u16(data, at, big))
        else:
            raise ValueError(f"unsupported CMAP method {method}")
        cmap = read_u32(data, block + 16, big)  # the next block
    return out


# The Arabic letters' presentation forms, as the shaping engine maps them
# (runtime/src/rtl_text.cpp kLetters/kExtra): letter -> (joining, first form, form count).
# Joining: D dual (isolated, final, initial, medial), R right (isolated, final), U isolated only.
ARABIC_LETTERS = {
    0x0621: ("U", 0xFE80, 1), 0x0622: ("R", 0xFE81, 2), 0x0623: ("R", 0xFE83, 2),
    0x0624: ("R", 0xFE85, 2), 0x0625: ("R", 0xFE87, 2), 0x0626: ("D", 0xFE89, 4),
    0x0627: ("R", 0xFE8D, 2), 0x0628: ("D", 0xFE8F, 4), 0x0629: ("R", 0xFE93, 2),
    0x062A: ("D", 0xFE95, 4), 0x062B: ("D", 0xFE99, 4), 0x062C: ("D", 0xFE9D, 4),
    0x062D: ("D", 0xFEA1, 4), 0x062E: ("D", 0xFEA5, 4), 0x062F: ("R", 0xFEA9, 2),
    0x0630: ("R", 0xFEAB, 2), 0x0631: ("R", 0xFEAD, 2), 0x0632: ("R", 0xFEAF, 2),
    0x0633: ("D", 0xFEB1, 4), 0x0634: ("D", 0xFEB5, 4), 0x0635: ("D", 0xFEB9, 4),
    0x0636: ("D", 0xFEBD, 4), 0x0637: ("D", 0xFEC1, 4), 0x0638: ("D", 0xFEC5, 4),
    0x0639: ("D", 0xFEC9, 4), 0x063A: ("D", 0xFECD, 4), 0x0640: ("C", 0, 0),
    0x0641: ("D", 0xFED1, 4), 0x0642: ("D", 0xFED5, 4), 0x0643: ("D", 0xFED9, 4),
    0x0644: ("D", 0xFEDD, 4), 0x0645: ("D", 0xFEE1, 4), 0x0646: ("D", 0xFEE5, 4),
    0x0647: ("D", 0xFEE9, 4), 0x0648: ("R", 0xFEED, 2), 0x0649: ("D", 0xFEEF, 2),
    0x064A: ("D", 0xFEF1, 4),
}
EXTRA_LETTERS = {  # Presentation Forms-A entries the shaping engine also uses
    0x0671: ("R", 0xFB50, 2), 0x067E: ("D", 0xFB56, 4), 0x0686: ("D", 0xFB7A, 4),
    0x0698: ("R", 0xFB8A, 2), 0x06A9: ("D", 0xFB8E, 4), 0x06AF: ("D", 0xFB92, 4),
    0x06CC: ("D", 0xFBFC, 4),
}


def letter_forms(cp: int):
    entry = ARABIC_LETTERS.get(cp) or EXTRA_LETTERS.get(cp)
    if not entry:
        return []
    join, first, count = entry
    if not first:
        return []
    forms = list(range(first, first + count))
    if cp == 0x0649:  # alef maksura: initial/medial live in Forms-A
        forms += [0xFBE8, 0xFBE9]
    return forms


def pack_font(pack_path: Path) -> set:
    raw = pack_path.read_bytes()
    hit = sarc_find(raw, "CKingMsg_bffnt.szs")
    if not hit:
        raise ValueError("no CKingMsg_bffnt.szs in the pack")
    inner = yaz0(raw[hit[0]:hit[0] + hit[1]])
    hit = sarc_find(inner, "CKingMsg.bffnt")
    if not hit:
        raise ValueError("no CKingMsg.bffnt in the font archive")
    return bffnt_glyphs(inner[hit[0]:hit[0] + hit[1]])


def report(glyphs: set) -> bool:
    arabic = sum(1 for c in glyphs if 0x0621 <= c <= 0x064A)
    hebrew = sum(1 for c in glyphs if 0x05D0 <= c <= 0x05EA)
    forms = sum(1 for c in glyphs if 0xFE70 <= c <= 0xFEFC)
    ligatures = sum(1 for c in glyphs if 0xFEF5 <= c <= 0xFEFC)
    harakat = sum(1 for c in glyphs if 0x064B <= c <= 0x0652)
    print(f"Arabic base letters (0621-064A): {arabic}")
    print(f"Hebrew letters (05D0-05EA):      {hebrew}")
    print(f"Presentation Forms-B glyphs:     {forms}")
    print(f"Lam-Alef ligatures (FEF5-FEFC):  {ligatures}")
    print(f"Harakat (064B-0652):             {harakat}")
    active = arabic >= 20 or hebrew >= 20 or forms >= 20
    print(f"Runtime activation (>=20 of any): {'ON' if active else 'OFF'}")
    if not active:
        return False
    # The shaping engine draws a letter's connected form only when the font has it and falls back
    # to the base letter otherwise (rtl_text.cpp shape_at). A base letter with no form at all
    # would render disconnected wherever it joins.
    bare = [hex(c) for c in sorted(glyphs & set(ARABIC_LETTERS))
            if ARABIC_LETTERS[c][0] != "U" and not any(f in glyphs for f in letter_forms(c))]
    if bare:
        print(f"Letters with no presentation form at all: {len(bare)} (they render disconnected): "
              + ", ".join(bare))
    else:
        print("Shaping coverage: every mapped joining letter has presentation forms available")
    return True


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    pack = Path(sys.argv[1])
    if not pack.is_file():
        raise SystemExit(f"FAIL {pack}: no such file")
    glyphs = pack_font(pack)
    print(f"{pack}: {len(glyphs)} mapped codepoints")
    ok = report(glyphs)
    print("PASS" if ok else "FAIL: the runtime would keep right-to-left text off for this font")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
