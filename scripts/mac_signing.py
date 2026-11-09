"""Persistent per-user signing identity for local macOS builds.

The local certificate is trusted only for code signing in the user profile.
Existing keychain contents and system/TLS trust are unchanged. Apple Developer ID
identities can instead be selected explicitly by the caller.
"""
import json
from pathlib import Path
import re
import shlex
import subprocess

DEFAULT_DIRECTORY = Path.home() / 'Library/Application Support/Conduit Development/Signing'


def private_config(directory):
    directory = Path(directory).expanduser().resolve()
    config = json.loads((directory / 'identity.json').read_text())
    if config.get('schema') != 1 or not re.fullmatch(r'[0-9A-Fa-f]{40}', config.get('identity', '')):
        raise ValueError('Invalid persistent signing configuration')
    for name in ['keychain', 'passwordFile']:
        path = Path(config[name])
        if not path.is_absolute() or not path.is_file():
            raise ValueError('Missing persistent signing material; restore it instead of rotating the identity')
        if path.stat().st_mode & 0o077:
            raise ValueError('Signing material must be accessible only to its owner')
    return config


def checked(command, description):
    # Commands may contain a dedicated keychain password: never expose argv on error.
    result = subprocess.run([str(x) for x in command], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(description + ' failed (exit ' + str(result.returncode) + ')')
    return result.stdout.strip()


def local_identity(directory):
    config = private_config(directory)
    password = Path(config['passwordFile']).read_text().strip()
    checked(['/usr/bin/security', 'unlock-keychain', '-p', password, config['keychain']], 'Unlock dedicated signing keychain')
    return config['identity'], config['keychain']


def include_keychain(keychain):
    existing = shlex.split(checked(['/usr/bin/security', 'list-keychains', '-d', 'user'], 'Read keychain search list'))
    if str(keychain) not in existing:
        checked(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *existing, keychain], 'Include dedicated signing keychain without replacing existing entries')


def designated_requirement(app):
    result = subprocess.run(['/usr/bin/codesign', '-d', '-r-', str(app)], capture_output=True, text=True, check=True)
    for line in (result.stdout + result.stderr).splitlines():
        normalized = line.lstrip('# ').strip()
        if normalized.startswith('designated =>'):
            return normalized
    raise ValueError('Signed app has no designated requirement')


def sign(app, identity, keychain=None):
    command = ['/usr/bin/codesign', '--force', '--deep', '--sign', identity]
    if keychain:
        command += ['--keychain', keychain]
    command.append(str(app))
    subprocess.run(command, check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    requirement = designated_requirement(app)
    if identity != '-' and 'cdhash ' in requirement:
        raise ValueError('Signing identity is still tied to one build hash')
    return requirement
