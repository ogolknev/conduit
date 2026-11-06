#!/usr/bin/env python3
import argparse, os, pathlib, subprocess

p = argparse.ArgumentParser(); p.add_argument('--scratch', required=True); args = p.parse_args()
project = pathlib.Path(__file__).resolve().parents[1]
scratch = pathlib.Path(args.scratch).resolve(); scratch.mkdir(parents=True, exist_ok=True)
cache = str(scratch / 'module-cache')
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=cache, SWIFTPM_MODULECACHE_OVERRIDE=cache)
cmd = ['swift', 'test', '--package-path', str(project), '--scratch-path', str(scratch / 'build'),
    '--cache-path', str(scratch / 'cache'), '--config-path', str(scratch / 'config'), '--security-path', str(scratch / 'security'),
    '--disable-sandbox', '--disable-xctest']
developer = pathlib.Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
frameworks = developer / 'Library/Developer/Frameworks'
if (frameworks / 'Testing.framework').exists():
    cmd += ['-Xswiftc', '-F', '-Xswiftc', str(frameworks), '-Xlinker', '-F', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(frameworks)]
    # CLT 6.2 includes Testing but omits the optional Foundation overlay's module.
    cmd += ['-Xswiftc', '-Xfrontend', '-Xswiftc', '-disable-cross-import-overlays']
subprocess.run(cmd, env=env, check=True)
