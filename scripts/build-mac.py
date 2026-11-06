#!/usr/bin/env python3
import argparse, os, pathlib, plistlib, shutil, subprocess, zipfile

p = argparse.ArgumentParser()
p.add_argument('--scratch', required=True)
p.add_argument('--platform-tools', required=True)
p.add_argument('--server', required=True)
p.add_argument('--apk', required=True)
p.add_argument('--output', required=True)
args = p.parse_args()
project = pathlib.Path(__file__).resolve().parents[1]
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
if (project / 'THIRD_PARTY_NOTICES.md').exists(): shutil.copy2(project / 'THIRD_PARTY_NOTICES.md', resources)
if (project / 'licenses').is_dir(): shutil.copytree(project / 'licenses', resources / 'licenses', dirs_exist_ok=True)
icons = scratch / 'Conduit.iconset'
if icons.exists(): shutil.rmtree(icons)
subprocess.run(['swift', str(project / 'scripts/render-icons.swift'), str(icons)], check=True, env=env)
subprocess.run(['/usr/bin/iconutil', '-c', 'icns', str(icons), '-o', str(resources / 'Conduit.icns')], check=True)
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleName':'Conduit', 'CFBundleDisplayName':'Conduit', 'CFBundleExecutable':'Conduit',
        'CFBundleIdentifier':'dev.conduit.mac', 'CFBundlePackageType':'APPL', 'CFBundleShortVersionString':'0.3.0',
        'CFBundleVersion':'11', 'CFBundleIconFile':'Conduit.icns', 'LSMinimumSystemVersion':'13.0', 'NSHighResolutionCapable':True,
        'NSPrincipalClass':'NSApplication', 'NSBluetoothAlwaysUsageDescription':'Conduit соединяет Mac и Android для передачи буфера, уведомлений и файлов по Bluetooth.'}, f)
subprocess.run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
print('Built:', app)
