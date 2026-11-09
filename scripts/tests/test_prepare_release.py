"""Packaging boundaries that can be checked without native toolchains or secrets."""
import importlib.util
from argparse import Namespace
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

SPEC = importlib.util.spec_from_file_location('prepare_release', Path(__file__).resolve().parents[1] / 'prepare-release.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def metadata(self, apk_version='0.4.0', code='12'):
        info = {'CFBundleIdentifier': 'dev.conduit.mac', 'CFBundleIconName': 'AppIcon',
                'CFBundleVersion': '16', 'CFBundleShortVersionString': '0.4.0'}
        manifest = ET.fromstring('<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.conduit.bridge" android:versionName="0.4.0" android:versionCode="12"/>')
        badging = f"package: name='dev.conduit.bridge' versionCode='{code}' versionName='{apk_version}' platformBuildVersionName='15'"
        return info, manifest, badging

    def test_matching_app_and_source_versions(self):
        self.assertEqual(release.validate_versions(*self.metadata()), '0.4.0')

    def test_stale_apk_or_android_source_is_rejected(self):
        for version, code in [('0.3.4', '12'), ('0.4.0', '11')]:
            with self.subTest(version=version, code=code), self.assertRaises(ValueError):
                release.validate_versions(*self.metadata(version, code))
        info, manifest, badging = self.metadata()
        manifest.set(release.ANDROID + 'versionName', '0.4.1')
        with self.assertRaises(ValueError):
            release.validate_versions(info, manifest, badging)

    def test_unexpected_app_identity_is_rejected(self):
        info, manifest, badging = self.metadata()
        info['CFBundleIdentifier'] = 'example.other'
        with self.assertRaises(ValueError):
            release.validate_versions(info, manifest, badging)

    def test_source_archive_keeps_agent_configuration(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'source.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('conduit/LICENSE', 'MIT')
                archive.writestr('conduit/.agents/skills/conduit-release/SKILL.md', 'skill')
                archive.writestr('conduit/AGENTS.md', 'guidance')
            release.validate_source_archive(path)

    def test_private_or_generated_source_files_are_rejected(self):
        for name in ['work/development.p12', '.env.local', 'keys/release.keystore', 'conduit-signing.keychain-db', 'keychain-password', 'device.log', 'app.apk', '.git/config']:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / 'source.zip'
                with zipfile.ZipFile(path, 'w') as archive:
                    archive.writestr('conduit/LICENSE', 'MIT')
                    archive.writestr('conduit/' + name, 'private fixture')
                with self.assertRaises(ValueError):
                    release.validate_source_archive(path)

    def test_source_without_license_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'source.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('conduit/README.md', 'readme')
            with self.assertRaises(ValueError):
                release.validate_source_archive(path)

    def test_existing_artifacts_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'release'
            output.mkdir()
            sentinel = output / 'existing.apk'
            sentinel.write_bytes(b'existing release')
            args = Namespace(app=temporary, apk=temporary, output=str(output),
                             jdk=temporary, build_tools=temporary, previous_apk=None)
            with self.assertRaisesRegex(ValueError, 'Output already exists'):
                release.prepare(args)
            self.assertEqual(sentinel.read_bytes(), b'existing release')

    def test_dirty_source_is_rejected_before_native_tools_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'uncommitted.txt').write_text('new source')
            output = root / 'release'
            args = Namespace(app=temporary, apk=temporary, output=str(output),
                             jdk=temporary, build_tools=temporary, previous_apk=None)
            # run's default cwd points to the real project, so route git to this fixture.
            def fixture_run(*command):
                return subprocess.check_output(command, cwd=root, text=True).strip()
            with patch.object(release, 'run', fixture_run):
                with self.assertRaisesRegex(ValueError, 'Commit or resolve'):
                    release.prepare(args)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
