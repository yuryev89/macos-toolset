import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/release.py'

class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.info = {'CFBundleIdentifier': 'local.macostoolset.app', 'CFBundleShortVersionString': '1.1.0', 'CFBundleVersion': '2', 'LSMinimumSystemVersion': '13.0'}
        (self.root / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        (self.root / 'CHANGELOG.md').write_text('# Changelog\n\n## [1.1.0] - 2026-10-13\n\nInitial public release.\n\n## [1.0.0] - 2026-09-07\n\nPrevious local version.\n')
    def tearDown(self):
        self.temp.cleanup()
    def run_release(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), '--root', str(self.root), *args], capture_output=True, text=True)
    def test_matching_stable_tag_reads_metadata(self):
        r = self.run_release('metadata', '--tag', 'v1.1.0')
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertEqual(data['version'], '1.1.0')
        self.assertEqual(data['build'], '2')
    def test_mismatch_and_prerelease_fail_without_mutating_version(self):
        before = (self.root / 'Info.plist').read_bytes()
        for tag in ['v1.2.0', 'v1.1.0-rc.1', '1.1.0', 'v01.1.0', 'v1.1.0\n']:
            r = self.run_release('metadata', '--tag', tag)
            self.assertNotEqual(r.returncode, 0, tag)
        self.assertEqual((self.root / 'Info.plist').read_bytes(), before)
    def test_notes_do_not_include_another_version(self):
        r = self.run_release('notes', '1.1.0')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('Initial public release.', r.stdout)
        self.assertNotIn('Previous local version.', r.stdout)
        self.assertNotEqual(self.run_release('notes', '1.2.0').returncode, 0)
    def test_bump_increments_build_and_preserves_identity(self):
        r = self.run_release('bump', '1.1.1')
        self.assertEqual(r.returncode, 0, r.stderr)
        info = plistlib.loads((self.root / 'Info.plist').read_bytes())
        self.assertEqual(info['CFBundleShortVersionString'], '1.1.1')
        self.assertEqual(info['CFBundleVersion'], '3')
        self.assertEqual(info['CFBundleIdentifier'], 'local.macostoolset.app')
        for v in ['1.1.1', '1.0.0', '1.2.0-beta', '01.2.0']:
            self.assertNotEqual(self.run_release('bump', v).returncode, 0, v)
    def test_checksums_match_known_bytes_and_reject_missing_inputs(self):
        artifact = self.root / 'macOS-Toolset-1.1.0-arm64.zip'
        artifact.write_bytes(b'hello')
        r = self.run_release('checksums', str(artifact))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824  macOS-Toolset-1.1.0-arm64.zip\n')
        self.assertNotEqual(self.run_release('checksums', str(self.root / 'missing.zip')).returncode, 0)
        self.assertNotEqual(self.run_release('checksums', str(artifact), str(artifact)).returncode, 0)

if __name__ == '__main__':
    unittest.main()
