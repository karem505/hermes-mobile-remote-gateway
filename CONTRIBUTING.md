# Contributing

Issues and pull requests are welcome. This is an independent Android client, not the upstream Hermes Agent repository.

- Use English for issue reports, documentation and pull-request descriptions.
- Keep the current Arabic RTL app layout usable on narrow screens and with enlarged text. Model identifiers and Thinking levels remain English.
- Add a failing regression test before changing behavior; run analysis and the full suite after the fix.
- Test Android behavior on a real phone when possible. Widget tests do not prove Doze reliability or notification delivery.
- Never silently confirm expensive/context-sensitive model changes or replay side-effecting RPCs after reconnecting.
- Preserve per-turn attachment ownership and drafts on failed delivery.
- Do not include provider credentials, tailnet hostnames, session text or signing keys in contributions. Use generic examples and sanitized captures.
- Include Flutter/Android/backend versions and reproducible steps. Clearly separate observations from assumptions.

See [BUILDING.md](docs/BUILDING.md) for commands and [SECURITY.md](SECURITY.md) for private vulnerability reporting.
