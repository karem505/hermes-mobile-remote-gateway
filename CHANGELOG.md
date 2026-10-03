# Changelog

## 1.3.0

Liquid Glass design, tuned for 120 Hz Android displays.

### Design
- The top bar and composer float as glass over the transcript, so messages scroll beneath them; the drawer, model sheet, dialogs, cards and page headers use the same glass surfaces.
- Glass is a warm tint with a lit top edge and a specular rim, built on the existing colour tokens (no palette change).
- Every control on a glass surface (attach, commands, model chip, voice, send, steer, queue, dialog actions) is an inset glass drop; disabled controls show an empty rim.
- Presses squash and spring back like a liquid drop; dialogs and revealed surfaces materialize (settle in from slightly oversized); page routes slide in with a soft overshoot.
- Model sheet: Thinking levels use compact labels (X-High, Med) that never clip, and the selected model is marked with a glass check instead of a flat disc.

### Performance
- No refraction shaders or live backdrop blur: on a Snapdragon 7-class phone a live blur behind the bars capped scrolling at ~67-77 fps; without it the transcript scrolls at ~100-110 fps on a 120 Hz panel. `--dart-define=GLASS_BLUR=true` restores the blur for comparison.
- The app asks Android for the display's fastest refresh rate on start and resume.
- Spinners and live status dots repaint on their own layers; bar heights update through notifiers instead of rebuilding the screen.
- Optional side-by-side build: `HERMES_APP_VARIANT=<name>` produces a separate application id and label for experiments.

## 1.2.0

Two cross-device features on top of 1.1.0.

### Pull a session between devices
- A send refused because another device owns the session (`SESSION_NOT_OWNED`) now offers to pull it: a dialog explains the session is open elsewhere and pulls it to the phone on request, then re-sends the same draft automatically once ownership moved.
- The draft is restored to the composer on refusal, so nothing typed is lost.
- The backend half (`session.takeover` RPC + `session.taken_over` event + cross-surface lease transfer) lands in the gateway; a desktop plugin contributes "اسحب الجلسة إلى هذا الجهاز" to the command palette and toasts when a session is pulled away from that window.
- While a turn is actively running on the other surface the pull waits or refuses (`TAKEOVER_BUSY`) instead of corrupting the running turn.

### Saved gateways (البوابات والاتصال)
- New screen listing saved gateways: switch between a local Tailscale serve and a public remote gateway over HTTPS with one tap; the active gateway is checked and shown in the drawer.
- Add or edit a gateway (name, address, username, password) with a Test connection action that proves login and the WebSocket ticket before saving, and per-gateway delete behind a confirmation.
- Passwords live per gateway in the platform keychain; existing single-login installs migrate into the first saved gateway on update.
- URLs are normalized by scheme: plain-HTTP hosts default to `:9131`, `https://` keeps the standard port (no Tailscale needed for the remote gateway).

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
