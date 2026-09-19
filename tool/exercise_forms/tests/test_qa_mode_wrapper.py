"""Execute the shell wrapper with fake external commands, never real devices."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class WrapperTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.script = self.root / 'tool/verify_workout_lifecycle.sh'
        self.script.parent.mkdir()
        shutil.copyfile(ROOT / 'tool/verify_workout_lifecycle.sh', self.script)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'calls.jsonl'
        self.command('flutter', '''import json,os,sys
with open(os.environ['CALL_LOG'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1]=='build' and os.environ.get('FAIL_BUILD'): sys.exit(9)
''')
        self.command('xcrun', '''import json,os
print(json.dumps({'devices':{'test':[{'udid':'qa-id','name':os.environ.get('DEVICE_NAME','MUSCLEMORY QA test')}]}}))
''')
        self.command('adb', "import os\nprint(os.environ.get('DEVICE_NAME','musclemory_qa'))\n")
        android = self.root / 'android/platform-tools'
        android.mkdir(parents=True)
        shutil.copyfile(self.bin / 'adb', android / 'adb')
        (android / 'adb').chmod(0o755)
        self.env = {**os.environ, 'PATH': str(self.bin)+os.pathsep+os.environ['PATH'],
                    'FLUTTER_BIN':str(self.bin/'flutter'),'CALL_LOG':str(self.log),
                    'ANDROID_HOME':str(self.root/'android')}
        for key in ('FORM_QA_MODE','FORM_QA_IDS','FORM_QA_BASELINE','MUSCLEMORY_QA_TARGET','FAIL_BUILD','DEVICE_NAME'):
            self.env.pop(key, None)

    def command(self, name, content):
        path = self.bin / name
        path.write_text('#!'+sys.executable+'\n'+content)
        path.chmod(0o755)

    def run_script(self, platform='ios', **env):
        result = subprocess.run(['bash',str(self.script),platform,'qa-id'],
                                env={**self.env,**env},capture_output=True,text=True)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_ordinary_target_preserves_checks_and_build_guard(self):
        result, calls = self.run_script()
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual([c[0] for c in calls],['analyze','test','build','drive'])
        self.assertFalse(any('FORM_QA_' in arg for arg in calls[2]))
        self.assertIn('--keep-app-running',calls[-1])
        self.assertTrue(any(arg.startswith('--use-application-binary=') for arg in calls[-1]))

    def test_light_options_reach_each_platform_build_as_whole_arguments(self):
        for platform in ('ios','android'):
            with self.subTest(platform=platform):
                self.log.unlink(missing_ok=True)
                result,calls=self.run_script(platform,
                    MUSCLEMORY_QA_TARGET='integration_test/exercise_form_expansion_test.dart',
                    FORM_QA_MODE='light',FORM_QA_IDS='low_row,dy_row',FORM_QA_BASELINE='qa/full check reference')
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn('--dart-define=FORM_QA_MODE=light',calls[2])
                self.assertIn('--dart-define=FORM_QA_IDS=low_row,dy_row',calls[2])
                self.assertIn('--dart-define=FORM_QA_BASELINE=qa/full check reference',calls[2])

    def test_invalid_mode_fails_before_flutter(self):
        result,calls=self.run_script(FORM_QA_MODE='lite')
        self.assertEqual(result.returncode,2)
        self.assertEqual(calls,[])

    def test_light_missing_evidence_or_wrong_target_fails(self):
        for fields in ({'FORM_QA_MODE':'light'},
                       {'FORM_QA_MODE':'light','FORM_QA_IDS':'low_row','FORM_QA_BASELINE':'qa/ref'}):
            result,calls=self.run_script(**fields)
            self.assertEqual(result.returncode,2)
            self.assertEqual(calls,[])

    def test_user_device_is_rejected(self):
        for platform in ('ios','android'):
            result,calls=self.run_script(platform,DEVICE_NAME='User personal device')
            self.assertEqual(result.returncode,2)
            self.assertEqual(calls,[])

    def test_build_failure_never_drives_old_binary(self):
        result,calls=self.run_script(FAIL_BUILD='1')
        self.assertEqual(result.returncode,9)
        self.assertEqual([c[0] for c in calls],['analyze','test','build'])


if __name__ == '__main__':
    unittest.main()
