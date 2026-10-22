# SPDX-License-Identifier: MPL-2.0
# Runs only inside the packaged interpreter; generated game code stays on USB.
#
# Arabic Hesham integration (docs/arabic.md). Hesham's patch ships a Cemu PPC assembly patch
# (graphicPacks/ArabicNative/patch_arabic_native.asm) for the Windfall pirate door: the riddle is
# answered directly instead of typing a password on the game's letter keyboard, which an Arabic
# translation makes impossible to complete on an English console. A Cemu .asm patch cannot run in
# this port (the game's PowerPC code is translated ahead of time), so this preparation applies the
# same edits to the game code before translation, and verifies them in the translated output.
import os, sys, json, hashlib, builtins
sys.path[:0] = [os.path.join(wwhd_tools, 'recomp'), wwhd_tools]
for key in ['WWHD_RECOMP_CRLIVE','WWHD_RECOMP_LEAF','WWHD_RECOMP_NONLEAF','WWHD_RECOMP_GQR']:
    os.environ[key] = '1'
for key in ['WWHD_RECOMP_PLAIN','WWHD_RECOMP_CR_CHECK','WWHD_RECOMP_LEAF_POISON']:
    os.environ[key] = '0'
with open(wwhd_rpx, 'rb') as f:
    digest = hashlib.file_digest(f, 'sha256').hexdigest()
if digest != 'c4f0ab300542e0bfc462696850534e71db2ad02288a7eb55e5a4cd4062f16153':
    raise ValueError('Unsupported game. Use the original USA release of Wind Waker HD.')
import recomp

# ---- Arabic native patches (the UWP equivalent of Hesham's patch_arabic_native.asm) ----
# Each edit: address, the PowerPC word written there, the function that must contain the address
# (the USA build's own function layout, recomp's analysis), and what it does.
#   0x021A4784: b 0x021A47C4        (0x48000040)  chkPassward: skip the password comparison and
#                                                 jump straight to the riddle-answered path.
#   0x021A4920: li r9, 1            (0x39200001)  actionPassward2: the password-correct flag is set,
#                                                 so Link answers the riddle without a keyboard.
ARABIC_NATIVE_PATCHES = [
    (0x021A4784, 0x48000040, 0x021A45C8, 'chkPassward: the riddle is answered, no password comparison'),
    (0x021A4920, 0x39200001, 0x021A4808, 'actionPassward2: the password-correct flag'),
]

def apply_arabic_native(compiler):
    """Write Hesham's Windfall door edits into the analyzed game code (compiler.p), before
    translation. The game image is pinned by its SHA-256 above, the same USA build Hesham's
    Cemu patch targets, so the edited addresses are exactly his; the containing function is
    reported for the log (his .asm patch works the same way, on addresses alone). The edited
    addresses stay inside their own functions, so the function layout is unchanged."""
    program = compiler.p
    words = list(program.words)
    data = bytearray(program.text.data)
    for addr, word, expected_func, what in ARABIC_NATIVE_PATCHES:
        i = (addr - program.text_lo) >> 2
        if i < 0 or i >= len(words):
            raise ValueError('Arabic native patch: 0x%08X is outside the game code' % addr)
        start = compiler.func_of(addr)
        if start != expected_func:
            print('WARNING arabic-native: 0x%08X sits in 0x%08X, expected 0x%08X (%s); '
                  'the image is pinned, so the edit is applied at the address as Cemu does'
                  % (addr, start if start is not None else 0, expected_func, what))
        if words[i] == word:
            print('Arabic native patch already applied at 0x%08X (%s)' % (addr, what))
            continue
        words[i] = word
        data[4 * i:4 * i + 4] = word.to_bytes(4, 'big')
        print('Arabic native patch 0x%08X = 0x%08X (%s)' % (addr, word, what))
    program.words = tuple(words)
    program.text.data = bytes(data)

def verify_arabic_native(outdir):
    """The translated source carries each original instruction in a comment: require both edits."""
    wanted = ['%08X: %08X' % (addr, word) for addr, word, _, _ in ARABIC_NATIVE_PATCHES]
    found = {marker: False for marker in wanted}
    for name in os.listdir(outdir):
        if not (name.startswith('code_') and name.endswith('.c')):
            continue
        with open(os.path.join(outdir, name), encoding='utf-8', errors='replace') as f:
            for line in f:
                for marker in wanted:
                    if marker in line:
                        found[marker] = True
    missing = [marker for marker, ok in found.items() if not ok]
    if missing:
        raise ValueError('Arabic native patch missing from the translated game: ' + ', '.join('0x' + m for m in missing))
    for marker in wanted:
        print('PASS arabic-native: 0x%s in the translated game' % marker)

compiler = recomp.Recompiler(wwhd_rpx, mod_hooks=True)
apply_arabic_native(compiler)
original_open = builtins.open
def progress_open(path, *args, **kwargs):
    mode = args[0] if args else kwargs.get('mode', 'r')
    if isinstance(path, str) and 'w' in mode and os.path.basename(path).startswith('code_'):
        print('GENERATING ' + os.path.basename(path))
    return original_open(path, *args, **kwargs)
builtins.open = progress_open
try:
    compiler.run(wwhd_work, 30000)
finally:
    builtins.open = original_open
verify_arabic_native(wwhd_work)
units = [name for name in os.listdir(wwhd_work) if name.startswith('code_') and name.endswith('.c')]
if compiler.build.name != 'USA' or len(compiler.sorted_entries) != 39713 or len(units) != 78:
    raise ValueError('Translation does not match the supported runtime profile.')
print('PASS translation: USA, 39713 functions, 78 source units')
print('PASS arabic: Windfall pirate door riddle bypass (Hesham patch_arabic_native) applied')
