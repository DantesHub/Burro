#!/usr/bin/env python3
"""Read session metadata on a Mac/Linux SSH host; emit no credentials or transcript bodies."""
import calendar
import errno
import fcntl
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import time

LIMIT = 2000
TAIL_LIMIT = 512 * 1024



def held_lock(path):
    try:
        with open(path, "rb") as handle:
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(handle, fcntl.LOCK_UN)
                return 0
            except OSError as error:
                return 1 if error.errno in (errno.EAGAIN, errno.EWOULDBLOCK) else -1
    except FileNotFoundError:
        return 0
    except OSError:
        return -1


def codex_state(tail, held, modified, now):
    if held < 0:
        return "Unknown"
    last = None
    for line in reversed(tail.splitlines()):
        try:
            event = json.loads(line)
            if event.get("type") != "event_msg":
                continue
            kind = event.get("payload", {}).get("type")
            if kind in ("task_started", "turn_started"):
                last = "Working"
            elif kind in ("task_complete", "turn_complete", "turn_aborted", "task_aborted"):
                last = "Open · idle"
            elif kind in ("request_user_input", "approval_required"):
                last = "Needs input"
            else:
                continue
            break
        except (ValueError, AttributeError, TypeError):
            continue
    if held == 1:
        return last or ("Working" if modified is not None and 0 <= now - modified < 120 else "Unknown")
    if last == "Open · idle":
        return "Inactive"
    return "Recent activity" if modified is not None and 0 <= now - modified < 300 else "Inactive"



def codex_completed(tail):
    completed = False
    for line in reversed(tail.splitlines()):
        try:
            event = json.loads(line)
            if event.get("type") != "event_msg":
                continue
            kind = event.get("payload", {}).get("type")
            if kind in ("task_complete", "turn_complete"):
                return True
            elif kind in ("task_started", "turn_started", "task_aborted", "turn_aborted", "request_user_input", "approval_required"):
                return False
        except (ValueError, AttributeError, TypeError):
            continue
    return completed


def claude_completed(home):
    completed = set()
    root = home / "Library/Application Support/Claude/claude-code-sessions"
    for path in root.glob("*/*/local_*.json"):
        try:
            if path.stat().st_size > 1024 * 1024:
                continue
            record = json.loads(path.read_bytes())
            if record.get("completedTurns", 0) > 0 and not record.get("isArchived"):
                completed.add(record.get("sessionId"))
        except (OSError, ValueError, TypeError):
            continue
    return completed

def session(sid, provider, title, cwd, state, updated, evidence, pid=None, pinned=False):
    return dict(id=sid, provider=provider, title=str(title)[:1000], cwd=str(cwd)[:4096], attachedPaths=[],
                state=state, updatedAt=float(updated), evidence=evidence, pid=pid, pinned=pinned)


def claude_state(status, live):
    if live is None:
        return "Unknown"
    if not live:
        return "Inactive"
    status = str(status).lower()
    if status in ("working", "running", "busy", "processing"):
        return "Working"
    if status in ("waiting", "waiting_for_input", "needs_input", "awaiting_approval", "waiting_for_permission"):
        return "Needs input"
    return "Open · idle" if status == "idle" else "Unknown"


def claude_identity(pid, expected):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return None
    try:
        result = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "uid=", "-o", "lstart=", "-o", "comm="],
                                capture_output=True, text=True, timeout=1,
                                env=dict(os.environ, LC_ALL="C", LANG="C"))
        if result.returncode != 0:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return False
            except OSError:
                return None
            return None
        fields = result.stdout.strip().split(None, 6)
        if len(fields) != 7 or int(fields[0]) != os.getuid():
            return False
        executable = fields[6]
        if Path(executable).name != "claude" and "/claude/versions/" not in executable:
            return False
        started = time.mktime(time.strptime(" ".join(fields[1:6]), "%a %b %d %H:%M:%S %Y"))
        stamp = time.strptime(expected, "%a %b %d %H:%M:%S %Y")
        return True if any(abs(started - candidate) < 2 for candidate in (time.mktime(stamp), calendar.timegm(stamp))) else None
    except (OSError, ValueError, TypeError, subprocess.TimeoutExpired):
        return None




def codex_is_subagent(source):
    if source in ('subagent', '"subagent"'):
        return True
    try:
        value = json.loads(source)
        return isinstance(value, dict) and "subagent" in value
    except (ValueError, TypeError):
        return False


def codex_parent_id(source):
    try:
        value = json.loads(source)["subagent"]["thread_spawn"]["parent_thread_id"]
        if isinstance(value, str) and re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value):
            return "codex:" + value
    except (ValueError, TypeError, KeyError):
        pass
    return None


def codex_display_name(name, title, is_subagent):
    for value in (name, title):
        if isinstance(value, str) and value.strip():
            return value.strip()
    return "Codex sub-agent" if is_subagent else "Untitled chat"

