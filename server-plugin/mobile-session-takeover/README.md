# mobile-session-takeover (Hermes server plugin)

The backend half of the app's **Pull to mobile** ("اسحب إلى الجوال") and of the desktop
plugin's **Pull session to this device**. It adds to every `hermes serve` / TUI gateway
process of a Hermes home:

- the `session.takeover` JSON-RPC method (requester side), and
- a small watcher that releases a session this process holds when another surface asks for it,
  after its running turn has settled. The holder's clients get a `session.taken_over` event.

Ownership still lives only in Hermes' active-session lease registry. Requests are advisory
files under `$HERMES_HOME/runtime/takeover_requests/`, so a stale or forged request can only
fail to help, never widen access. A holder from before this plugin (no watcher) loses its
entry only when it is provably between turns, and the entry is restored if that races a new turn.

## Why a plugin

Earlier this lived as uncommitted edits inside the Hermes checkout. `hermes update`
autostashes local edits and does not re-apply runtime patches, so the method disappeared after
an update and the app showed `unknown method: session.takeover`. A plugin under
`~/.hermes/plugins/` is outside the checkout and survives updates.

Hermes has no plugin API for gateway RPC methods yet, so the plugin installs a post-import hook
on `tui_gateway.server` and registers through the gateway's own seams (contract registry,
`register_method`, `method_ctx.bind_module`), as a built-in split module would. If Hermes itself
ships `session.takeover`, the plugin stands down.

## Install

```sh
cp -r server-plugin/mobile-session-takeover ~/.hermes/plugins/
hermes plugins enable mobile-session-takeover
systemctl --user restart hermes-serve.service   # or restart however you run `hermes serve`
```

Restart every backend that may hold sessions (the desktop app's backend too) so each one runs
the watcher. Check with a WebSocket call: `session.takeover` for an unknown id must answer
`session not found`, not `unknown method`.

## Tests

The tests use the Hermes test harness. From a Hermes checkout:

```sh
cp ~/.hermes/plugins/mobile-session-takeover/tests/test_session_takeover.py tests/tui_gateway/test_zz_takeover_plugin.py
# point _PLUGIN in the copy at ~/.hermes/plugins/mobile-session-takeover, then:
scripts/run_tests.sh tests/tui_gateway/test_zz_takeover_plugin.py
rm tests/tui_gateway/test_zz_takeover_plugin.py
```

Built against Hermes Agent 0.22.2. The plugin uses Hermes internals (`tui_gateway` session
records, `hermes_cli.active_sessions` registry helpers), so a large upstream refactor can break
it; the install check above shows that quickly.
