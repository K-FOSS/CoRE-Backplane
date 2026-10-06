#!/usr/bin/env python3
"""Exercise the rendered handoff shell with disposable tc/ip command fixtures."""

import json
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'templates/KubeVIP.yaml'
VIP = '10.0.0.40'
PREF = '1040'


def filter_text(chain, kind):
    handle = '0x28' if kind == 'redirect' else '0x1'
    action = ('mirred (Egress Redirect to device handoff0)'
              if kind == 'redirect' else 'gact action goto chain 100')
    return (f'filter protocol ip pref {PREF} flower chain {chain}\n'
            f'filter protocol ip pref {PREF} flower chain {chain} handle {handle}\n'
            f'  dst_ip {VIP}\n  action order 1: {action}\n')


FIXTURE = '''#!/usr/bin/env python3
import json, os, pathlib, signal, sys
p = pathlib.Path(os.environ['FIXTURE_DIR'])
name = pathlib.Path(sys.argv[0]).name
a = sys.argv[1:]
if name == 'sleep':
    os.kill(os.getppid(), signal.SIGTERM)
    sys.exit(0)
if name == 'ip':
    if a[:4] == ['-4', '-o', 'addr', 'show']:
        if (p / 'owned').exists():
            print('1: wan0 inet 10.0.0.40/32 scope global wan0')
    elif a[:3] == ['-4', 'route', 'show'] and 'default' in a:
        if 'eth0' in a:
            print('default via 10.1.0.1 dev eth0')
    elif a[:3] == ['-4', 'route', 'show']:
        print('10.0.0.0/8 via 10.1.0.1 dev eth0')
    sys.exit(0)
if name != 'tc':
    sys.exit(1)
if 'qdisc' in a:
    print('qdisc clsact ffff: dev wan0 parent ffff:fff1')
    sys.exit(0)
if 'action' in a and 'filter' not in a:
    sys.exit(0)
if 'filter' not in a:
    sys.exit(0)
op = a[a.index('filter') + 1]
if op not in ('show', 'add', 'del'):
    sys.exit(0)
chain = a[a.index('chain') + 1] if 'chain' in a else '0'
pref = a[a.index('pref') + 1] if 'pref' in a else ''
state_path = p / 'state.json'
state = json.loads(state_path.read_text())
key = chain + ':' + pref
if op == 'show':
    if key in state:
        print(state[key], end='')
    sys.exit(0)
with (p / 'operations').open('a') as log:
    log.write(op + ' ' + key + '\\n')
if op == 'add':
    if (p / 'fail_redirect').exists() and chain == '100':
        sys.exit(1)
    if (p / 'no_redirect_postcondition').exists() and chain == '100':
        sys.exit(0)
    if key in state:
        sys.exit(2)
    handle = '0x28' if chain == '100' else '0x1'
    action = ('mirred (Egress Redirect to device handoff0)'
              if chain == '100' else 'gact action goto chain 100')
    state[key] = (f'filter protocol ip pref {pref} flower chain {chain}\\n'
                  f'filter protocol ip pref {pref} flower chain {chain} handle {handle}\\n'
                  f'  dst_ip 10.0.0.40\\n  action order 1: {action}\\n')
else:
    state.pop(key, None)
state_path.write_text(json.dumps(state))
'''


class HandoffTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = pathlib.Path(self.temp.name)
        text = SOURCE.read_text().split('  reconcile.sh: |\n', 1)[1].split('\n---\n', 1)[0]
        script = self.path / 'reconcile.sh'
        script.write_text('\n'.join(line[4:] for line in text.splitlines()) + '\n')
        subprocess.run(['sh', '-n', str(script)], check=True)
        self.script = script
        for name in ('tc', 'ip', 'sleep'):
            command = self.path / name
            command.write_text(FIXTURE)
            command.chmod(0o755)
        self.state_path = self.path / 'state.json'
        self.state_path.write_text('{}')

    def run_once(self):
        env = dict(os.environ, FIXTURE_DIR=str(self.path),
                   PATH=str(self.path) + ':' + os.environ['PATH'],
                   WAN_INTERFACE='wan0', HANDOFF_INTERFACE='handoff0',
                   CILIUM_INTERFACE='eth0', PRIVATE_ROUTE_CIDRS='',
                   VIP_RANGE=f'{VIP}-{VIP}', RECONCILE_INTERVAL='1s')
        subprocess.run(['sh', str(self.script)], env=env, capture_output=True,
                       text=True, timeout=5)
        return json.loads(self.state_path.read_text()), (
            (self.path / 'operations').read_text().splitlines()
            if (self.path / 'operations').exists() else [])

    def test_redirect_present_entry_missing_and_idempotence(self):
        self.state_path.write_text(json.dumps({'100:1040': filter_text('100', 'redirect')}))
        (self.path / 'owned').touch()
        state, ops = self.run_once()
        self.assertIn('0:1040', state)
        self.assertEqual(ops, ['add 0:1040'])
        self.assertEqual(self.run_once()[1], ops)

    def test_ownership_loss_deletes_entry_first(self):
        self.state_path.write_text(json.dumps({
            '0:1040': filter_text('0', 'entry'),
            '100:1040': filter_text('100', 'redirect')}))
        state, ops = self.run_once()
        self.assertEqual(state, {})
        self.assertEqual(ops, ['del 0:1040', 'del 100:1040'])

    def test_failed_redirect_prevents_entry(self):
        (self.path / 'owned').touch()
        (self.path / 'fail_redirect').touch()
        state, ops = self.run_once()
        self.assertEqual(state, {})
        self.assertEqual(ops, ['add 100:1040'])

    def test_success_without_redirect_postcondition_prevents_entry(self):
        (self.path / 'owned').touch()
        (self.path / 'no_redirect_postcondition').touch()
        state, ops = self.run_once()
        self.assertEqual(state, {})
        self.assertEqual(ops, ['add 100:1040'])

    def test_unverified_redirect_removes_stale_entry(self):
        (self.path / 'owned').touch()
        (self.path / 'fail_redirect').touch()
        self.state_path.write_text(json.dumps({'0:1040': filter_text('0', 'entry')}))
        state, ops = self.run_once()
        self.assertEqual(state, {})
        self.assertEqual(ops, ['add 100:1040', 'del 0:1040'])

    def test_unrelated_collision_preserved(self):
        (self.path / 'owned').touch()
        unrelated = filter_text('100', 'redirect').replace('10.0.0.40', '10.0.0.99')
        self.state_path.write_text(json.dumps({'100:1040': unrelated}))
        state, ops = self.run_once()
        self.assertEqual(state, {'100:1040': unrelated})
        self.assertEqual(ops, [])

    def test_unrelated_entry_collision_preserved(self):
        (self.path / 'owned').touch()
        unrelated = filter_text('0', 'entry').replace('goto chain 100', 'goto chain 200')
        self.state_path.write_text(json.dumps({
            '0:1040': unrelated, '100:1040': filter_text('100', 'redirect')}))
        state, ops = self.run_once()
        self.assertEqual(state['0:1040'], unrelated)
        self.assertEqual(ops, [])


if __name__ == '__main__':
    unittest.main()
