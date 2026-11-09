#!/usr/bin/env python3
"""Create a reusable local identity with user code-signing trust, outside the repo."""
import argparse
import json
import os
from pathlib import Path
import secrets
import tempfile
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
        password = secrets.token_urlsafe(32)
        password_file = directory / 'keychain-password'
        password_file.write_text(password + '\n')
        keychain = directory / 'conduit-signing.keychain-db'
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
        keychain.chmod(0o600)
        checked(['/usr/bin/security', 'add-trusted-cert', '-r', 'trustRoot', '-p', 'codeSign', '-k', keychain, directory / 'certificate.pem'], 'Trust local certificate for user code signing only')
        include_keychain(keychain)
        fingerprint = checked(['/usr/bin/openssl', 'x509', '-in', cert, '-noout', '-fingerprint', '-sha1'], 'Read public certificate fingerprint').split('=', 1)[1].replace(':', '')
        config_path.write_text(json.dumps({'schema': 1, 'identity': fingerprint, 'keychain': str(keychain), 'passwordFile': str(password_file)}, indent=2) + '\n')
        private_config(directory)
        print('Created persistent Conduit local signing identity:', fingerprint)
        print('Private material stored outside the repository:', directory)
    finally:
        os.umask(old_mask)


if __name__ == '__main__':
    main()
