"""Session takeover ("pull a live chat to this surface"): release watcher + ``session.takeover``.

Two halves that meet at the shared request files (``hmt_requests.py`` in this plugin):

* The WATCHER runs in every serve process and looks for requests naming a session THIS process
  holds a live lease for. The holding turn is asked to stop; once it has settled the lease is
  released and the session marked taken over, so the requesting surface can claim the slot
  through the normal registry. A request is consumed only after the release lands — the
  requester polls the registry, it never sees a half-dead turn.
* ``session.takeover`` is the REQUESTER side: write the request, poll for the holder's release,
  then claim the slot onto the live session record. A holder from before this feature cannot
  release; when it is provably between turns (no marker of its own, on a surface whose turns
  write markers) the guarded registry steal retires its entry, with a restore when the steal
  raced a fresh turn.

Requests carry no authority: ownership still lives in the lease registry alone.
"""

from __future__ import annotations

import contextlib
import logging
import os
import threading
import time

from tui_gateway.method_ctx import HandlerRegistry, bind_module

_registry = HandlerRegistry()
method = _registry.method

logger = logging.getLogger(__name__)

_WATCH_INTERVAL_S = 2.0  # watcher scan cadence; each tick early-outs with no requests on disk
_REQUEST_WAIT_S = 12.0  # the requester's total budget for the holder to release
_STEAL_AFTER_S = 6.0  # cooperative window before a provably-idle old holder loses its entry
_REQUEST_POLL_S = 0.25  # the requester's registry poll cadence while the holder settles
_ACT_ON_REQUEST_MAX_AGE_S = 60.0  # older = abandoned (the requester polls well under this)
_STEAL_MIN_LEASE_AGE_S = 3.0  # a just-claimed lease's writer may not have written its marker yet
# Surfaces whose serving processes write a turn marker on every turn: that marker is the fence
# proving "between turns", so only these holders may ever lose their entry to a steal. Anything
# else (cli, messaging gateway, unknown) either releases cooperatively or is left alone.
_STEALABLE_SURFACES = frozenset({"desktop", "mobile"})


def _start_takeover_watcher() -> None:
    """Start the daemon that honours takeover requests this process can release (idle loop)."""

    def _loop():
        while True:
            time.sleep(_WATCH_INTERVAL_S)
            with contextlib.suppress(Exception):
                _takeover_watch_once()

    threading.Thread(target=_loop, daemon=True, name="session-takeover").start()


def _takeover_watch_once() -> None:
    from hermes_mobile_takeover.requests import pending_takeover_requests

    holders = _leased_holders_by_key()
    if not holders:
        return
    for home, by_key in holders.items():
        for request in pending_takeover_requests(registry_home=home):
            for sid, session in by_key.get(str(request.get("session_key") or ""), ()):
                _release_session_for_takeover(request, sid, session, home)


def _leased_holders_by_key() -> dict:
    """``{home: {session_key: [(sid, session)]}}`` for live sessions holding an unreleased lease.

    Snapshot under ``_sessions_lock``; every release decision is re-taken later under the
    session's own guards.
    """
    out: dict = {}
    with _sessions_lock:
        for sid, session in _sessions.items():
            if session.get("_finalized"):
                continue
            lease = session.get("active_session_lease")
            if lease is None or getattr(lease, "released", False) or not getattr(lease, "enabled", True):
                continue
            key = str(session.get("session_key") or "")
            if not key:
                continue
            out.setdefault(_session_home(session), {}).setdefault(key, []).append((sid, session))
    return out


def _request_still_live(request: dict) -> bool:
    """A request whose requester died or that sat unclaimed for a minute is abandoned: the
    holder must not interrupt a user's live turn for it."""
    try:
        age = time.time() - float(request.get("requested_at") or 0)
    except (TypeError, ValueError):
        return False
    if age > _ACT_ON_REQUEST_MAX_AGE_S or age < 0:
        return False
    try:
        from hermes_cli.active_sessions import _pid_liveness

        state = _pid_liveness(request.get("requester_pid"), request.get("requester_process_start"))
    except Exception:
        state = None
    return state is not False  # True/None: act; False: the requester is gone


def _session_turn_live(session: dict) -> bool:
    """A turn is running (or its compute host is mid-flight): the lease may NOT be released yet."""
    with session["history_lock"]:
        return bool(session.get("running") or session.get("_compute_host_turn_id") or session.get("inflight_turn"))


def _release_session_for_takeover(request: dict, sid: str, session: dict, home) -> None:
    from hermes_mobile_takeover.requests import clear_takeover_request

    key = str(request.get("session_key") or "")
    if not _request_still_live(request):
        return
    if _session_turn_live(session):
        if not session.get("_takeover_interrupt_requested"):
            session["_takeover_interrupt_requested"] = True
            logger.info("Session %s: takeover requested by %s — interrupting the live turn",
                        key, request.get("surface") or "another surface")
            with contextlib.suppress(Exception):
                _interrupt_session_turn(sid, session, request_id=f"takeover-{key}")
        return  # request stays: re-checked next tick, released only once the turn has settled
    if not _release_active_session_slot(session):
        return  # registry unavailable: leave the request for the next tick
    session.pop("_takeover_interrupt_requested", None)
    session["_lease_taken_over"] = True  # no longer ours: its finalize must not end the row like an owner
    clear_takeover_request(key, registry_home=home, requester_pid=request.get("requester_pid"))
    _emit("session.taken_over", sid, {"session_id": key, "by": str(request.get("surface") or ""), "forced": False})
    logger.info("Session %s released to %s (takeover)", key, request.get("surface") or "another surface")


