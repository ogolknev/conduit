import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('mac_signing', Path(__file__).resolve().parents[1] / 'mac_signing.py')
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def fixture(self, directory):
        directory = Path(directory)
        keychain, password = directory / 'signing.keychain-db', directory / 'keychain-password'
        for path in [keychain, password]:
            path.write_text('private fixture')
            path.chmod(0o600)
        config = {'schema': 1, 'identity': 'A' * 40, 'keychain': str(keychain), 'passwordFile': str(password)}
        (directory / 'identity.json').write_text(json.dumps(config))
        return config

    def test_existing_identity_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            expected = self.fixture(directory)
            self.assertEqual(signing.private_config(directory), expected)
            self.assertEqual(signing.private_config(directory)['identity'], expected['identity'])

    def test_missing_key_material_fails_instead_of_rotating(self):
        with tempfile.TemporaryDirectory() as directory:
            config = self.fixture(directory)
            Path(config['keychain']).unlink()
            with self.assertRaises(ValueError):
                signing.private_config(directory)
            self.assertTrue((Path(directory) / 'identity.json').exists())

    def test_world_readable_secret_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            config = self.fixture(directory)
            Path(config['passwordFile']).chmod(0o644)
            with self.assertRaises(ValueError):
                signing.private_config(directory)

    def test_command_failures_do_not_disclose_passwords(self):
        secret = 'private-test-password'
        result = subprocess.CompletedProcess([], 1, secret, secret)
        with patch.object(signing.subprocess, 'run', return_value=result):
            with self.assertRaises(RuntimeError) as caught:
                signing.checked(['security', 'unlock-keychain', '-p', secret], 'Unlock signing keychain')
        self.assertNotIn(secret, str(caught.exception))


if __name__ == '__main__':
    unittest.main()
