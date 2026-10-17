"""Cross-surface session takeover requests ("pull this chat to my device").

A takeover is COOPERATIVE and advisory. The surface that wants a session another
live process is holding writes a small request file under
``$HERMES_HOME/runtime/takeover_requests/``; the holding process's watcher
(``hmt_takeover.py`` in this plugin) asks its own turn to stop, and once the
turn has settled it releases the session's active-session lease, which lets the
requester claim the slot through the normal registry.

Requests never carry authority: ownership still lives in the lease registry
alone (``hermes_cli/active_sessions.py``), so a stale, forged or unreadable
request can only fail to help — never widen access. Requests self-expire.
"""

from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Any, Optional

from hermes_constants import get_hermes_home

logger = logging.getLogger(__name__)

# A request older than this is presumed abandoned (the requester gave up or its
# poll timed out) and must not keep a holder reacting to a much later pull.
REQUEST_TTL_S = 180.0

_REQUEST_DIR = "takeover_requests"


def _registry_home(registry_home: str | Path | None = None) -> Path:
    return Path(registry_home) if registry_home is not None else Path(get_hermes_home())


def takeover_dir(registry_home: str | Path | None = None) -> Path:
    return _registry_home(registry_home) / "runtime" / _REQUEST_DIR


def _request_path(session_key: str, registry_home: str | Path | None = None) -> Path:
    # The key is a session id (``YYYYMMDD_HHMMSS_hex`` / ``claude_hex``); sanitize
    # defensively so a hostile key can never escape the directory.
    safe = "".join(c if (c.isalnum() or c in "-_.") else "_" for c in str(session_key))[:200]
    return takeover_dir(registry_home) / f"{safe}.json"


def _own_start_time() -> Optional[float]:
    try:
        import psutil

        return float(psutil.Process(os.getpid()).create_time())
    except Exception:
        return None


def write_takeover_request(
    session_key: str, *, surface: str, registry_home: str | Path | None = None,
    pid: int | None = None,
) -> Optional[Path]:
    """Create (or refresh) the takeover request for ``session_key``. Atomic replace."""
    key = str(session_key or "").strip()
    if not key:
        return None
    entry = {
        "session_key": key,
        "surface": str(surface or ""),
        "requester_pid": int(pid if pid is not None else os.getpid()),
        "requester_process_start": _own_start_time(),
        "requested_at": time.time(),
    }
    path = _request_path(key, registry_home)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
        tmp.write_text(json.dumps(entry), encoding="utf-8")
        os.replace(tmp, path)
        return path
    except OSError as exc:
        logger.warning("Could not write takeover request for %s: %s", key, exc)
        return None


def read_takeover_request(
    session_key: str, *, registry_home: str | Path | None = None, max_age_s: float = REQUEST_TTL_S,
) -> Optional[dict[str, Any]]:
    return _load_request(_request_path(session_key, registry_home), max_age_s=max_age_s)


def _load_request(path: Path, *, max_age_s: float) -> Optional[dict[str, Any]]:
    try:
        entry = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        logger.warning("Ignoring unreadable takeover request at %s", path)
        return None
    if not isinstance(entry, dict) or not str(entry.get("session_key") or "").strip():
        return None
    try:
        age = time.time() - float(entry.get("requested_at") or 0)
    except (TypeError, ValueError):
        age = max_age_s + 1
    if age > max_age_s or age < -max_age_s:  # stale, or clock skew from the far future
        with _suppress_os_error():
            path.unlink()
        return None
    return entry


def pending_takeover_requests(
    *, registry_home: str | Path | None = None, max_age_s: float = REQUEST_TTL_S,
) -> list[dict[str, Any]]:
    """Live requests, stale ones removed. Never raises; an unreadable dir reads as empty."""
    directory = takeover_dir(registry_home)
    try:
        names = sorted(directory.iterdir())
    except FileNotFoundError:
        return []
    except OSError:
        logger.warning("Could not scan takeover requests at %s", directory, exc_info=True)
        return []
    entries = []
    for path in names:
        if path.suffix != ".json":
            continue
        entry = _load_request(path, max_age_s=max_age_s)
        if entry is not None:
            entries.append(entry)
    return entries


def clear_takeover_request(
    session_key: str, *, registry_home: str | Path | None = None, requester_pid: int | None = None,
) -> bool:
    """Drop the request for ``session_key``. With ``requester_pid``, only when it belongs
    to that requester (the holder acknowledges the exact request it consumed)."""
    path = _request_path(session_key, registry_home)
    if requester_pid is not None:
        entry = _load_request(path, max_age_s=REQUEST_TTL_S)
        if entry is None:
            return False
        if int(entry.get("requester_pid") or -1) != int(requester_pid):
            return False
    try:
        path.unlink()
        return True
    except FileNotFoundError:
        return False
    except OSError as exc:
        logger.warning("Could not clear takeover request for %s: %s", session_key, exc)
        return False


class _suppress_os_error:
    def __enter__(self) -> None:
        return None

    def __exit__(self, exc_type, exc, tb) -> bool:
        return exc_type is not None and issubclass(exc_type, OSError)
