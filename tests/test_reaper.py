"""Tests inside a real, headless REAPER (tests/reaper/*_test.lua).

They run where tools/reaper/install.sh has installed REAPER on Linux, which the
cloud setup does; elsewhere they are skipped.
"""
from pathlib import Path
import os
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
PREFIX = Path(os.environ.get('FME_REAPER_PREFIX', '/opt/fme-reaper'))


@unittest.skipUnless(sys.platform.startswith('linux') and (PREFIX / 'REAPER/reaper').exists(),
                     'headless REAPER not installed (tools/reaper/install.sh)')
class InReaper(unittest.TestCase):
    def test_reaper_suite(self):
        result = subprocess.run(['bash', str(ROOT / 'tools/reaper/reaper.sh'), 'test'],
                                capture_output=True, text=True, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
