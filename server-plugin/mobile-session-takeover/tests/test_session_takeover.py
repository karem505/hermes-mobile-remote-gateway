"""Cross-surface session takeover ("pull a live chat to another device").

Three cooperating pieces under test: the request files
(``hmt_requests``), the holder-side release watcher + requester-side
``session.takeover`` (``tui_gateway.session_takeover``), and the guarded registry steal for
holders from before the watcher existed (``hmt_registry.steal_active_session``).

What must hold: a request alone changes nothing; a running turn is interrupted but the lease
is released only once it has settled; abandoned requests (dead requester / stale) are never
acted on; a steal requires the between-turns proof and restores the entry when it loses the
race; the RPC reports honestly (already / released / stolen / TAKEOVER_BUSY / TAKEOVER_RACED).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time

import pytest

import importlib.util
import os as _os
import sys as _sys

_PLUGIN = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location(
    "mobile_session_takeover_under_test", _os.path.join(_PLUGIN, "__init__.py"),
    submodule_search_locations=[_PLUGIN])
_mod = importlib.util.module_from_spec(_spec)
_sys.modules[_spec.name] = _mod
_spec.loader.exec_module(_mod)  # arms the tui_gateway.server import hook

from hermes_cli.active_sessions import _own_start_time, try_acquire_active_session  # noqa: E402
from hermes_mobile_takeover.registry import (  # noqa: E402
    active_session_holder,
    restore_stolen_session,
    steal_active_session,
)
from hermes_mobile_takeover.requests import (  # noqa: E402
    clear_takeover_request,
    pending_takeover_requests,
    read_takeover_request,
    write_takeover_request,
)
from tui_gateway import server
from tui_gateway.turn_marker import clear_turn_marker, record_turn_start

KEY = "20261001_120000_test01"
SID = "live-requester"
HOLDER_SID = "live-holder"


@pytest.fixture(autouse=True)
def _isolate_sessions():
    before = set(server._sessions)
    yield
    for sid in list(server._sessions):
        if sid not in before:
            server._sessions.pop(sid, None)


@pytest.fixture()
def manual_watcher(monkeypatch):
    """Park the import-time watcher daemon and hand back the real tick, so call-count
    assertions are deterministic."""
    real = server._takeover_watch_once
    monkeypatch.setattr(server, "_takeover_watch_once", lambda: None)
    return real


def _session(tmp_path, *, sid=SID, key=KEY, running=False, lease=None, source="mobile"):
    return {
        "history_lock": threading.Lock(),
        "session_key": key,
        "profile_home": str(tmp_path),
        "source": source,
        "running": running,
        "active_session_lease": lease,
    }


def _register(tmp_path, **kw):
    session = _session(tmp_path, **kw)
    server._sessions[kw.get("sid", SID)] = session
    return session


def _hold(tmp_path, *, sid=HOLDER_SID):
    """A live holder runtime in THIS process with a real unreleased lease."""
    lease, err = try_acquire_active_session(
        session_id=KEY, surface="desktop", config={}, registry_home=tmp_path, track_liveness=True)
    assert err is None and lease is not None
    return _register(tmp_path, sid=sid, lease=lease, source="desktop"), lease


def _foreign_entry(tmp_path, *, surface="desktop", live="foreign-live", age=600.0):
    """A raw registry entry: this pid (kept alive by liveness pruning) as another writer."""
    state = tmp_path / "runtime" / "active_sessions.json"
    state.parent.mkdir(parents=True, exist_ok=True)
    entry = {
        "lease_id": "deadbeefdeadbeefdeadbeefdeadbeef",
        "session_id": KEY,
        "surface": surface,
        "pid": os.getpid(),
        "process_start_time": _own_start_time(),
        "started_at": time.time() - age,
        "updated_at": time.time() - age,
        "track_liveness": True,
        "metadata": {"live_session_id": live},
    }
    state.write_text(json.dumps({"entries": [entry]}))
    return entry


# ── request files ─────────────────────────────────────────────────────────────────────────────


def test_request_files_roundtrip_and_expire(tmp_path):
    write_takeover_request(KEY, surface="mobile", registry_home=tmp_path)
    entry = read_takeover_request(KEY, registry_home=tmp_path)
    assert entry and entry["surface"] == "mobile"
    assert [e["session_key"] for e in pending_takeover_requests(registry_home=tmp_path)] == [KEY]

    assert clear_takeover_request(KEY, registry_home=tmp_path) is True
    assert read_takeover_request(KEY, registry_home=tmp_path) is None

    write_takeover_request(KEY, surface="mobile", registry_home=tmp_path)
    path = tmp_path / "runtime" / "takeover_requests" / f"{KEY}.json"
    stale = json.loads(path.read_text())
    stale["requested_at"] = time.time() - 10_000
    path.write_text(json.dumps(stale))
    assert read_takeover_request(KEY, registry_home=tmp_path) is None
    assert pending_takeover_requests(registry_home=tmp_path) == []


def test_clear_with_requester_pid_only_removes_that_requester(tmp_path):
    write_takeover_request(KEY, surface="mobile", registry_home=tmp_path, pid=os.getpid())
    assert clear_takeover_request(KEY, registry_home=tmp_path, requester_pid=os.getpid() + 1) is False
    assert read_takeover_request(KEY, registry_home=tmp_path) is not None
    assert clear_takeover_request(KEY, registry_home=tmp_path, requester_pid=os.getpid()) is True


# ── release watcher ───────────────────────────────────────────────────────────────────────────


def test_watcher_releases_an_idle_holders_lease(tmp_path, manual_watcher, monkeypatch):
    session, lease = _hold(tmp_path)
    write_takeover_request(KEY, surface="mobile", registry_home=tmp_path)
    events = []
    monkeypatch.setattr(server, "_emit", lambda event, sid, payload=None: events.append((event, sid, payload)))

    manual_watcher()

    assert lease.released is True
    assert session["_lease_taken_over"] is True
    assert session.get("active_session_lease") is None
    assert read_takeover_request(KEY, registry_home=tmp_path) is None
    assert events == [("session.taken_over", HOLDER_SID, {"session_id": KEY, "by": "mobile", "forced": False})]


def test_watcher_interrupts_a_running_turn_then_releases(tmp_path, manual_watcher, monkeypatch):
    session, lease = _hold(tmp_path)
    session["running"] = True
    write_takeover_request(KEY, surface="mobile", registry_home=tmp_path)
    interrupts, events = [], []
    monkeypatch.setattr(server, "_interrupt_session_turn",
                        lambda sid, sess, *, request_id=None: (interrupts.append(sid), sess.update(running=False))[0])
    monkeypatch.setattr(server, "_emit", lambda event, sid, payload=None: events.append(event))

    manual_watcher()
    assert interrupts == [HOLDER_SID]
    assert lease.released is False          # never mid-turn
    assert read_takeover_request(KEY, registry_home=tmp_path) is not None

    manual_watcher()
    assert lease.released is True
    assert events == ["session.taken_over"]
    assert session.get("active_session_lease") is None


def test_watcher_ignores_a_dead_requester(tmp_path, manual_watcher):
    _, lease = _hold(tmp_path)
    corpse = subprocess.Popen([sys.executable, "-c", "pass"])
    corpse.wait()
    write_takeover_request(KEY, surface="mobile", registry_home=tmp_path, pid=corpse.pid)

    manual_watcher()

    assert lease.released is False
    assert read_takeover_request(KEY, registry_home=tmp_path) is not None


def test_watcher_ignores_requests_for_sessions_this_process_does_not_hold(tmp_path, manual_watcher):
    _foreign_entry(tmp_path)
    write_takeover_request(KEY, surface="mobile", registry_home=tmp_path)

    manual_watcher()

    assert active_session_holder(KEY, registry_home=tmp_path) is not None  # untouched
    assert read_takeover_request(KEY, registry_home=tmp_path) is not None


# ── steal fence + registry helpers ────────────────────────────────────────────────────────────


def test_steal_fence_requires_between_turns_proof(tmp_path):
    fence = server._steal_fence
    assert fence({"surface": "desktop", "started_at": time.time() - 600}, KEY, tmp_path) is True
    assert fence({"surface": "cli", "started_at": time.time() - 600}, KEY, tmp_path) is False
    assert fence({"surface": "desktop", "started_at": time.time()}, KEY, tmp_path) is False  # fresh claim
    assert fence({"surface": "desktop"}, KEY, tmp_path) is False  # age unprovable

    record_turn_start(tmp_path, KEY, "mid-turn")
    try:
        assert fence({"surface": "desktop", "started_at": time.time() - 600}, KEY, tmp_path) is False
    finally:
        clear_turn_marker(tmp_path, KEY)
    assert fence({"surface": "desktop", "started_at": time.time() - 600}, KEY, tmp_path) is True


def test_registry_holder_steal_and_restore(tmp_path):
    entry = _foreign_entry(tmp_path, live=HOLDER_SID)
    holder = active_session_holder(KEY, registry_home=tmp_path)
    assert holder and int(holder["pid"]) == os.getpid() and holder["surface"] == "desktop"

    # A holder that changed since the caller looked must not be removed by accident.
    assert steal_active_session(KEY, held_by_pid=os.getpid() + 1, registry_home=tmp_path) is None
    assert active_session_holder(KEY, registry_home=tmp_path) is not None

    removed = steal_active_session(KEY, held_by_pid=os.getpid(), registry_home=tmp_path)
    assert removed and removed["lease_id"] == entry["lease_id"]
    assert active_session_holder(KEY, registry_home=tmp_path) is None

    assert restore_stolen_session(removed, registry_home=tmp_path) is True
    assert active_session_holder(KEY, registry_home=tmp_path) is not None
    assert restore_stolen_session(removed, registry_home=tmp_path) is False  # slot is taken again


# ── session.takeover RPC ──────────────────────────────────────────────────────────────────────


@pytest.fixture(autouse=True)
def _no_caps(monkeypatch):
    monkeypatch.setattr(server, "_load_cfg", lambda: {})


def test_takeover_rpc_reports_already_when_unheld(tmp_path, manual_watcher):
    session = _register(tmp_path)
    resp = server._handle_session_takeover(1, {"session_id": SID})
    assert resp["result"] == {"status": "already", "holder_surface": None}
    assert session.get("active_session_lease") is not None


def test_takeover_rpc_releases_cooperatively_via_the_holder_watcher(tmp_path, manual_watcher, monkeypatch):
    monkeypatch.setattr(server, "_STEAL_AFTER_S", 60.0)
    monkeypatch.setattr(server, "_REQUEST_WAIT_S", 8.0)
    holder, holder_lease = _hold(tmp_path)
    requester = _register(tmp_path)
    threading.Timer(0.4, manual_watcher).start()  # the holder process's watcher tick

    resp = server._handle_session_takeover(2, {"session_id": SID})

    assert resp["result"] == {"status": "released", "holder_surface": "desktop"}
    assert holder_lease.released is True
    assert holder["_lease_taken_over"] is True
    assert requester.get("active_session_lease") is not None
    assert read_takeover_request(KEY, registry_home=tmp_path) is None


def test_takeover_rpc_steals_from_an_idle_prewatcher_holder(tmp_path, manual_watcher, monkeypatch):
    monkeypatch.setattr(server, "_STEAL_AFTER_S", 0.01)
    monkeypatch.setattr(server, "_REQUEST_WAIT_S", 6.0)
    _foreign_entry(tmp_path)
    session = _register(tmp_path)

    resp = server._handle_session_takeover(3, {"session_id": SID})

    assert resp["result"] == {"status": "stolen", "holder_surface": "desktop"}
    lease = session.get("active_session_lease")
    assert lease is not None and lease.released is False
    assert read_takeover_request(KEY, registry_home=tmp_path) is None  # consumed
    holder = active_session_holder(KEY, registry_home=tmp_path)
    assert holder and int(holder["pid"]) == os.getpid()
    assert (holder.get("metadata") or {}).get("live_session_id") == SID


def test_takeover_rpc_reports_busy_when_the_holder_keeps_turning(tmp_path, manual_watcher, monkeypatch):
    monkeypatch.setattr(server, "_STEAL_AFTER_S", 60.0)
    monkeypatch.setattr(server, "_REQUEST_WAIT_S", 0.6)
    _foreign_entry(tmp_path)
    record_turn_start(tmp_path, KEY, "mid-turn")  # live marker: mid-turn, never stealable
    try:
        _register(tmp_path)
        resp = server._handle_session_takeover(4, {"session_id": SID})
        assert resp["error"]["code"] == 4090
        assert resp["error"]["data"] == {"reason": "TAKEOVER_BUSY", "holder_surface": "desktop"}
        assert read_takeover_request(KEY, registry_home=tmp_path) is None  # failed pull cleaned up
    finally:
        clear_turn_marker(tmp_path, KEY)


def test_takeover_rpc_restores_the_entry_when_the_steal_raced_a_new_turn(tmp_path, manual_watcher, monkeypatch):
    monkeypatch.setattr(server, "_STEAL_AFTER_S", 0.01)
    monkeypatch.setattr(server, "_REQUEST_WAIT_S", 6.0)
    _foreign_entry(tmp_path)
    import hermes_mobile_takeover.registry as registry

    real_steal = registry.steal_active_session

    def racing_steal(session_id, *, held_by_pid, registry_home=None):
        removed = real_steal(session_id, held_by_pid=held_by_pid, registry_home=registry_home)
        if removed is not None:
            assert registry_home is not None
            record_turn_start(registry_home, session_id, "raced")  # a fresh turn appeared mid-steal
        return removed

    monkeypatch.setattr(registry, "steal_active_session", racing_steal)
    _register(tmp_path)
    try:
        resp = server._handle_session_takeover(5, {"session_id": SID})
        assert resp["error"]["data"]["reason"] == "TAKEOVER_RACED"
        assert active_session_holder(KEY, registry_home=tmp_path) is not None  # entry restored
    finally:
        clear_turn_marker(tmp_path, KEY)
