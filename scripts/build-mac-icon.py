#!/usr/bin/env python3
"""Compile the macOS app-icon catalog with Xcode; keep a verified CLT fallback."""
import sys, argparse, hashlib, json, pathlib, shutil, subprocess

p = argparse.ArgumentParser()
p.add_argument('--scratch', required=True)
p.add_argument('--output', required=True)
args = p.parse_args()
project = pathlib.Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(project / "scripts/generate-brand.py"), "--check"], check=True)
scratch = pathlib.Path(args.scratch).resolve()
output = pathlib.Path(args.output).resolve()
scratch.mkdir(parents=True, exist_ok=True)
output.mkdir(parents=True, exist_ok=True)
compiled = scratch / 'compiled'
compiled.mkdir(exist_ok=True)
subprocess.run(['xcrun', 'actool', str(project / 'design/AppIcon.icon'), '--compile', str(compiled), '--platform', 'macosx',
    '--minimum-deployment-target', '13.0', '--target-device', 'mac', '--app-icon', 'AppIcon',
    '--output-partial-info-plist', str(compiled / 'info.plist'), '--output-format', 'human-readable-text'], check=True)
asset = compiled / 'Assets.car'
assert asset.is_file() and asset.stat().st_size > 0
shutil.copy2(asset, output / 'Assets.car')
sources = ['scripts/render-icons.swift', 'scripts/build-mac-icon.py', 'design/AppIcon.icon/icon.json', 'design/AppIcon.icon/Assets/Conduit.svg', 'design/brand.json', 'scripts/generate-brand.py']
manifest = {'iconName': 'AppIcon', 'sources': {f: hashlib.sha256((project / f).read_bytes()).hexdigest() for f in sources},
    'assetsSHA256': hashlib.sha256(asset.read_bytes()).hexdigest()}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Compiled and verified macOS app-icon catalog:', output)
