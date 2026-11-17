#!/usr/bin/env python3
"""Create a reusable local identity with user code-signing trust, outside the repo."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import tempfile
import uuid
from mac_signing import DEFAULT_DIRECTORY, checked, private_config, include_keychain


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', default=str(DEFAULT_DIRECTORY))
    args = parser.parse_args()
    directory = Path(args.directory).expanduser().resolve()
    config_path = directory / 'identity.json'
    if config_path.exists():
        config = private_config(directory)
        include_keychain(config['keychain'])
        print('Reusing Conduit local signing identity:', config['identity'])
        return
    # A partial setup must be repaired deliberately, never silently replace the key.
    if directory.exists() and any(directory.iterdir()):
        raise SystemExit('Signing directory is not empty. Restore the existing identity before continuing.')
    directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    directory.chmod(0o700)
    old_mask = os.umask(0o077)
    try:
        password = secrets.token_hex(32)
        password_file = directory / 'keychain-password'
        password_file.write_text(password + '\n')
        keychain = directory / ('conduit-signing-' + uuid.uuid4().hex[:12] + '.keychain-db')
        with tempfile.TemporaryDirectory(prefix='setup-', dir=directory) as temporary:
            temp = Path(temporary)
            config = temp / 'certificate.cnf'
            config.write_text('''[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = Conduit Local Development
[signing]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
''')
            key, cert, p12 = temp / 'signing.key', directory / 'certificate.pem', temp / 'identity.p12'
            checked(['/usr/bin/openssl', 'req', '-new', '-newkey', 'rsa:3072', '-nodes', '-x509', '-sha256', '-days', '3650', '-config', config, '-keyout', key, '-out', cert], 'Create local signing certificate')
            checked(['/usr/bin/openssl', 'pkcs12', '-export', '-inkey', key, '-in', cert, '-name', 'Conduit Local Development', '-passout', 'file:' + str(password_file), '-out', p12], 'Prepare signing import')
            checked(['/usr/bin/security', 'create-keychain', '-p', password, keychain], 'Create dedicated keychain')
            checked(['/usr/bin/security', 'unlock-keychain', '-p', password, keychain], 'Unlock dedicated keychain')
            checked(['/usr/bin/security', 'import', p12, '-k', keychain, '-P', password, '-T', '/usr/bin/codesign'], 'Import signing identity')
            checked(['/usr/bin/security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain], 'Authorize codesign for this dedicated keychain')
            # Keep an encrypted export so a future keychain-password problem can
            # be repaired without replacing the certificate and app identity.
            shutil.copy2(p12, directory / 'identity-backup.p12')
            (directory / 'identity-backup.p12').chmod(0o600)
        keychain.chmod(0o600)
        checked(['/usr/bin/security', 'add-trusted-cert', '-r', 'trustRoot', '-p', 'codeSign', '-k', keychain, directory / 'certificate.pem'], 'Trust local certificate for user code signing only')
        include_keychain(keychain)
        fingerprint = checked(['/usr/bin/openssl', 'x509', '-in', cert, '-noout', '-fingerprint', '-sha1'], 'Read public certificate fingerprint').split('=', 1)[1].replace(':', '')
        config_path.write_text(json.dumps({'schema': 1, 'identity': fingerprint, 'keychain': str(keychain), 'passwordFile': str(password_file)}, indent=2) + '\n')
        private_config(directory)
        checked(['/usr/bin/security', 'lock-keychain', keychain], 'Lock new signing keychain for verification')
        stored_password = password_file.read_text().strip()
        checked(['/usr/bin/security', 'unlock-keychain', '-p', stored_password, keychain], 'Verify stored signing password after locking')
        checked(['/usr/bin/openssl', 'pkcs12', '-in', directory / 'identity-backup.p12', '-passin', 'file:' + str(password_file), '-noout'], 'Verify encrypted identity backup')
        backup = directory.parent / 'Signing Backups' / (fingerprint[:12] + '-' + uuid.uuid4().hex[:8])
        backup.mkdir(parents=True, mode=0o700)
        for name in ['identity-backup.p12', 'certificate.pem', 'keychain-password']:
            shutil.copy2(directory / name, backup / name)
            (backup / name).chmod(0o600)
        print('Created persistent Conduit local signing identity:', fingerprint)
        print('Private material stored outside the repository:', directory)
        print('Verified encrypted identity backup:', backup)
    finally:
        os.umask(old_mask)


if __name__ == '__main__':
    main()
