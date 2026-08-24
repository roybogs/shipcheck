# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability.

Use GitHub's private vulnerability reporting for this repository when available. If that channel is unavailable, open a minimal issue asking for a private contact without including exploit details.

ShipCheck processes release artifacts on the caller's own GitHub macOS runner. The action does not upload artifacts to ShipCheck infrastructure.

## Scope

Security-sensitive areas include:

- command or path injection through action inputs
- unsafe archive extraction or disk-image handling
- incorrect signature, Gatekeeper, or notarization conclusions
- receipt tampering or misleading PASS results
- unexpected network access or artifact exfiltration

## Supported versions

Until v1 is tagged, only the current `main` branch is supported. After v1, the latest major release line will receive security fixes.
