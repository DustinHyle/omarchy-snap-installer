"""Isolated integration tests: fake sudo/hyprpm/Hyprland, never the real desktop."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('migration', ROOT / 'migrate-legacy.py')
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)
PIN = '5232f5105f1c59f986533af132392bcde1865fd9'

MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, subprocess, sys
p = pathlib.Path(os.environ['MOCK_ROOT'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
cache = pathlib.Path(os.environ['HYPR_EDGESNAP_HYPRPM_CACHE'])
repo = cache / 'hypr-edgesnap'
def log(s):
    with (p / 'events').open('a') as f: f.write(s + '\n')
if name == 'sudo':
    log('sudo ' + ' '.join(args))
    if args == ['-k']:
        (p / 'authorized').unlink(missing_ok=True)
        sys.exit(0)
    noninteractive = '-n' in args
    args = [a for a in args if a != '-n']
    if args == ['-v']:
        if not noninteractive:
            log('PASSWORD')
            if not os.environ.get('NO_CACHE'): (p / 'authorized').touch()
            sys.exit(0)
    if not (p / 'authorized').exists(): sys.exit(1)
    if args in (['-v'], ['true']): sys.exit(0)
    if args[0] == 'install':
        # Avoid root ownership changes while testing copies as a normal user.
        args = [a for i,a in enumerate(args) if a not in ('-o','-g') and not (i and args[i-1] in ('-o','-g'))]
    sys.exit(subprocess.call(args))
elif name == 'hyprpm':
    op = next(a for a in args if not a.startswith('--'))
    log('hyprpm ' + op)
    if subprocess.call(['sudo', '-n', 'true']): sys.exit(1)
    try:
        if op in ('remove','add'):
            print('Confirm repository operation? [Y/n]', flush=True)
            # Read one line without stealing later prompts' piped test input.
            answer = b''
            while True:
                byte = os.read(0, 1)
                if byte in (b'', b'\n'): break
                answer += byte
            if answer.strip().lower() not in (b'', b'y', b'yes'): sys.exit(0)
        if op == 'remove':
            shutil.rmtree(repo)
            (p / 'loaded').unlink(missing_ok=True)
        elif op == 'add':
            repo.mkdir(parents=True, exist_ok=True)
            rev = args[-1]
            (repo/'state.toml').write_text('[hypr-edgesnap]\nenabled = false\nfailed = false\nfilename = "hypr-edgesnap.so"\n[repository]\nrev = "'+rev+'"\n')
            (repo/'hypr-edgesnap.so').write_text('new binary')
            if os.environ.get('FAIL_ADD'): sys.exit(1)
        elif op == 'enable':
            state = repo/'state.toml'
            state.write_text(state.read_text().replace('enabled = false','enabled = true'))
            (p / 'loaded').touch()
        elif op == 'disable':
            state = repo/'state.toml'
            state.write_text(state.read_text().replace('enabled = true','enabled = false'))
            (p / 'loaded').unlink(missing_ok=True)
    finally:
        subprocess.call(['sudo', '-k'])
elif name == 'omarchy-version': print('4.5.0')
elif name == 'vercmp': print('0')
elif name == 'omarchy': sys.exit('unexpected package installation')
elif name == 'Hyprland': print(json.dumps({'abiHash':'abi'}))
elif name == 'hyprctl':
    if args == ['configerrors']:
        if os.environ.get('FAIL_CONFIG') and (p/'.config/hypr/window-snap.lua').exists(): print('test config failure')
    elif args == ['-j','version']: print(json.dumps({'version':'0.56.2','abiHash':'abi'}))
    elif args == ['-j','plugin','list']: print(json.dumps([{'name':'hypr-edgesnap'}] if (p/'loaded').exists() else []))
    elif args[:2] == ['plugin','unload']: (p/'loaded').unlink(missing_ok=True)
    elif args[:2] == ['plugin','load']: (p/'loaded').touch()
    elif args != ['reload']: sys.exit('unexpected hyprctl call: '+repr(args))
else: sys.exit('unknown mock '+name)
'''


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        for name in ['sudo','hyprpm','omarchy','omarchy-version','vercmp','Hyprland','hyprctl']:
            path = self.bin / name
            path.write_text(MOCK)
            path.chmod(0o755)
        self.configdir = self.home / '.config/hypr'
        self.configdir.mkdir(parents=True)
        self.config = self.configdir / 'hyprland.lua'
        self.config.write_text('-- user config\nrequire("hypr.edgesnap")\n')
        (self.configdir/'bindings.lua').write_text(migration.PLUGIN_BINDINGS + '\n-- keep dictation\n')
        (self.configdir/'looknfeel.lua').write_text('hl.config({ general = {\n' + migration.ALIGNMENT + 'gaps_in = 2,\n} })\n')
        helpers = self.home/'omarchy/default/hypr/helpers.lua'
        helpers.parent.mkdir(parents=True)
        helpers.write_text('function o.rebind()\nend\n')
        self.cache = self.home/'cache'
        self.repo = self.cache/'hypr-edgesnap'
        self.repo.mkdir(parents=True)
        (self.cache/'state.toml').write_text('[state]\nhash = "abi"\n')
        self.oldstate = '[hypr-edgesnap]\nenabled = true\nfailed = false\nfilename = "hypr-edgesnap.so"\n[repository]\nrev = ""\n'
        (self.repo/'state.toml').write_text(self.oldstate)
        (self.repo/'hypr-edgesnap.so').write_text('original binary')
        (self.home/'loaded').touch()
        self.env = {**os.environ, 'HOME':str(self.home), 'MOCK_ROOT':str(self.home),
                    'OMARCHY_PATH':str(self.home/'omarchy'), 'PATH':f'{self.bin}:'+os.environ['PATH'],
                    'HYPRLAND_INSTANCE_SIGNATURE':'fake', 'HYPR_EDGESNAP_HYPRPM_CACHE':str(self.cache),
                    'TMPDIR':str(self.home)}
        self.original = {p:p.read_bytes() for p in self.configdir.iterdir()}

    def run_install(self, answers='y\ny\ny\n', **extra):
        return subprocess.run(['bash',str(ROOT/'install.sh')], input=answers, text=True,
                              capture_output=True, env={**self.env, **extra}, timeout=30)

    def assert_recovered(self):
        self.assertEqual((self.repo/'state.toml').read_text(), self.oldstate)
        self.assertEqual((self.repo/'hypr-edgesnap.so').read_text(), 'original binary')
        self.assertTrue((self.home/'loaded').exists())
        for path,data in self.original.items(): self.assertEqual(path.read_bytes(), data)
        self.assertFalse((self.configdir/'window-snap.lua').exists())

    def test_success_and_repeat_with_one_authentication_each(self):
        for _ in range(2):
            result = self.run_install()
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        events = (self.home/'events').read_text().splitlines()
        self.assertEqual(events.count('PASSWORD'), 2)
        self.assertEqual(events.count('sudo -k'), 2)  # only installer cleanup, never hyprpm's drops
        self.assertEqual(self.config.read_text().count('-- omarchy-snap-installer'), 1)
        self.assertNotIn('require("hypr.edgesnap")',self.config.read_text())
        self.assertEqual((self.configdir/'bindings.lua').read_text(), '-- keep dictation\n')
        self.assertNotIn(migration.ALIGNMENT,(self.configdir/'looknfeel.lua').read_text())
        self.assertIn('gaps_in = 2',(self.configdir/'looknfeel.lua').read_text())
        for name in ['edgesnap.lua','window-snap.lua']:
            self.assertEqual((self.configdir/name).read_bytes(), (ROOT/'payload'/name).read_bytes())
        self.assertIn(PIN,(self.repo/'state.toml').read_text())

    def test_cancelled_add_restores_old_plugin_without_network(self):
        result = self.run_install('y\ny\nn\n')
        self.assertNotEqual(result.returncode,0)
        self.assert_recovered()

    def test_build_failure_restores_old_plugin(self):
        result = self.run_install(FAIL_ADD='1')
        self.assertNotEqual(result.returncode,0)
        self.assert_recovered()

    def test_config_failure_restores_files_and_plugin(self):
        result = self.run_install(FAIL_CONFIG='1')
        self.assertNotEqual(result.returncode,0)
        self.assert_recovered()

    def test_cancelled_remove_does_not_replace_plugin(self):
        result = self.run_install('y\nn\n')
        self.assertNotEqual(result.returncode,0)
        self.assert_recovered()

    def test_new_install_failure_removes_partial_registration(self):
        import shutil
        shutil.rmtree(self.repo)
        (self.home/'loaded').unlink()
        result = self.run_install(FAIL_ADD='1')
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(self.repo.exists())

    def test_no_sudo_cache_fails_without_repeated_passwords(self):
        result = self.run_install(NO_CACHE='1')
        self.assertNotEqual(result.returncode,0)
        events = (self.home/'events').read_text().splitlines()
        self.assertEqual(events.count('PASSWORD'),1)
        self.assertFalse(any(e.startswith('hyprpm ') for e in events))
        self.assert_recovered()

    def test_modified_legacy_block_is_not_touched(self):
        path=self.configdir/'bindings.lua'
        path.write_text(migration.PLUGIN_BINDINGS.replace('Snap window left','My custom action'))
        before=path.read_bytes()
        result=self.run_install()
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(path.read_bytes(),before)
        self.assertFalse((self.home/'events').exists())

    def test_original_script_only_migration(self):
        path=self.configdir/'bindings.lua'
        path.write_text(migration.SCRIPT_BINDINGS+'\n-- personal binding\n')
        changes=migration.plan(self.home)
        self.assertEqual(changes[path],'-- personal binding\n')

    def test_uninstall_uses_one_authentication(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        result = subprocess.run(['bash',str(ROOT/'uninstall.sh')], input='y\ny\n', text=True,
                                capture_output=True, env=self.env, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertFalse(self.repo.exists())
        events = (self.home/'events').read_text().splitlines()
        self.assertEqual(events.count('PASSWORD'),2)  # once per install/uninstall
        self.assertEqual(events.count('sudo -k'),2)

    def test_preexisting_authorization_needs_no_password(self):
        (self.home/'authorized').touch()
        result = self.run_install()
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertNotIn('PASSWORD',(self.home/'events').read_text())
        self.assertFalse((self.home/'authorized').exists())

    def test_disabled_registration_recovers_as_disabled(self):
        self.oldstate = self.oldstate.replace('enabled = true','enabled = false')
        (self.repo/'state.toml').write_text(self.oldstate)
        (self.home/'loaded').unlink()
        result=self.run_install(FAIL_ADD='1')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.repo/'state.toml').read_text(),self.oldstate)
        self.assertFalse((self.home/'loaded').exists())


if __name__ == '__main__':
    unittest.main()
