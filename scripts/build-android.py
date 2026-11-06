#!/usr/bin/env python3
"""Dependency-free Android build using an existing JDK + official SDK tools.
The local development signing key stays in --scratch, outside the source package.
"""
import argparse, pathlib, subprocess, zipfile, os, shutil

p = argparse.ArgumentParser()
p.add_argument('--jdk', required=True, help='JDK Contents/Home directory')
p.add_argument('--platform', required=True, help='SDK directory containing android.jar')
p.add_argument('--build-tools', required=True, help='SDK build-tools directory')
p.add_argument('--scratch', required=True)
p.add_argument('--output', required=True)
p.add_argument('--shizuku', required=True, help='Directory containing Shizuku api/provider/aidl/shared jars')
p.add_argument('--server', required=True)
args = p.parse_args()
project = pathlib.Path(__file__).resolve().parents[1]
scratch = pathlib.Path(args.scratch).resolve(); scratch.mkdir(parents=True, exist_ok=True)
jdk, sdk, tools = map(lambda s: pathlib.Path(s).resolve(), [args.jdk, args.platform, args.build_tools])
output = pathlib.Path(args.output).resolve(); output.parent.mkdir(parents=True, exist_ok=True)
classes = scratch / 'classes'
if classes.exists(): shutil.rmtree(classes)
classes.mkdir()
dex = scratch / 'dex'; dex.mkdir(exist_ok=True)

def run(*cmd): subprocess.run([str(x) for x in cmd], check=True)

jar = sdk / 'android.jar'
dependencies = [pathlib.Path(args.shizuku).resolve() / (m + '.jar') for m in ['api','provider','aidl','shared']]
sources = sorted((project / 'android/src').rglob('*.java'))
run(jdk / 'bin/javac', '--release', '8', '-encoding', 'UTF-8', '-classpath', os.pathsep.join(str(p) for p in [jar] + dependencies + [pathlib.Path(args.shizuku).resolve() / 'annotation.jar']), '-d', classes, *sources)
classes_jar = scratch / 'classes.jar'
run(jdk / 'bin/jar', 'cf', classes_jar, '-C', classes, '.')
run(jdk / 'bin/java', '-cp', tools / 'lib/d8.jar', 'com.android.tools.r8.D8', '--min-api', '26', '--lib', jar, '--output', dex, classes_jar, *dependencies)
unsigned = scratch / 'unsigned.apk'
run(tools / 'aapt2', 'link', '-o', unsigned, '-I', jar, '--manifest', project / 'android/AndroidManifest.xml')
with zipfile.ZipFile(unsigned, 'a', zipfile.ZIP_DEFLATED) as z:
    for file in dex.glob('*.dex'): z.write(file, file.name)
    z.write(args.server, 'assets/scrcpy-server-v5.0.1', compress_type=zipfile.ZIP_STORED)
aligned = scratch / 'aligned.apk'
run(tools / 'zipalign', '-f', '-p', '4', unsigned, aligned)
key = scratch / 'development.p12'
if not key.exists():
    run(jdk / 'bin/keytool', '-genkeypair', '-keystore', key, '-storepass', 'conduit-local-dev', '-alias', 'conduit', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Conduit Local Development')
run(jdk / 'bin/java', '-jar', tools / 'lib/apksigner.jar', 'sign', '--ks', key, '--ks-pass', 'pass:conduit-local-dev', '--out', output, aligned)
run(jdk / 'bin/java', '-jar', tools / 'lib/apksigner.jar', 'verify', '--verbose', output)
print('Built:', output)
