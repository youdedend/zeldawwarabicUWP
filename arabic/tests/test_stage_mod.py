# SPDX-License-Identifier: MPL-2.0
"""Staging (Method A) and overlay (Method B) with a synthetic archive: the mod package carries the
content files and the manifest, and never Hesham's Cemu .asm patch (the runtime applies it at
translation time)."""
import json
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import stage_mod  # noqa: E402

PACK_BYTES = b"\0SARCDUMMY-PACK" * 64
TITLE_BYTES = b"\0Yaz0DUMMY-SZS" * 64


class StageModTest(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)

    def make_zip(self) -> Path:
        path = self.work / "Arabic.Hesham.Zelda.WW.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Arabic_Hesham/content/Common/Pack/permanent_2d_UsEnglish.pack", PACK_BYTES)
            archive.writestr("Arabic_Hesham/content/Common/Layout/Title_00.szs", TITLE_BYTES)
            archive.writestr("Arabic_Hesham/graphicPacks/ArabicNative/patch_arabic_native.asm",
                             "0x021A4920 = li r9, 1\n")
            archive.writestr("Arabic_Hesham/README.txt", "Translation by Arabic Hesham")
        return path

    def source(self) -> Path:
        root = self.work / "Arabic_Hesham"
        (root / "content" / "Common" / "Pack").mkdir(parents=True)
        (root / "content" / "Common" / "Layout").mkdir(parents=True)
        (root / "graphicPacks" / "ArabicNative").mkdir(parents=True)
        (root / "content" / "Common" / "Pack" / "permanent_2d_UsEnglish.pack").write_bytes(PACK_BYTES)
        (root / "content" / "Common" / "Layout" / "Title_00.szs").write_bytes(TITLE_BYTES)
        (root / "graphicPacks" / "ArabicNative" / "patch_arabic_native.asm").write_text("0x021A4920 = li r9, 1\n")
        return root

    def test_extract_tree_finds_content(self):
        source = stage_mod.extract_tree(self.make_zip(), self.work / "extracted")
        self.assertEqual(source.name, "Arabic_Hesham")
        self.assertTrue((source / "content" / "Common" / "Pack" / "permanent_2d_UsEnglish.pack").is_file())

    def test_stage_builds_the_mod(self):
        target = stage_mod.stage(self.source(), self.work / "Mods", Path(__file__).parents[2] / "arabic" / "manifest.json")
        self.assertEqual(target, self.work / "Mods" / stage_mod.MOD_ID)
        manifest = json.loads((target / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["id"], "content.arabic_hesham")
        self.assertEqual(manifest["kind"], "content")
        self.assertEqual(manifest["game_id"], "wwhd")
        self.assertEqual(manifest["content_dir"], "content")
        self.assertEqual((target / "content" / "Common" / "Pack" / "permanent_2d_UsEnglish.pack").read_bytes(), PACK_BYTES)
        self.assertEqual((target / "content" / "Common" / "Layout" / "Title_00.szs").read_bytes(), TITLE_BYTES)
        staged = {p.relative_to(target).as_posix() for p in target.rglob("*") if p.is_file()}
        self.assertFalse(any(name.endswith(".asm") for name in staged), "no Cemu patch ships in the mod")

    def test_overlay_bakes_into_game_tree(self):
        game = self.work / "game"
        (game / "content" / "Common" / "Pack").mkdir(parents=True)
        (game / "content" / "Common" / "Layout").mkdir(parents=True)
        (game / "content" / "Common" / "Pack" / "permanent_2d_UsEnglish.pack").write_bytes(b"ORIGINAL")
        stage_mod.overlay(self.source(), game)
        self.assertEqual((game / "content" / "Common" / "Pack" / "permanent_2d_UsEnglish.pack").read_bytes(), PACK_BYTES)
        self.assertEqual((game / "content" / "Common" / "Layout" / "Title_00.szs").read_bytes(), TITLE_BYTES)

    def test_overlay_rejects_non_game_tree(self):
        with self.assertRaises(SystemExit):
            stage_mod.overlay(self.source(), self.work / "not-a-game")

    def test_stage_rejects_unknown_pack(self):
        root = self.work / "bad"
        (root / "content" / "Common" / "Pack").mkdir(parents=True)
        (root / "content" / "Common" / "Pack" / "some_random.pack").write_bytes(b"x")
        with self.assertRaises(SystemExit):
            stage_mod.stage(root, self.work / "Mods", Path(__file__).parents[2] / "arabic" / "manifest.json")


if __name__ == "__main__":
    unittest.main()
