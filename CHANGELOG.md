# Changelog

## 1.1.0

Background activity panel for the open session.

- New panel above the composer lists long-running `terminal(background=true)` processes, delegated subagents and `/background` side agents that belong to the session you are looking at.
- Rows show live state (running, finished, failed with exit code), the tool a subagent is using, its model and tool count; the panel stays collapsed to one line until you open it.
- Streaming terminal output is captured per process and the detail view keeps the tail bounded, so a noisy job cannot grow the row without limit.
- Stop a running process (`process.kill`) or a live subagent (`subagent.interrupt`); dismiss finished rows. A failure to stop keeps the row so it can be retried.
- Finished rows clear themselves after a short linger, failures stay longer, and switching or closing a session drops the previous session's rows.
- Hydrates from `process.list` / `subagent.list` on open and every few seconds, so work started before the app connected (or while the phone slept) still appears.

## 1.0.0

First public Android community release.

- Authenticated Hermes gateway access over a private Tailscale network.
- Streaming chat, sessions, model search and English Thinking levels.
- Steering, queued follow-ups and turn-bound attachment handling.
- Received image/file cards and authenticated downloads.
- Foreground connection service and local completion notifications.
- Shared confirmation/feedback components and explicit model-switch approval.
- Private installation defaults removed from the public app.
- Dedicated release signing, checksum manifest and Android CI build artifacts.

Known limits: Arabic UI only; ARM64 release; background delivery is not cloud push; backend compatibility depends on the gateway version. See the README before deployment.
