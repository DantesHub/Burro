# Isolated cross-platform parser/probe fixtures; no SSH connections or provider accounts are used.
import calendar
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

PROBE = Path(__file__).resolve().parents[1] / 'Sources/BurroCore/Resources/remote_probe.py'
spec = importlib.util.spec_from_file_location('probe', PROBE)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
    def test_parent_identity_is_explicit_and_validated(self):
        sid = '11111111-2222-4333-8444-555555555555'
        source = json.dumps({'subagent': {'thread_spawn': {'parent_thread_id': sid}}})
        self.assertEqual(probe.codex_parent_id(source), 'codex:' + sid)
        for invalid in [None, 'vscode', '{}', '{"subagent":{"other":"guardian"}}', source.replace(sid, '../bad')]:
            self.assertIsNone(probe.codex_parent_id(invalid))

    def test_event_states_need_live_evidence(self):
        start = json.dumps({'type': 'event_msg', 'payload': {'type': 'task_started'}})
        stop = json.dumps({'type': 'event_msg', 'payload': {'type': 'task_complete'}})
        self.assertEqual(probe.codex_state(start, 1, 100, 101), 'Working')
        self.assertEqual(probe.codex_state(start, 0, 100, 101), 'Recent activity')
        self.assertEqual(probe.codex_state(start, 0, 100, 1000), 'Inactive')
        self.assertEqual(probe.codex_state(start + '\n' + stop, 1, 100, 101), 'Open · idle')
        self.assertEqual(probe.codex_state(start + '\n' + stop, 0, 100, 101), 'Inactive')
        self.assertEqual(probe.codex_state(start, -1, 100, 101), 'Unknown')

    def test_claude_dead_or_uncertain_identity_never_looks_working(self):
        self.assertEqual(probe.claude_state('working', False), 'Inactive')
        self.assertEqual(probe.claude_state('working', None), 'Unknown')
        self.assertEqual(probe.claude_state('waiting_for_permission', True), 'Needs input')
        self.assertEqual(probe.claude_state('future_status', True), 'Unknown')

    def test_mac_and_linux_ps_identity_fixtures(self):
        start = 1800000000
        local = time.strftime('%a %b %d %H:%M:%S %Y', time.localtime(start))
        utc = time.strftime('%a %b %d %H:%M:%S %Y', time.gmtime(start))
        for executable in ['/usr/local/bin/claude', '/home/user/.local/share/claude/versions/2.1.0']:
            response = subprocess.CompletedProcess([], 0, f'{os.getuid()} {local} {executable}\n', '')
            with patch.object(probe.subprocess, 'run', return_value=response):
                self.assertTrue(probe.claude_identity(1234, utc))
                self.assertIsNone(probe.claude_identity(1234, time.strftime('%a %b %d %H:%M:%S %Y', time.gmtime(start - 60))))
        response = subprocess.CompletedProcess([], 0, f'{os.getuid()} {local} /usr/bin/python3\n', '')
        with patch.object(probe.subprocess, 'run', return_value=response):
            self.assertFalse(probe.claude_identity(1234, utc))

    def test_unreadable_identity_is_unknown(self):
        with patch.object(probe.subprocess, 'run', side_effect=subprocess.TimeoutExpired('ps', 1)):
            self.assertIsNone(probe.claude_identity(1234, 'fixture'))
        self.assertIsNone(probe.claude_identity(-1, 'fixture'))

    def test_read_only_probe_fixture_and_no_transcript_body_in_output(self):
        with tempfile.TemporaryDirectory(prefix='burro-probe-') as directory:
            home = Path(directory)
            codex = home / '.codex'; codex.mkdir()
            locks = codex / 'thread-writer-locks'; locks.mkdir()
            rollout = codex / 'fixture.jsonl'
            rollout.write_text(json.dumps({'type': 'event_msg', 'payload': {'type': 'task_started'}}) + '\n' +
                               json.dumps({'type': 'response_item', 'payload': {'content': 'PRIVATE PROMPT BODY'}}) + '\n')
            database = codex / 'state_7.sqlite'
            with sqlite3.connect(database) as db:
                db.execute('CREATE TABLE threads (id TEXT,cwd TEXT,title TEXT,updated_at REAL,rollout_path TEXT,archived INTEGER)')
                db.execute('INSERT INTO threads VALUES (?,?,?,?,?,0)', ('fixture', '/remote/space path', 'Codex fixture', time.time(), str(rollout)))
            before = database.read_bytes()
            with open(locks / 'fixture.lock', 'wb') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                result = subprocess.run([sys.executable, '-B', str(PROBE), '--home', directory], capture_output=True, text=True, check=True)
            self.assertNotIn('PRIVATE PROMPT BODY', result.stdout)
            snapshot = json.loads(result.stdout)
            self.assertEqual(snapshot['sessions'][0]['state'], 'Working')
            self.assertEqual(snapshot['sessions'][0]['cwd'], '/remote/space path')
            self.assertEqual(before, database.read_bytes())
            self.assertEqual(snapshot['warnings'], [])

    def test_closed_completed_history_is_exported_without_viewer_ids(self):
        with tempfile.TemporaryDirectory(prefix='burro-probe-') as directory:
            home = Path(directory); codex = home / '.codex'; codex.mkdir()
            rollout = codex / 'done.jsonl'
            rollout.write_text(json.dumps({'type': 'event_msg', 'payload': {'type': 'task_complete'}}))
            with sqlite3.connect(codex / 'state_7.sqlite') as db:
                db.execute('CREATE TABLE threads (id TEXT,cwd TEXT,title TEXT,updated_at REAL,rollout_path TEXT,archived INTEGER)')
                db.executemany('INSERT INTO threads VALUES (?,?,?,?,?,0)', [(f'fixture-{i}', '/repo', 'Done', i, str(rollout)) for i in range(3)])
            result = probe.collect(home)
            self.assertEqual(len(result['sessions']), 3)
            self.assertEqual(len({s['id'] for s in result['sessions']}), 3)
            self.assertEqual(result['sessions'][0]['state'], 'Inactive')
            self.assertTrue(result['sessions'][0]['turnCompleted'])
            self.assertNotIn('hasUnreadResult', result['sessions'][0])
            rollout.write_text(json.dumps({'type': 'event_msg', 'payload': {'type': 'task_aborted'}}))
            self.assertFalse(probe.codex_completed(rollout.read_text()))
            self.assertEqual(probe.collect(home)['sessions'], [])
            with sqlite3.connect(codex / 'state_7.sqlite') as db:
                db.execute('DELETE FROM threads')
            self.assertEqual(probe.collect(home)['sessions'], [])

    def test_claude_completion_requires_finished_turn_and_idle(self):
        with tempfile.TemporaryDirectory(prefix='burro-probe-') as directory:
            home = Path(directory)
            registry = home / '.claude/sessions'; registry.mkdir(parents=True)
            metadata = home / 'Library/Application Support/Claude/claude-code-sessions/account/org'
            metadata.mkdir(parents=True)
            (metadata / 'local_fixture.json').write_text(json.dumps(dict(sessionId='local_fixture', completedTurns=1, isArchived=False)))
            record = dict(sessionId='cli-fixture', cwd='/repo', pid=123, status='idle', hostSessionId='local_fixture')
            (registry / 'fixture.json').write_text(json.dumps(record))
            with patch.object(probe, 'claude_identity', return_value=True):
                self.assertTrue(probe.collect(home)['sessions'][0]['turnCompleted'])
                record['status'] = 'busy'
                (registry / 'fixture.json').write_text(json.dumps(record))
                self.assertFalse(probe.collect(home)['sessions'][0]['turnCompleted'])

    def test_checkpoint_fallback_refuses_live_journals(self):
        with tempfile.TemporaryDirectory(prefix='burro-probe-') as directory:
            database = Path(directory) / 'state.sqlite'
            with sqlite3.connect(database) as db:
                db.execute('CREATE TABLE threads (id TEXT,cwd TEXT,title TEXT,updated_at REAL,rollout_path TEXT,archived INTEGER)')
            original = sqlite3.connect
            calls = []
            def blocked_sidecars(location, **kwargs):
                calls.append(location)
                if 'immutable=1' not in location:
                    raise sqlite3.OperationalError('unable to open database file')
                return original(location, **kwargs)
            with patch.object(probe.sqlite3, 'connect', side_effect=blocked_sidecars):
                self.assertEqual(probe.codex_rows(database), [])
                self.assertIn('immutable=1', calls[-1])
                Path(str(database) + '-wal').write_bytes(b'live')
                calls.clear()
                with self.assertRaises(sqlite3.OperationalError):
                    probe.codex_rows(database)
                self.assertEqual(len(calls), 1)

    def test_internal_children_never_export_closed_done_history(self):
        child = json.dumps({'subagent': {'thread_spawn': {'parent_thread_id': 'parent', 'depth': 1}}})
        self.assertTrue(probe.codex_is_subagent(child))
        self.assertTrue(probe.codex_is_subagent('{"subagent":{"other":"guardian"}}'))
        self.assertFalse(probe.codex_is_subagent('vscode'))
        with tempfile.TemporaryDirectory(prefix='burro-identity-') as directory:
            home = Path(directory); codex = home / '.codex'; codex.mkdir()
            rollout = codex / 'done.jsonl'
            rollout.write_text(json.dumps({'type': 'event_msg', 'payload': {'type': 'task_complete'}}))
            with sqlite3.connect(codex / 'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads (id TEXT,cwd TEXT,title TEXT,name TEXT,source TEXT,updated_at REAL,rollout_path TEXT,archived INTEGER)')
                db.executemany('INSERT INTO threads VALUES (?,?,?,?,?,?,?,0)', [
                    ('chat', '/repo', 'Original prompt', 'Displayed chat name', 'vscode', 1, str(rollout)),
                    ('untitled', '/repo', '', '', 'vscode', 1, str(rollout)),
                    ('blank-worker', '/repo', '', '', child, 1, str(rollout)),
                    ('named-worker', '/repo', 'Task instruction', 'Worker name', child, 1, str(rollout))])
            result = probe.collect(home)
            self.assertEqual({s['id'] for s in result['sessions']}, {'codex:chat', 'codex:untitled'})
            self.assertEqual({s['title'] for s in result['sessions']}, {'Displayed chat name', 'Untitled chat'})
            self.assertTrue(all(not s['isSubagent'] for s in result['sessions']))
            rollout.write_text(json.dumps({'type': 'event_msg', 'payload': {'type': 'task_started'}}))
            with patch.object(probe, 'held_lock', return_value=1):
                live = probe.collect(home)['sessions']
            self.assertEqual(len(live), 4)
            self.assertEqual(sum(s['isSubagent'] for s in live), 2)
            self.assertTrue(all(s['state'] == 'Working' for s in live))

    def test_provider_schema_failures_report_limited_visibility(self):
        with tempfile.TemporaryDirectory(prefix='burro-probe-') as directory:
            home = Path(directory)
            (home / '.codex').mkdir()
            (home / '.claude').mkdir()
            result = probe.collect(home)
            self.assertEqual(result['sessions'], [])
            self.assertEqual(len(result['warnings']), 2)

    def test_claude_navigation_ids_survive_remote_probe_without_session_content(self):
        with tempfile.TemporaryDirectory(prefix='burro-probe-') as directory:
            home = Path(directory)
            registry = home / '.claude/sessions'
            registry.mkdir(parents=True)
            record = dict(sessionId='cli-session', cwd='/remote/workspace', pid=123, procStart='fixture',
                          status='busy', hostSessionId='local_desktop', bridgeSessionId='session_remote',
                          unrelated='PRIVATE CONTENT')
            (registry / 'fixture.json').write_text(json.dumps(record))
            with patch.object(probe, 'claude_identity', return_value=True):
                result = probe.collect(home)
            self.assertEqual(result['sessions'][0]['claudeDesktopSessionID'], 'local_desktop')
            self.assertEqual(result['sessions'][0]['claudeBridgeSessionID'], 'session_remote')
            self.assertNotIn('PRIVATE CONTENT', json.dumps(result))
            record['hostSessionId'] = {'unexpected': 'object'}
            record['bridgeSessionId'] = 'x' * 129
            (registry / 'fixture.json').write_text(json.dumps(record))
            with patch.object(probe, 'claude_identity', return_value=True):
                result = probe.collect(home)
            self.assertNotIn('claudeDesktopSessionID', result['sessions'][0])
            self.assertNotIn('claudeBridgeSessionID', result['sessions'][0])


if __name__ == '__main__':
    unittest.main()
