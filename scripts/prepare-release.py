#!/usr/bin/env python3
"""Verify existing native builds and package a clean committed source revision.

This command creates local artifacts only. It never installs apps, creates tags or
publishes a GitHub release. See docs/RELEASING.md for the complete release procedure.
"""
import argparse
import hashlib
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'


def run(*command, cwd=ROOT):
    return subprocess.check_output([str(part) for part in command], cwd=cwd,
                                   stderr=subprocess.STDOUT, text=True).strip()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def validate_versions(info, manifest, badging):
    version = info.get('CFBundleShortVersionString', '')
    require(re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version), 'Invalid Mac version')
    require(info.get('CFBundleIdentifier') == 'dev.conduit.mac', 'Unexpected Mac bundle ID')
    require(info.get('CFBundleIconName') == 'AppIcon', 'Missing Mac icon identity')
    require(str(info.get('CFBundleVersion', '')).isdigit(), 'Invalid Mac build number')
    require(manifest.get('package') == 'dev.conduit.bridge', 'Unexpected source Android package')
    package = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    require(package is not None, 'Unable to read APK identity')
    require(package.group(1) == 'dev.conduit.bridge', 'Unexpected APK package')
    require(version == manifest.get(ANDROID + 'versionName') == package.group(3), 'Mac, source and APK versions differ')
    require(manifest.get(ANDROID + 'versionCode') == package.group(2), 'Source and APK version codes differ')
    return version


def validate_source_archive(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require('conduit/LICENSE' in names, 'Source archive is missing LICENSE')
        for name in names:
            parts = Path(name).parts
            unsafe = any(part in {'.git', 'work', '.build', '.swiftpm', 'dist', 'outputs', '__pycache__'} for part in parts)
            leaf = Path(name).name
            unsafe |= leaf == '.env' or (leaf.startswith('.env.') and leaf != '.env.example')
            unsafe |= leaf in {'local.properties', 'keychain-password'} or leaf.endswith(('.p12', '.pfx', '.jks', '.keystore', '.key', '.pem', '.keychain', '.keychain-db', '.log', '.apk', '.aar', '.jar'))
            require(not unsafe, f'Unexpected private/generated file in source archive: {name}')


def verify_apk(apk, jdk, build_tools):
    output = run(jdk / 'bin/java', '-jar', build_tools / 'lib/apksigner.jar',
                 'verify', '--verbose', '--print-certs', apk)
    certificates = re.findall(r'^Signer #\d+ certificate SHA-256 digest: (\w+)$', output, re.M)
    require(len(certificates) == 1, 'Expected one verified APK signer')
    return certificates[0]


def prepare(args):
    app, apk, output, jdk, tools = [Path(value).resolve() for value in
                                  (args.app, args.apk, args.output, args.jdk, args.build_tools)]
    require(not output.exists(), 'Output already exists; choose a new release directory')
    require(not run('git', 'status', '--porcelain'), 'Commit or resolve source changes before packaging')
    commit = run('git', 'rev-parse', 'HEAD')
    resources = app / 'Contents/Resources'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    manifest = ET.parse(ROOT / 'android/AndroidManifest.xml').getroot()
    version = validate_versions(info, manifest, run(tools / 'aapt2', 'dump', 'badging', apk))
    signer = verify_apk(apk, jdk, tools)
    if args.previous_apk:
        require(signer == verify_apk(Path(args.previous_apk).resolve(), jdk, tools), 'APK signing key changed')
    require((resources / 'conduit-companion.apk').read_bytes() == apk.read_bytes(), 'Mac embeds a different APK')
    with zipfile.ZipFile(resources / 'conduit-companion.zip') as archive:
        require(archive.read('conduit-companion.apk') == apk.read_bytes(), 'Mac companion ZIP differs')
    with zipfile.ZipFile(apk) as archive:
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'licenses/scrcpy-APACHE-2.0.txt', 'licenses/shizuku-MIT.txt']:
            require(archive.read('assets/' + name) == (ROOT / name).read_bytes(), f'APK license mismatch: {name}')
        require(archive.read('assets/scrcpy-server-v5.0.1') == (resources / 'scrcpy-server-v5.0.1').read_bytes(), 'Servers differ')
    for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'licenses/scrcpy-APACHE-2.0.txt', 'licenses/shizuku-MIT.txt', 'licenses/platform-tools-NOTICE.txt']:
        require((resources / name).read_bytes() == (ROOT / name).read_bytes(), f'Mac license mismatch: {name}')
    require((resources / 'Assets.car').read_bytes() == (ROOT / 'design/mac-icon/Assets.car').read_bytes(), 'Mac icon catalog differs from source')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    print(run(app / 'Contents/MacOS/Conduit', '--smoke-test'), flush=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.conduit-release-', dir=output.parent) as temporary:
        stage = Path(temporary)
        mac = stage / f'Conduit-{version}-Bluetooth-macOS.zip'
        standalone = stage / f'conduit-companion-{version}.apk'
        android = stage / f'Conduit-{version}-Android.zip'
        source = stage / 'Conduit-source.zip'
        run('/usr/bin/ditto', '-c', '-k', '--norsrc', '--keepParent', app, mac)
        shutil.copy2(apk, standalone)
        with zipfile.ZipFile(android, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.write(apk, 'conduit-companion.apk')
        run('git', 'archive', '--format=zip', '--prefix=conduit/', commit, '-o', source)
        validate_source_archive(source)
        with zipfile.ZipFile(mac) as archive:
            require(archive.read(app.name + '/Contents/Resources/conduit-companion.apk') == apk.read_bytes(), 'Packaged Mac APK differs')
        files = [mac, standalone, android, source]
        (stage / 'SHA256SUMS.txt').write_text(''.join(f'{digest(path)}  {path.name}\n' for path in files))
        # Publish the directory only after all local verification succeeds.
        stage.rename(output)
    print(f'Prepared Conduit {version} from {commit} in {output}')
    print(f'Mac build {info["CFBundleVersion"]}; Android code {manifest.get(ANDROID + "versionCode")}; APK signer SHA-256 {signer}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['app', 'apk', 'output', 'jdk', 'build-tools']:
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--previous-apk', help='Previous release APK; require the same verified signing certificate')
    args = parser.parse_args()
    try:
        prepare(args)
    except subprocess.CalledProcessError as error:
        print(f'Command failed: {error.cmd}\n{error.output}', file=sys.stderr)
        return 1
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, ET.ParseError) as error:
        print(f'Release preparation failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
