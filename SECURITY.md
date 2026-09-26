# Security policy

## Reporting

Please use GitHub's private **Report a vulnerability** feature on this repository rather than a public issue for exploitable bugs. Do not include real credentials, raw session histories, private hostnames or unredacted screenshots. If private reporting is unavailable, open a public issue requesting a private contact channel without disclosing exploit details or secrets.

## Trust model

This app connects to a user-controlled Hermes backend. That agent can access tools and files on its host. Tailscale limits network reachability; Hermes password authentication is still required. Restrict tailnet access to intended users and keep both client and server updated.

The app supports cleartext HTTP for private-tailnet deployments. Tailscale encrypts traffic in transit between its nodes, but plain HTTP itself does not. Prefer tailnet-only HTTPS through Tailscale Serve and never send credentials to a public plain-HTTP endpoint.

Credentials/cookies are stored using Flutter Secure Storage. Files downloaded to device storage, notification previews and screenshots can still disclose sensitive data. Configure Android lock-screen notification privacy accordingly. Voice and image content is sent to your configured backend and may be processed by its selected providers.

GitHub Release APKs use a dedicated maintainer signing key. Actions artifacts use a development key unless a release-signing environment is explicitly provided. Verify release checksums and download only from this repository's Releases. A checksum detects corruption; it does not independently establish trust in a compromised publishing account.

No telemetry/analytics service is intentionally configured in the client source. The Hermes backend, selected model providers, Android and Tailscale have their own behavior and policies. The app makes no guarantee of notification delivery after force-stop, process termination or network loss.

Only the current release is maintained. This early community project has not had an independent security audit.
