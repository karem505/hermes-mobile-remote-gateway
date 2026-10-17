"""Registry operations the takeover needs, built on hermes_cli.active_sessions internals.

Lifted out of a core patch so `hermes update` can no longer drop them: they only read and
write the lease registry through its own lock and helpers.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Optional

from hermes_cli.active_sessions import (
    ActiveSessionRegistryError,
    _FileLock,
    _holds_session,
    _lease_paths,
    _read_live_entries,
    _write_entries,
)

logger = logging.getLogger(__name__)


def active_session_holder(session_id: str, *, registry_home: str | Path | None = None) -> Optional[dict[str, Any]]:
    """The live registry entry holding ``session_id`` (dead owners pruned first), or None."""
    key = str(session_id or "")
    if not key:
        return None
    state_path, lock_path = _lease_paths(registry_home=registry_home)
    with _FileLock(lock_path):
        try:
            loaded = _read_live_entries(
                state_path, track_liveness=True,
                warn="Active-session registry is unavailable; treating the session as unowned for lookup",
                target_session_id=key,
            )
        except ActiveSessionRegistryError:
            return None
        if loaded is None:
            return None
        raw_entries, entries = loaded
        if len(raw_entries) != len(entries):
            _write_entries(state_path, entries)
        for entry in entries:
            if str(entry.get("session_id") or "") == key:
                return dict(entry)
    return None


def steal_active_session(
    session_id: str, *, held_by_pid: int, registry_home: str | Path | None = None,
) -> Optional[dict[str, Any]]:
    """Force-drop the entry holding ``session_id`` ONLY while ``held_by_pid`` still holds it.

    The caller provides the safety fence (holder provably between turns). Returns the
    removed entry, or None when nothing was (or should have been) removed.
    """
    key = str(session_id or "")
    if not key or not held_by_pid:
        return None
    state_path, lock_path = _lease_paths(registry_home=registry_home)
    removed: Optional[dict[str, Any]] = None
    with _FileLock(lock_path):
        try:
            loaded = _read_live_entries(
                state_path, track_liveness=True,
                warn="Active-session registry is unavailable; refusing to steal the session slot",
                target_session_id=key,
            )
        except ActiveSessionRegistryError:
            return None
        if loaded is None:
            return None
        raw_entries, entries = loaded
        kept: list[dict[str, Any]] = []
        for entry in entries:
            if removed is None and str(entry.get("session_id") or "") == key:
                try:
                    same_holder = int(entry.get("pid") or -1) == int(held_by_pid)
                except (TypeError, ValueError):
                    same_holder = False
                if not same_holder:
                    _write_entries(state_path, entries)
                    return None
                removed = dict(entry)
                continue
            kept.append(entry)
        if removed is None:
            if len(raw_entries) != len(entries):
                _write_entries(state_path, entries)
            return None
        _write_entries(state_path, kept)
    logger.info("Stole active session %s from pid=%s surface=%s", key, removed.get("pid"), removed.get("surface"))
    return removed


def restore_stolen_session(entry: dict[str, Any], *, registry_home: str | Path | None = None) -> bool:
    """Put back an entry removed by ``steal_active_session`` when the slot is still free."""
    if not isinstance(entry, dict) or not str(entry.get("session_id") or ""):
        return False
    state_path, lock_path = _lease_paths(registry_home=registry_home)
    with _FileLock(lock_path):
        try:
            loaded = _read_live_entries(
                state_path, track_liveness=True,
                warn="Active-session registry is unavailable; cannot restore the stolen entry",
                target_session_id=str(entry.get("session_id")),
            )
        except ActiveSessionRegistryError:
            return False
        if loaded is None:
            return False
        entries = loaded[1]
        if _holds_session(entries, str(entry.get("session_id"))):
            return False
        entries.append(entry)
        _write_entries(state_path, entries)
        return True
