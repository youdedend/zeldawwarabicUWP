# SPDX-License-Identifier: MPL-2.0
"""Synthetic SARC / Yaz0 / BFFNT fixtures run through arabic/verify_pack.py's parsers, mirroring
runtime/src/overlay/game_font.cpp. Covers the activation rule (base letters OR presentation
forms, the runtime's hardened rule) and the shaping-coverage report for a Hesham-style font
(forms-heavy, few base letters)."""
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import verify_pack  # noqa: E402


def yaz0_compress_literal(data: bytes) -> bytes:
    """A valid (if naive) Yaz0 stream: groups of literals, one flag byte each."""
    out = bytearray(b"Yaz0" + struct.pack(">I", len(data)) + b"\0" * 8)  # the 16-byte header
    for start in range(0, len(data), 8):
        group = data[start:start + 8]
        out.append(0x100 - (1 << (8 - len(group))))  # one flag bit 1 per literal present
        out.extend(group)
    return bytes(out)


def sarc(files: dict) -> bytes:
    """A minimal big-endian SARC archive {name: data}, laid out as game_font.cpp reads it."""
    names = bytearray()
    entries = bytearray()
    blob = bytearray()
    layout = {}
    for name, payload in files.items():
        while len(names) % 4:
            names.append(0)
        while len(blob) % 4:
            blob.append(0)
        layout[name] = (len(names) // 4, len(blob), len(blob) + len(payload))
        names.extend(name.encode() + b"\0")
        blob.extend(payload)
    while len(blob) % 4:
        blob.append(0)
    for name in files:
        name_off, begin, end = layout[name]
        entries.extend(struct.pack(">IIII", 0, 0x01000000 | name_off, begin, end))
    names_start = 0x20 + len(entries) + 8
    data_off = (names_start + len(names) + 3) & ~3
    header = struct.pack(">4sHHIIHH", b"SARC", 0x14, 0xFEFF, data_off + len(blob), data_off, 0x0100, 0)
    sfat = struct.pack(">4sHHI", b"SFAT", 0x0C, len(files), 0x0131)
    sfnt = struct.pack(">4sHH", b"SFNT", 0x08, 0x0202)
    pad_after_names = data_off - names_start - len(names)
    return header + sfat + entries + sfnt + bytes(names) + b"\0" * pad_after_names + bytes(blob)


def bffnt(cmap_chain: list) -> bytes:
    """A big-endian BFFNT font whose CMAP chain is [(first, last, method, payload)].

    Layout per parse_bffnt: header 0x14 (BOM at +4, header size at +6), FINF 0x30 at 0x14 with
    the CMAP pointer at +0x1C (pointing at a block's body, i.e. magic+8), then CMAP blocks of
    magic+size / first / last / method / pad / next / payload."""
    header_size, finf_size = 0x14, 0x30
    pointers = []
    cursor = header_size + finf_size
    for _first, _last, _method, payload in cmap_chain:
        pointers.append(cursor + 8)  # the value the chain (or FINF) holds for this block
        cursor += 8 + 12 + len(payload)  # magic+size, first/last/method/pad+next, payload
    fixed = []
    for k, (first, last, method, payload) in enumerate(cmap_chain):
        nxt = pointers[k + 1] if k + 1 < len(pointers) else 0
        body = struct.pack(">HHH2xI", first, last, method, nxt) + payload
        fixed.append(struct.pack(">4sI", b"CMAP", 8 + len(body)) + body)
    chain = b"".join(fixed)
    total = header_size + finf_size + len(chain)
    header = struct.pack(">4sHHIIHH", b"FFNT", 0xFEFF, header_size, total, len(cmap_chain) + 2, 0x18, 0)
    finf = bytearray(b"FINF" + struct.pack(">I", finf_size) + b"\0" * (finf_size - 8))
    struct.pack_into(">I", finf, 0x1C, pointers[0])
    return header + bytes(finf) + chain


def cmap_direct(first: int, last: int) -> bytes:
    return b"\0" * ((last - first + 1) * 2)  # method 0: the parser maps the whole run


def cmap_table(codes: list) -> bytes:
    first, last = min(codes), max(codes)
    index = {c: k + 1 for k, c in enumerate(sorted(codes))}
    return b"".join(struct.pack(">H", index.get(c, 0xFFFF)) for c in range(first, last + 1))


def pack_file(font_codes: set) -> str:
    """A .pack the way the runtime reads Hesham's: SARC -> Yaz0 -> SARC -> BFFNT."""
    base = sorted(c for c in font_codes if 0x0621 <= c <= 0x064A)
    forms = sorted(c for c in font_codes if 0xFE70 <= c <= 0xFEFC)
    chain = []
    if base:
        chain.append((min(base), max(base), 0, cmap_direct(min(base), max(base))))
    if forms:
        chain.append((min(forms), max(forms), 1, cmap_table(forms)))
    font = bffnt(chain)
    inner = sarc({"CKingMsg.bffnt": font})
    outer = sarc({"CKingMsg_bffnt.szs": yaz0_compress_literal(inner)})
    handle, path = tempfile.mkstemp(suffix=".pack")
    with os.fdopen(handle, "wb") as f:
        f.write(outer)
    return path


class PackParserTest(unittest.TestCase):
    def pack(self, codes: set) -> set:
        path = pack_file(codes)
        self.addCleanup(os.remove, path)
        return verify_pack.pack_font(Path(path))

    def test_yaz0_roundtrip_literals(self):
        payload = bytes(range(256)) * 3
        self.assertEqual(verify_pack.yaz0(yaz0_compress_literal(payload)), payload)
        self.assertEqual(verify_pack.yaz0(payload), payload)  # not compressed: returned as is

    def test_yaz0_back_reference(self):
        # 'abcdefgh' as literals, then a compressed group copying it (length 8, distance 8).
        stream = bytearray(b"Yaz0" + struct.pack(">I", 16) + b"\0" * 8)
        stream.append(0xFF)
        stream.extend(b"abcdefgh")
        stream.append(0x00)
        stream.extend(bytes([(8 - 2) << 4 | ((8 - 1) >> 8) & 0xF, (8 - 1) & 0xFF]))
        self.assertEqual(verify_pack.yaz0(bytes(stream)), b"abcdefghabcdefgh")

    def test_sarc_find(self):
        inner = sarc({"CKingMsg.bffnt": b"FONTDATA"})
        hit = verify_pack.sarc_find(inner, "CKingMsg.bffnt")
        self.assertEqual(inner[hit[0]:hit[0] + hit[1]], b"FONTDATA")
        self.assertIsNone(verify_pack.sarc_find(inner, "missing.bin"))
        self.assertIsNone(verify_pack.sarc_find(b"NOPE", "x"))

    def test_bffnt_direct_run(self):
        glyphs = verify_pack.bffnt_glyphs(bffnt([(0x0621, 0x064A, 0, cmap_direct(0x0621, 0x064A))]))
        self.assertEqual(glyphs, set(range(0x0621, 0x064B)))

    def test_bffnt_table_and_chain(self):
        forms = list(range(0xFE70, 0xFE8E))
        glyphs = verify_pack.bffnt_glyphs(bffnt([
            (0x0621, 0x0624, 0, cmap_direct(0x0621, 0x0624)),
            (0xFE70, 0xFE8D, 1, cmap_table(forms)),
        ]))
        self.assertTrue(set(range(0x0621, 0x0625)) <= glyphs)
        self.assertEqual(glyphs & set(range(0xFE70, 0xFE8E)), set(forms))

    def test_bffnt_table_holes(self):
        # Method 1 with 0xFFFF holes: only the codes with indices are mapped.
        glyphs = verify_pack.bffnt_glyphs(bffnt([(0xFE70, 0xFE73, 1, struct.pack(">4H", 1, 0xFFFF, 2, 0xFFFF))]))
        self.assertEqual(glyphs, {0xFE70, 0xFE72})

    def test_bffnt_scan(self):
        payload = struct.pack(">H", 2) + struct.pack(">HH", 0x064B, 1) + struct.pack(">HH", 0x0652, 2)
        glyphs = verify_pack.bffnt_glyphs(bffnt([(0x064B, 0x0652, 2, payload)]))
        self.assertEqual(glyphs, {0x064B, 0x0652})

    def test_pack_font_full_pipeline(self):
        codes = set(range(0x0621, 0x064B))
        self.assertEqual(self.pack(codes), codes)

    def test_forms_only_font_activates(self):
        # A Hesham-style font: presentation forms, only a handful of base letters.
        codes = set(range(0x0621, 0x0626)) | set(range(0xFE70, 0xFE8E))
        glyphs = self.pack(codes)
        self.assertGreaterEqual(sum(1 for c in glyphs if 0xFE70 <= c <= 0xFEFC), 20)
        self.assertTrue(verify_pack.report(glyphs))

    def test_small_font_stays_off(self):
        glyphs = self.pack(set(range(0x0621, 0x0626)))  # 5 letters: decorative, not a translation
        self.assertFalse(verify_pack.report(glyphs))

    def test_letter_forms_match_the_runtime_table(self):
        from verify_pack import letter_forms
        for letter in (0x0628, 0x0641, 0x064A):
            self.assertEqual(len(letter_forms(letter)), 4, "dual-joining letters have four forms")
        self.assertEqual(letter_forms(0x0621), [0xFE80])
        self.assertEqual(letter_forms(0x0622), [0xFE81, 0xFE82])
        self.assertEqual(letter_forms(0x0649), [0xFEEF, 0xFEF0, 0xFBE8, 0xFBE9])
        self.assertEqual(letter_forms(0x0640), [])  # tatweel has none
        self.assertEqual(letter_forms(0x06CC), [0xFBFC, 0xFBFD, 0xFBFE, 0xFBFF])  # Forms-A extra


if __name__ == "__main__":
    unittest.main()
