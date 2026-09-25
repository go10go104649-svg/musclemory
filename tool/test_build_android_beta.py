"""Build script regression checks; no Flutter build or private signing key used."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / 'build_android_beta.sh'

class BuildConfigTests(unittest.TestCase):
    def run_script(self, config):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            signing = root / 'signing.properties'
            signing.touch()
            config_path = root / 'config.json'
            if config is not None:
                config_path.write_text(json.dumps(config))
            log = root / 'calls'
            flutter = root / 'flutter'
            flutter.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$BUILD_TEST_LOG"\n')
            flutter.chmod(0o700)
            env = dict(os.environ, SETKEEP_SIGNING_PROPERTIES=str(signing),
                SETKEEP_SUPABASE_CONFIG=str(config_path), FLUTTER_BIN=str(flutter),
                BUILD_TEST_LOG=str(log), BUILD_PLAY_BUNDLE='1')
            result = subprocess.run(['bash', str(SCRIPT)], env=env, capture_output=True)
            return result.returncode, log.read_text() if log.exists() else '', str(config_path)

    def test_missing_or_incomplete_config_stops_build(self):
        for config in [None, {}, {'SUPABASE_URL': 'https://example.invalid'}]:
            code, calls, _ = self.run_script(config)
            self.assertNotEqual(code, 0)
            self.assertEqual(calls, '')

    def test_both_artifacts_receive_config_file(self):
        code, calls, path = self.run_script({'SUPABASE_URL': 'https://example.invalid', 'SUPABASE_PUBLISHABLE_KEY': 'test-only'})
        self.assertEqual(code, 0)
        self.assertIn('build apk --release --dart-define-from-file=' + path, calls)
        self.assertIn('build appbundle --release --dart-define-from-file=' + path, calls)

if __name__ == '__main__':
    unittest.main()
