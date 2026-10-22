# SPDX-License-Identifier: MPL-2.0
"""The pinned download metadata: the official release URL and the exact archive fingerprint."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fetch_patch  # noqa: E402


class FetchMetaTest(unittest.TestCase):
    def test_pinned_url_and_fingerprint(self):
        self.assertEqual(fetch_patch.EXPECTED_SHA256,
                         "21b83f9b05a493764bfe38ed93fd3995f65533d551c33f3a02ed1feeb5554001")
        self.assertEqual(fetch_patch.EXPECTED_SIZE, 10585918)
        self.assertIn("7akeem0/Arabic_Hesham-Downloads", fetch_patch.DOWNLOAD_URL)
        self.assertIn("releases/download/localizations-2026-09/Arabic.Hesham.Zelda.WW.zip",
                      fetch_patch.DOWNLOAD_URL)
        self.assertIn("arabichesham.com", fetch_patch.PAGE_URL)

    def test_verify_rejects_wrong_size(self):
        import tempfile, os
        handle, path = tempfile.mkstemp(suffix=".zip")
        with os.fdopen(handle, "wb") as f:
            f.write(b"PK\3\4 too small")
        self.addCleanup(os.remove, path)
        with self.assertRaises(SystemExit):
            fetch_patch.verify(Path(path))


if __name__ == "__main__":
    unittest.main()
