"""mobile-session-takeover: the backend half of Hermes Mobile's "Pull to mobile".

Adds the ``session.takeover`` JSON-RPC method and the holder-side release watcher to every
``hermes serve`` / TUI gateway process of this Hermes home, without editing Hermes core files
(core edits are stashed and dropped by ``hermes update``).

Hermes has no plugin API for gateway RPC methods, so this installs a post-import hook on
``tui_gateway.server`` and registers through the gateway's own seams (contract registry +
``register_method`` + ``method_ctx.bind_module``), exactly as a built-in split module would.
If Hermes itself ever ships ``session.takeover``, the plugin stands down.
"""

from __future__ import annotations

import importlib.machinery
import logging
import sys

from . import hmt_registry, hmt_requests

logger = logging.getLogger(__name__)

_TARGET = "tui_gateway.server"
_ALIAS = "hermes_mobile_takeover"

# Stable absolute names for imports inside handler bodies (they are rebound onto server
# globals, where a relative import would resolve against tui_gateway).
sys.modules.setdefault(_ALIAS, sys.modules[__name__])
sys.modules.setdefault(f"{_ALIAS}.requests", hmt_requests)
sys.modules.setdefault(f"{_ALIAS}.registry", hmt_registry)
requests = hmt_requests  # attribute access for ``import hermes_mobile_takeover.requests``
registry = hmt_registry

_installed = False


def _declare_contracts() -> None:
    from tui_gateway.contracts.base import Payload, Result
    from tui_gateway.contracts.common import SessionParams
    from tui_gateway.contracts.registry import EVENTS, METHODS, event, method

    if "session.takeover" not in METHODS:
        class SessionTakeoverParams(SessionParams):
            pass

        class SessionTakeoverResult(Result):
            status: str  # already | released | stolen
            holder_surface: str | None = None

        method("session.takeover", params=SessionTakeoverParams, result=SessionTakeoverResult,
               doc="Pull this session's ownership to this surface (mobile-session-takeover plugin).")
    if "session.taken_over" not in EVENTS:
        class SessionTakenOverPayload(Payload):
            session_id: str
            by: str
            forced: bool

        event("session.taken_over", SessionTakenOverPayload,
              doc="This process released a live session's ownership to another surface (pull).")


def install(server) -> bool:
    """Register the method and start the watcher on an imported ``tui_gateway.server``."""
    global _installed
    if _installed:
        return False
    if "session.takeover" in getattr(server, "_methods", {}):
        logger.info("mobile-session-takeover: Hermes already provides session.takeover; standing down")
        _installed = True
        return False
    _declare_contracts()
    from . import hmt_takeover

    hmt_takeover.register(server)
    server._start_takeover_watcher()
    _installed = True
    logger.info("mobile-session-takeover: session.takeover registered")
    return True


class _ServerImportHook:
    """Run :func:`install` right after ``tui_gateway.server`` finishes importing."""

    def find_spec(self, fullname, path=None, target=None):
        if fullname != _TARGET:
            return None
        spec = importlib.machinery.PathFinder.find_spec(fullname, path)
        if spec is None or spec.loader is None:
            return spec
        original = spec.loader.exec_module

        def exec_module(module):
            original(module)
            try:
                install(module)
            except Exception:
                logger.exception("mobile-session-takeover: install failed")

        spec.loader.exec_module = exec_module
        return spec


def arm() -> None:
    server = sys.modules.get(_TARGET)
    if server is not None and hasattr(server, "_start_session_work"):
        try:
            install(server)
        except Exception:
            logger.exception("mobile-session-takeover: install failed")
        return
    if not any(isinstance(f, _ServerImportHook) for f in sys.meta_path):
        sys.meta_path.insert(0, _ServerImportHook())


def register(ctx) -> None:
    arm()


arm()
