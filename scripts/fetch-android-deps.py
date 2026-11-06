#!/usr/bin/env python3
"""Download pinned, unmodified Shizuku API artifacts. No system installation."""
import argparse, hashlib, pathlib, subprocess, zipfile
p = argparse.ArgumentParser(); p.add_argument('--output', required=True); args = p.parse_args()
root = pathlib.Path(args.output).resolve(); root.mkdir(parents=True, exist_ok=True)
digests = {
    'api': '4def9bde498ef8626614c2fc5db9af4749c86f16f6c33e3f5658d35e70bab59b',
    'provider': 'b0f18cd9812464ec171c53cac93a819fe411718a3965c311f01eb4de265381b3',
    'aidl': '33fe7191cdd69fcb66d649264f3b0c47acb2f3d6343afc05b98dbbff6f221963',
    'shared': '4659642c9339be0a26e9c65bb8648f7ad6d8f4a465f557993ccbc78802381635'
}
def fetch(url, target, digest):
    if not target.exists(): subprocess.run(['curl', '-fsSL', '--retry', '2', '--max-time', '60', url, '-o', str(target)], check=True)
    if hashlib.sha256(target.read_bytes()).hexdigest() != digest: raise RuntimeError('Checksum mismatch: ' + target.name)
for module, digest in digests.items():
    target = root / (module + '.aar')
    fetch(f'https://repo.maven.apache.org/maven2/dev/rikka/shizuku/{module}/13.1.5/{module}-13.1.5.aar', target, digest)
    with zipfile.ZipFile(target) as z: (root / (module + '.jar')).write_bytes(z.read('classes.jar'))
fetch('https://dl.google.com/dl/android/maven2/androidx/annotation/annotation/1.3.0/annotation-1.3.0.jar', root / 'annotation.jar',
    '97dc45afefe3a1e421da42b8b6e9f90491477c45fc6178203e3a5e8a05ee8553')
print('Verified Shizuku API 13.1.5 and build-only AndroidX annotations')
