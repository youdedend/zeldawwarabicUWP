# SPDX-License-Identifier: MPL-2.0
"""The Windfall door patches as shipped in platforms/uwp-game/prepare_game.py.

prepare_game.py runs only inside the console's packaged Python, so the test extracts its patch
section with the AST and runs it against a fake recompiler: a program whose .text starts at the
game's base address, and func_of() reporting the USA build's function layout around the door code
(wwhd_chkPassward 0x021A45C8, wwhd_actionPassward2 0x021A4808, per the runtime's bindings).
"""
import ast
import os
import sys
import tempfile
import unittest
from pathlib import Path

TEXT_LO = 0x02000000
CHK_PASSWARD, ACTION_PASSWARD2 = 0x021A45C8, 0x021A4808
DOOR_BRANCH, DOOR_FLAG = 0x021A4784, 0x021A4920


def load_prepare_section():
    """Exec the constants and functions of prepare_game.py's Arabic section without its top-level
    preparation flow (which needs the game image and the packaged interpreter)."""
    source = Path(__file__).resolve().parents[2] / "platforms" / "uwp-game" / "prepare_game.py"
    tree = ast.parse(source.read_text(encoding="utf-8"))
    wanted = []
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
                getattr(t, "id", "") == "ARABIC_NATIVE_PATCHES" for t in node.targets):
            wanted.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name in ("apply_arabic_native", "verify_arabic_native"):
            wanted.append(node)
    if len(wanted) != 3:
        raise AssertionError(f"prepare_game.py: expected the patch table and both functions, found {len(wanted)}")
    namespace = {"os": os, "print": print}
    exec(compile(ast.Module(body=wanted, type_ignores=[]), str(source), "exec"), namespace)
    return namespace["ARABIC_NATIVE_PATCHES"], namespace["apply_arabic_native"], namespace["verify_arabic_native"]


class FakeSection:
    def __init__(self, size):
        self.data = bytes(size)  # like recomp's Rpx section


class FakeProgram:
    def __init__(self, n_words=0x80000):  # 2 MiB of text: past the door code
        self.text_lo = TEXT_LO
        self.words = tuple(0x60000000 for _ in range(n_words))  # nop fill
        self.text = FakeSection(n_words * 4)


class FakeCompiler:
    def __init__(self):
        self.p = FakeProgram()

    def func_of(self, addr):
        if CHK_PASSWARD <= addr < ACTION_PASSWARD2:
            return CHK_PASSWARD
        if ACTION_PASSWARD2 <= addr < 0x021A4A30:
            return ACTION_PASSWARD2
        return 0x02000000


class NativePatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        patches, apply_fn, verify_fn = load_prepare_section()
        cls.patches = patches
        cls.apply = staticmethod(apply_fn)
        cls.verify = staticmethod(verify_fn)

    def test_patch_table_is_the_door_patch(self):
        table = {addr: (word, func) for addr, word, func, _ in self.patches}
        self.assertEqual(table[DOOR_BRANCH], (0x48000040, CHK_PASSWARD), "b 0x021A47C4 in chkPassward")
        self.assertEqual(table[DOOR_FLAG], (0x39200001, ACTION_PASSWARD2), "li r9, 1 in actionPassward2")

    def test_encodings_match_hesham_asm(self):
        # b 0x021A47C4 from 0x021A4784: opcode 18, LI = 0x40, AA=0, LK=0
        li = 0x021A47C4 - DOOR_BRANCH
        self.assertEqual((18 << 26) | li, 0x48000040)
        # li r9, 1: addi r9, r0, 1 -> opcode 14, rD=9, rA=0, SIMM=1
        self.assertEqual((14 << 26) | (9 << 21) | 1, 0x39200001)

    def test_apply_writes_words_and_data(self):
        compiler = FakeCompiler()
        self.apply(compiler)
        for addr, word, _, _ in self.patches:
            i = (addr - TEXT_LO) >> 2
            self.assertEqual(compiler.p.words[i], word)
            self.assertEqual(int.from_bytes(compiler.p.text.data[4 * i:4 * i + 4], "big"), word)

    def test_apply_is_idempotent(self):
        compiler = FakeCompiler()
        self.apply(compiler)
        once = compiler.p.words
        self.apply(compiler)
        self.assertEqual(once, compiler.p.words)

    def test_apply_rejects_out_of_text_address(self):
        compiler = FakeCompiler()
        compiler.p.text_lo = 0x03000000  # a program whose text does not cover the door
        with self.assertRaises(ValueError):
            self.apply(compiler)

    def test_verify_accepts_translated_markers(self):
        compiler = FakeCompiler()
        self.apply(compiler)
        with tempfile.TemporaryDirectory() as out:
            with open(os.path.join(out, "code_021.c"), "w") as f:
                for addr, word, _, _ in self.patches:
                    f.write("    c->r[9] = 1u; /* %08X: %08X */\n" % (addr, word))
            self.verify(out)  # must not raise
            os.remove(os.path.join(out, "code_021.c"))
            with open(os.path.join(out, "code_021.c"), "w") as f:
                f.write("    c->r[9] = 2u; /* 021A4784: 60000000 */\n")
            with self.assertRaises(ValueError):
                self.verify(out)


if __name__ == "__main__":
    unittest.main()
