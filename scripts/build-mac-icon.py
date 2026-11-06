#!/usr/bin/env python3
"""Compile the macOS app-icon catalog with Xcode; keep a verified CLT fallback."""
import argparse, hashlib, json, os, pathlib, shutil, subprocess

p = argparse.ArgumentParser()
p.add_argument('--scratch', required=True)
p.add_argument('--output', required=True)
args = p.parse_args()
project = pathlib.Path(__file__).resolve().parents[1]
scratch = pathlib.Path(args.scratch).resolve()
output = pathlib.Path(args.output).resolve()
scratch.mkdir(parents=True, exist_ok=True)
output.mkdir(parents=True, exist_ok=True)
iconset = scratch / 'AppIcon.iconset'
cache = scratch / 'module-cache'
cache.mkdir(exist_ok=True)
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(cache))
subprocess.run(['swift', str(project / 'scripts/render-icons.swift'), str(iconset)], check=True, env=env)
catalog = scratch / 'Icons.xcassets'
appicon = catalog / 'AppIcon.appiconset'
appicon.mkdir(parents=True, exist_ok=True)
images = []
for points in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        name = f'icon_{points}x{points}' + ('@2x' if scale == 2 else '') + '.png'
        shutil.copy2(iconset / name, appicon / name)
        images.append({'idiom': 'mac', 'size': f'{points}x{points}', 'scale': f'{scale}x', 'filename': name})
(appicon / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'version': 1, 'author': 'xcode'}}, indent=2))
(catalog / 'Contents.json').write_text(json.dumps({'info': {'version': 1, 'author': 'xcode'}}))
compiled = scratch / 'compiled'
compiled.mkdir(exist_ok=True)
subprocess.run(['xcrun', 'actool', str(catalog), '--compile', str(compiled), '--platform', 'macosx',
    '--minimum-deployment-target', '13.0', '--target-device', 'mac', '--app-icon', 'AppIcon',
    '--output-partial-info-plist', str(compiled / 'info.plist'), '--output-format', 'human-readable-text'], check=True)
asset = compiled / 'Assets.car'
assert asset.is_file() and asset.stat().st_size > 0
shutil.copy2(asset, output / 'Assets.car')
sources = ['scripts/render-icons.swift', 'scripts/build-mac-icon.py']
manifest = {'iconName': 'AppIcon', 'sources': {f: hashlib.sha256((project / f).read_bytes()).hexdigest() for f in sources},
    'assetsSHA256': hashlib.sha256(asset.read_bytes()).hexdigest()}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Compiled and verified macOS app-icon catalog:', output)