def _entry_pid(entry: dict) -> int:
    try:
        return int(entry.get("pid") or 0)
    except (TypeError, ValueError):
        return 0


def _steal_fence(holder: dict, key: str, home) -> bool:
    """Provably between turns? Only then may an old (pre-watcher) holder lose its entry."""
    from tui_gateway.turn_marker import marker_writer_state, read_turn_marker

    if str(holder.get("surface") or "") not in _STEALABLE_SURFACES:
        return False
    try:
        lease_age = time.time() - float(holder.get("started_at"))
    except (TypeError, ValueError):
        return False  # age unprovable: never steal on it (also covers a missing started_at)
    if not lease_age >= _STEAL_MIN_LEASE_AGE_S:  # fresh claim — or a future timestamp (skew)
        return False
    marker = read_turn_marker(home, key)
    if isinstance(marker, dict) and marker_writer_state(marker) != "dead":
        return False  # alive turn (or unprovable): never steal from under it
    return True


def _steal_lost_race(key: str, home) -> bool:
    """A marker that appeared after the steal means the old holder started a turn in the window
    between the fence check and the removal — the caller must restore its entry and stand down."""
    from tui_gateway.turn_marker import marker_writer_state, read_turn_marker

    marker = read_turn_marker(home, key)
    return isinstance(marker, dict) and marker_writer_state(marker) != "dead"


@method("session.takeover")
def _handle_session_takeover(rid, params: dict) -> dict:
    """Pull this session's ownership to this surface (see the module docstring).

    Returns ``status``: ``already`` (no other holder), ``released`` (the holder released),
    ``stolen`` (an idle pre-watcher holder's entry was retired). Refusals carry
    ``data.reason``: ``TAKEOVER_BUSY`` (holder's turn would not settle; ``holder_surface``
    names it), ``TAKEOVER_RACED`` (the holder started a fresh turn mid-pull), or the
    underlying slot-refusal reason (e.g. a capacity cap — takeover cannot help).
    """
    session, err = _sess_nowait(params, rid)
    if err:
        return err
    from hermes_cli.active_sessions import SESSION_NOT_OWNED
    from hermes_mobile_takeover.registry import (
        active_session_holder,
        restore_stolen_session,
        steal_active_session,
    )
    from hermes_mobile_takeover.requests import clear_takeover_request, write_takeover_request

    sid = str(params.get("session_id") or "")
    key = str(session.get("session_key") or "")
    home = _session_home(session)
    lease = session.get("active_session_lease")
    if not key or (lease is not None and not getattr(lease, "released", False) and getattr(lease, "enabled", True)):
        return _ok(rid, {"status": "already", "holder_surface": None})

    deadline = time.monotonic() + _REQUEST_WAIT_S
    steal_at = time.monotonic() + _STEAL_AFTER_S
    request_written = False
    stole = False
    holder: dict | None = None
    while True:
        lease, refusal = _claim_active_session_slot(
            key, live_session_id=sid, surface=_session_source(session), profile_home=session.get("profile_home"),
        )
        if refusal is None:
            _attach_lease(session, lease)
            if request_written:
                clear_takeover_request(key, registry_home=home, requester_pid=os.getpid())
            status = "stolen" if stole else ("released" if request_written else "already")
            logger.info("Session %s takeover complete (%s) on sid=%s", key, status, sid)
            return _ok(rid, {"status": status, "holder_surface": str((holder or {}).get("surface") or "") or None})
        reason = getattr(refusal, "reason", None)
        if reason != SESSION_NOT_OWNED:
            return _err(rid, 4090, str(refusal), {"reason": reason or "SESSION_BUSY"})
        now = time.monotonic()
        if now >= deadline:
            break
        holder = active_session_holder(key, registry_home=home)
        if holder is None:
            time.sleep(_REQUEST_POLL_S / 5)  # released mid-flight: re-claim without hammering the registry
            continue
        if not request_written:
            write_takeover_request(key, surface=_session_source(session), registry_home=home)
            request_written = True
        if not stole and now >= steal_at and _steal_fence(holder, key, home):
            holder_pid = _entry_pid(holder)
            removed = steal_active_session(key, held_by_pid=holder_pid, registry_home=home) if holder_pid else None
            if removed is not None:
                if _steal_lost_race(key, home):
                    restore_stolen_session(removed, registry_home=home)
                    clear_takeover_request(key, registry_home=home, requester_pid=os.getpid())
                    return _err(rid, 4090, "This chat started a new turn on its current device while "
                                           "pulling; try again once it is idle.",
                                {"reason": "TAKEOVER_RACED", "holder_surface": str(holder.get("surface") or "")})
                stole = True
            continue
        time.sleep(_REQUEST_POLL_S)

    clear_takeover_request(key, registry_home=home, requester_pid=os.getpid())
    surface = str((holder or {}).get("surface") or "")
    return _err(rid, 4090, "This chat is in use on another device and its turn has not finished; "
                           "stop it there, then pull again.",
                {"reason": "TAKEOVER_BUSY", "holder_surface": surface})


def register(server) -> None:
    """Publish this module's helpers onto ``server``, rebound to its globals."""
    bind_module(globals(), server, skip=("_",))
