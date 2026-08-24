# Changelog

## v1.0.0

Initial public release.

- verify final `.app`, `.dmg`, `.zip`, and `.pkg` artifacts on macOS runners
- strict nested code-signature validation
- Gatekeeper assessment enabled by default
- stapled notarization-ticket validation enabled by default
- expected bundle ID, version, build, Team ID, and architecture gates
- SHA-256 artifact identity
- entitlements snapshot hash
- machine-readable JSON receipt
- receipt provenance for repository, commit, ref, workflow/run, and runner identity
- GitHub Actions step summary and outputs
- optional launch smoke test
- CI acceptance coverage for `.app`, `.zip`, and `.dmg`
- negative acceptance test proving identity drift blocks a release
- no ShipCheck backend or artifact upload required
