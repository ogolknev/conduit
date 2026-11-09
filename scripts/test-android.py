#!/usr/bin/env python3
import argparse, pathlib, subprocess
p = argparse.ArgumentParser(); p.add_argument('--jdk', required=True); p.add_argument('--scratch', required=True); args=p.parse_args()
project = pathlib.Path(__file__).resolve().parents[1]
jdk=pathlib.Path(args.jdk).resolve(); scratch=pathlib.Path(args.scratch).resolve(); scratch.mkdir(parents=True,exist_ok=True)
classes = ['PairingCode', 'BluetoothPermissions', 'DiagnosticText', 'BluetoothListenerRecovery']
sources = [str(project/f'android/src/dev/conduit/bridge/{name}.java') for name in classes]
tests = [str(project/f'android/tests/dev/conduit/bridge/{name}Test.java') for name in classes]
subprocess.run([str(jdk/'bin/javac'),'--release','8','-d',str(scratch),*sources,*tests],check=True)
for name in classes:
    subprocess.run([str(jdk/'bin/java'),'-cp',str(scratch),f'dev.conduit.bridge.{name}Test'],check=True)
