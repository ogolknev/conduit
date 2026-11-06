#!/usr/bin/env python3
import sys, argparse, hashlib, json, os, pathlib, plistlib, shutil, subprocess, zipfile

p = argparse.ArgumentParser()
p.add_argument('--scratch', required=True)
p.add_argument('--platform-tools', required=True)
p.add_argument('--server', required=True)
p.add_argument('--apk', required=True)
p.add_argument('--output', required=True)
args = p.parse_args()
project = pathlib.Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(project / "scripts/generate-brand.py"), "--check"], check=True)
subprocess.run([sys.executable, str(project / "scripts/generate-localizations.py"), "--check"], check=True)
scratch = pathlib.Path(args.scratch).resolve(); scratch.mkdir(parents=True, exist_ok=True)
cache = scratch / 'module-cache'; cache.mkdir(exist_ok=True)
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(cache), SWIFTPM_MODULECACHE_OVERRIDE=str(cache))
cmd = ['swift', 'build', '-c', 'release', '--package-path', str(project), '--scratch-path', str(scratch / 'build'),
    '--cache-path', str(scratch / 'cache'), '--config-path', str(scratch / 'config'), '--security-path', str(scratch / 'security'), '--disable-sandbox']
subprocess.run(cmd, check=True, env=env)
app = pathlib.Path(args.output).resolve()
macos = app / 'Contents/MacOS'; resources = app / 'Contents/Resources'
macos.mkdir(parents=True, exist_ok=True); resources.mkdir(parents=True, exist_ok=True)
shutil.copy2(scratch / 'build/release/Conduit', macos / 'Conduit')
adb_dir = resources / 'platform-tools'; adb_dir.mkdir(exist_ok=True)
for name in ['adb', 'NOTICE.txt', 'source.properties']:
    source = pathlib.Path(args.platform_tools) / name
    if source.exists(): shutil.copy2(source, adb_dir / name)
shutil.copy2(args.server, resources / 'scrcpy-server-v5.0.1')
shutil.copy2(args.apk, resources / 'conduit-companion.apk')
with zipfile.ZipFile(resources / 'conduit-companion.zip', 'w', zipfile.ZIP_DEFLATED) as z: z.write(args.apk, 'conduit-companion.apk')
for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
    shutil.copy2(project / name, resources / name)
shutil.copytree(project / 'licenses', resources / 'licenses', dirs_exist_ok=True)
icons = scratch / 'Conduit.iconset'
if icons.exists(): shutil.rmtree(icons)
subprocess.run(['swift', str(project / 'scripts/render-icons.swift'), str(icons)], check=True, env=env)
subprocess.run(['/usr/bin/iconutil', '-c', 'icns', str(icons), '-o', str(resources / 'AppIcon.icns')], check=True)
# A compiled catalog supplies the app icon on modern macOS notification surfaces.
# Keep a checked-in build so Command Line Tools alone can package the app.
icon_catalog = project / 'design/mac-icon'
manifest = json.loads((icon_catalog / 'manifest.json').read_text())
assert manifest['iconName'] == 'AppIcon'
for name in ['scripts/render-icons.swift', 'scripts/build-mac-icon.py', 'design/AppIcon.icon/icon.json', 'design/AppIcon.icon/Assets/Conduit.svg', 'design/brand.json', 'scripts/generate-brand.py']:
    assert hashlib.sha256((project / name).read_bytes()).hexdigest() == manifest['sources'][name], 'Recompile the macOS icon catalog after changing its sources'
assert hashlib.sha256((icon_catalog / 'Assets.car').read_bytes()).hexdigest() == manifest['assetsSHA256'], 'Invalid macOS icon catalog'
shutil.copy2(icon_catalog / 'Assets.car', resources / 'Assets.car')
# Remove the old resource name when rebuilding an existing bundle.
(resources / 'Conduit.icns').unlink(missing_ok=True)
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleName':'Conduit', 'CFBundleDisplayName':'Conduit', 'CFBundleExecutable':'Conduit',
        'CFBundleIdentifier':'dev.conduit.mac', 'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'0.4.0',
        'CFBundleVersion':'16', 'CFBundleIconFile':'AppIcon', 'CFBundleIconName':'AppIcon',
        'CFBundleInfoDictionaryVersion':'6.0', 'CFBundleSupportedPlatforms':['MacOSX'], 'CFBundleDevelopmentRegion':'en', 'CFBundleLocalizations':['en','ru'], 'CFBundleSignature':'????', 'LSMinimumSystemVersion':'13.0', 'NSHighResolutionCapable':True,
        'NSPrincipalClass':'NSApplication', 'NSBluetoothAlwaysUsageDescription':'Conduit connects this Mac to Android for clipboard, notifications and files over Bluetooth.'}, f)
for language in ['en', 'ru']:
    shutil.copytree(project / 'localization' / (language + '.lproj'), resources / (language + '.lproj'), dirs_exist_ok=True)
(app / 'Contents/PkgInfo').write_bytes(b'APPL????')
subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
print('Built:', app)