def codex_rows(path):
    def query(immutable=False):
        uri = path.resolve().as_uri() + "?mode=ro" + ("&immutable=1" if immutable else "")
        db = sqlite3.connect(uri, uri=True, timeout=1)
        try:
            db.execute("PRAGMA query_only=ON")
            columns = {row[1] for row in db.execute("PRAGMA table_info(threads)")}
            pinned = "is_pinned" if "is_pinned" in columns else "0"
            name = "name" if "name" in columns else "NULL"
            source = "source" if "source" in columns else "NULL"
            return list(db.execute("SELECT id,cwd,title,updated_at,rollout_path," + pinned + "," + name + "," + source +
                                   " FROM threads WHERE archived=0 ORDER BY updated_at DESC LIMIT 2001"))
        finally:
            db.close()
    try:
        return query()
    except sqlite3.OperationalError:
        # SQLite's read-only WAL mode may try to create absent sidecars. Only a
        # stable checkpoint with no journal can be read without those sidecars.
        journals = [Path(str(path) + suffix) for suffix in ("-wal", "-journal")]
        if any(p.exists() for p in journals):
            raise
        before = path.stat()
        rows = query(immutable=True)
        after = path.stat()
        if any(p.exists() for p in journals) or (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise sqlite3.OperationalError("Checkpoint changed during inspection")
        return rows

def collect(home):
    now, deadline = time.time(), time.monotonic() + 8
    sessions, warnings = [], []
    codex = home / ".codex"
    if codex.exists():
        try:
            files = [p for p in codex.glob("state_*.sqlite") if re.fullmatch(r"state_\d+\.sqlite", p.name)]
            files.sort(key=lambda p: int(re.search(r"\d+", p.name).group()), reverse=True)
            if not files:
                warnings.append("Codex session database is unavailable.")
            else:
                rows = codex_rows(files[0])
                if len(rows) > LIMIT:
                    warnings.append("Codex history exceeds the inspection limit; some sessions may be absent.")
                # Inspect open writers first, then bounded history for completed results.
                # No viewer read-state or chat identifiers are sent to this host.
                selected = [(row, held_lock(codex / "thread-writer-locks" / (str(row[0]) + ".lock")))
                            for row in rows[:LIMIT] if isinstance(row[0], str) and "/" not in row[0]]
                selected.sort(key=lambda pair: pair[1] == 0)
                for (sid, cwd, title, updated, rollout, pinned, name, source), held in selected:
                    if time.monotonic() > deadline - 3:
                        warnings.append("Remote inspection reached its time limit.")
                        break
                    if not isinstance(sid, str) or "/" in sid or not cwd:
                        warnings.append("A Codex session record could not be read.")
                        continue
                    is_subagent = codex_is_subagent(source)
                    # Completed child runs are not unread chats in the provider sidebar.
                    # Retain live/uncertain workers for activity and safety evidence.
                    if is_subagent and held == 0 and now - float(updated or 0) >= 600:
                        continue
                    modified, tail = None, ""
                    try:
                        with open(rollout, "rb") as handle:
                            handle.seek(0, 2)
                            handle.seek(max(0, handle.tell() - TAIL_LIMIT))
                            tail = handle.read(TAIL_LIMIT).decode("utf-8", errors="replace")
                            modified = os.fstat(handle.fileno()).st_mtime
                        state = codex_state(tail, held, modified, now)
                    except (OSError, TypeError):
                        state = "Unknown" if held != 0 else "Inactive"
                    completed = codex_completed(tail)
                    if state != "Inactive" or completed and not is_subagent:
                        sessions.append(session("codex:" + sid, "Codex", codex_display_name(name, title, is_subagent), cwd, state, updated or 0,
                                                "Remote writer lock and turn event metadata.", pinned=bool(pinned)))
                        sessions[-1]["turnCompleted"] = completed
                        sessions[-1]["isSubagent"] = is_subagent
                        sessions[-1]["parentSessionID"] = codex_parent_id(source)
        except (OSError, sqlite3.Error, ValueError, TypeError):
            warnings.append("Codex session metadata could not be read on this host.")
    claude = home / ".claude/sessions"
    if claude.exists():
        try:
            files = list(claude.glob("*.json"))
            completed = claude_completed(home)
            if len(files) > LIMIT:
                warnings.append("Claude session records exceed the inspection limit.")
            for path in files[:LIMIT]:
                if time.monotonic() > deadline:
                    warnings.append("Remote inspection reached its time limit.")
                    break
                try:
                    if path.stat().st_size > 1024 * 1024:
                        raise ValueError("Large metadata record")
                    record = json.loads(path.read_bytes())
                    sid, cwd, pid = record["sessionId"], record["cwd"], record["pid"]
                    if not isinstance(sid, str) or not isinstance(cwd, str):
                        raise ValueError("Invalid session identity")
                    live = claude_identity(pid, record.get("procStart"))
                    state = claude_state(record.get("status", ""), live)
                    desktop_id = record.get("hostSessionId")
                    has_result = isinstance(desktop_id, str) and desktop_id in completed and record.get("status") == "idle"
                    if state != "Inactive" or has_result:
                        updated = float(record.get("updatedAt", record.get("startedAt", 0))) / 1000
                        sessions.append(session("claude:" + sid, "Claude Code", record.get("name") or "Claude Code session",
                                                cwd, state, updated, "Remote PID/start-time identity and reported session status.", pid=pid if live else None))
                        sessions[-1]["turnCompleted"] = has_result
                        for source, target in (("hostSessionId", "claudeDesktopSessionID"),
                                               ("bridgeSessionId", "claudeBridgeSessionID")):
                            value = record.get(source)
                            if isinstance(value, str) and len(value) <= 128:
                                sessions[-1][target] = value
                except (OSError, ValueError, KeyError, TypeError):
                    warnings.append("A Claude session record could not be read on this host.")
        except OSError:
            warnings.append("Claude session metadata could not be read on this host.")
    elif (home / ".claude").exists():
        warnings.append("Claude session registry is unavailable on this host.")
    sessions.sort(key=lambda item: item["state"] == "Inactive")
    if len(sessions) > LIMIT:
        warnings.append("Remote sessions exceed the inspection limit.")
    return dict(version=1, sessions=sessions[:LIMIT], warnings=sorted(set(warnings)))


if __name__ == "__main__":
    # An explicit home is used by isolated fixture tests; SSH invokes this script without arguments.
    home = Path(sys.argv[2]) if len(sys.argv) == 3 and sys.argv[1] == "--home" else Path.home()
    print(json.dumps(collect(home), ensure_ascii=True, allow_nan=False))
