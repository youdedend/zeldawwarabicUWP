# Arabic Hesham's Cemu graphic-pack patch for The Wind Waker HD (USA), kept for reference.
#
# Source: Arabic.Hesham.Zelda.WW.zip -> graphicPacks/ArabicNative/patch_arabic_native.asm
#         (https://arabichesham.com/games/the-legend-of-zelda-the-wind-waker-hd)
#
# Cemu applies these PowerPC edits to the loaded game code. This port translates the game's PowerPC
# ahead of time, so a Cemu .asm patch cannot run here; platforms/uwp-game/prepare_game.py applies the
# same edits to the game image before translation (ARABIC_NATIVE_PATCHES), and verifies them in the
# translated output. The lines below are the patch as Hesham ships it; keep this file in sync when
# updating the translation archive.

# Windfall pirate door: no password keyboard, Link answers the riddle.
# (The game's letter keyboard cannot show the Arabic password of the translation.)
0x021A4920 = li r9, 1          # actionPassward2 (0x021A4808): the password-correct flag
0x021A4784 = b 0x021A47C4      # chkPassward (0x021A45C8): jump straight to the riddle-answered path

# Encodings used by prepare_game.py (PowerPC AssemblerRef, opcode 18 b / opcode 14 addi):
#   0x021A4784: b 0x021A47C4  -> LI = 0x021A47C4 - 0x021A4784 = 0x40, AA=0, LK=0 -> 0x48000040
#   0x021A4920: li r9, 1      -> addi r9, r0, 1 -> 0x39200001
