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
    action = ('mirred (Egress Redirect to device handoff0) stolen'
              if kind == 'redirect' else 'gact action goto chain 100')
    return (f'filter protocol ip flower\n'
            f'filter protocol ip flower handle {handle}\n'
            f'eth_type ipv4\ndst_ip {VIP}\nnot_in_hw\n'
            f'action order 1: {action}\n')


FIXTURE = '''#!/usr/bin/env python3
import json, os, pathlib, re, signal, sys
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
            print('default via 10.1.0.1 mtu 8950')
            if not (p / 'missing_metric').exists() or (p / 'route_replaced').exists():
                print('default via 10.1.0.1 metric 50')
    elif a[:3] == ['-4', 'route', 'show']:
        print('10.0.0.0/8 via 10.1.0.1 dev eth0')
    elif a[:3] == ['-4', 'route', 'replace']:
        (p / 'route_replaced').touch()
        with (p / 'operations').open('a') as log:
            log.write('route-replace\\n')
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
    if 'chain' not in a or 'pref' not in a or a[a.index('protocol') + 1] != 'ip':
        sys.exit(3)
    if key in state:
        value = state[key]
        if '-j' in a and not (p / 'no_tc_json').exists():
            handle = int(re.search(r'handle 0x([0-9a-f]+)', value).group(1), 16)
            vip = re.search(r'dst_ip ([0-9.]+)', value).group(1)
            if 'mirred' in value:
                dest = re.search(r'to device ([^ )]+)', value).group(1)
                action = dict(kind='mirred', mirred_action='redirect',
                              direction='egress', to_dev=dest)
            else:
                target = int(re.search(r'goto chain ([0-9]+)', value).group(1))
                action = dict(kind='gact', control_action=dict(type='goto', chain=target))
            print(json.dumps([dict(kind='flower'), dict(kind='flower', options=dict(
                handle=handle, keys=dict(eth_type='ipv4', dst_ip=vip), actions=[action]))]))
        elif '-j' in a:
            sys.exit(1)
        else:
            print(value, end='')
    elif '-j' in a and not (p / 'no_tc_json').exists():
        print('[]')
    elif '-j' in a:
        sys.exit(1)
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
    state[key] = (f'filter protocol ip flower\\n'
                  f'filter protocol ip flower handle {handle}\\n'
                  f'eth_type ipv4\\ndst_ip 10.0.0.40\\nnot_in_hw\\n'
                  f'action order 1: {action}\\n')
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

    def test_fresh_install_and_repeated_reconciliation(self):
        (self.path / 'owned').touch()
        state, ops = self.run_once()
        self.assertEqual(set(state), {'100:1040', '0:1040'})
        self.assertEqual(ops, ['add 100:1040', 'add 0:1040'])
        self.assertEqual(self.run_once()[1], ops)

    def test_exact_human_output_without_json(self):
        (self.path / 'owned').touch()
        (self.path / 'no_tc_json').touch()
        self.state_path.write_text(json.dumps({'100:1040': filter_text('100', 'redirect')}))
        state, ops = self.run_once()
        self.assertIn('0:1040', state)
        self.assertEqual(ops, ['add 0:1040'])
        self.assertEqual(self.run_once()[1], ops)

    def test_equivalent_manual_entry_is_kept(self):
        (self.path / 'owned').touch()
        self.state_path.write_text(json.dumps({
            '100:1040': filter_text('100', 'redirect'),
            '0:1040': filter_text('0', 'entry')}))
        state, ops = self.run_once()
        self.assertEqual(set(state), {'100:1040', '0:1040'})
        self.assertEqual(ops, [])

    def test_ownership_loss_deletes_entry_first(self):
        self.state_path.write_text(json.dumps({
            '0:1040': filter_text('0', 'entry'),
            '100:1040': filter_text('100', 'redirect')}))
        state, ops = self.run_once()
        self.assertEqual(state, {})
        self.assertEqual(ops, ['del 0:1040', 'del 100:1040'])

    def test_existing_metric_fifty_route_is_kept(self):
        _, ops = self.run_once()
        self.assertEqual(ops, [])

    def test_missing_metric_fifty_route_is_replaced_once(self):
        (self.path / 'missing_metric').touch()
        _, ops = self.run_once()
        self.assertEqual(ops, ['route-replace'])
        self.assertEqual(self.run_once()[1], ops)

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

    def test_unverified_redirect_preserves_existing_entry(self):
        (self.path / 'owned').touch()
        (self.path / 'fail_redirect').touch()
        self.state_path.write_text(json.dumps({'0:1040': filter_text('0', 'entry')}))
        state, ops = self.run_once()
        self.assertEqual(state, {'0:1040': filter_text('0', 'entry')})
        self.assertEqual(ops, ['add 100:1040'])

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

    def test_wrong_handle_collision_preserved(self):
        (self.path / 'owned').touch()
        unrelated = filter_text('100', 'redirect').replace('handle 0x28', 'handle 0x29')
        self.state_path.write_text(json.dumps({'100:1040': unrelated}))
        state, ops = self.run_once()
        self.assertEqual(state, {'100:1040': unrelated})
        self.assertEqual(ops, [])

    def test_legacy_cleanup_does_not_touch_entry_preference(self):
        self.state_path.write_text(json.dumps({
            '0:140': filter_text('0', 'redirect').replace('handle 0x28', 'handle 0x1'),
            '0:1040': filter_text('0', 'entry')}))
        state, ops = self.run_once()
        self.assertEqual(state, {})
        self.assertEqual(ops, ['del 0:1040', 'del 0:140'])


if __name__ == '__main__':
    unittest.main()
