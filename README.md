# ShipCheck

[![CI](https://github.com/roybogs/shipcheck/actions/workflows/ci.yml/badge.svg)](https://github.com/roybogs/shipcheck/actions/workflows/ci.yml)

Verify the exact macOS release artifact before you ship it.

ShipCheck is a GitHub Action for checking a final `.app`, `.dmg`, `.zip`, or `.pkg` on a macOS runner. It verifies code signing, Gatekeeper acceptance, notarization/stapling, bundle identity, version/build metadata, architectures, and artifact integrity, then emits a machine-readable receipt plus a GitHub Actions summary.

**No ShipCheck account, server, or artifact upload is required.** Verification runs on your own GitHub macOS runner using Apple's local release-security tools.

## Quick start

```yaml
name: Verify macOS release

on:
  workflow_dispatch:
  release:
    types: [published]

jobs:
  shipcheck:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      # Produce or download the exact artifact customers will receive before this step.

      - name: ShipCheck
        uses: roybogs/shipcheck@main
        with:
          artifact: dist/MyApp.dmg
          expected-bundle-id: com.example.MyApp
          expected-team-id: ABCDE12345
          expected-architectures: arm64 x86_64
```

For production releases, pin ShipCheck to `roybogs/shipcheck@v1` once the v1 tag is published.

## What it checks

- SHA-256 of the exact release artifact
- package/container extraction for `.dmg` and `.zip`
- strict nested code-signature verification for apps
- package signature verification for `.pkg`
- Gatekeeper assessment
- stapled notarization ticket validation
- bundle identifier
- short version and build version
- signing Team ID
- executable architectures
- entitlements snapshot hash
- optional launch smoke test for apps
- JSON release receipt
- human-readable GitHub Actions summary

## Why after packaging matters

A successful Xcode archive or notarization command does not prove that the exact DMG/ZIP/PKG customers receive still has the intended identity, architecture, signature, or ticket. Run ShipCheck on the final file after your packaging/download step and before publishing or promoting it.

## Inputs

| Input | Required | Default | Purpose |
| --- | --- | --- | --- |
| `artifact` | yes | | Path to the final `.app`, `.dmg`, `.zip`, or `.pkg` |
| `expected-bundle-id` | no | | Fail if the app bundle ID differs |
| `expected-version` | no | | Fail if `CFBundleShortVersionString` differs |
| `expected-build` | no | | Fail if `CFBundleVersion` differs |
| `expected-team-id` | no | | Fail if the signing Team ID differs |
| `expected-architectures` | no | | Space/comma-separated exact architecture set |
| `require-gatekeeper` | no | `true` | Require Gatekeeper acceptance |
| `require-notarization` | no | `true` | Require a valid stapled notarization ticket |
| `launch-smoke` | no | `false` | Launch an app briefly and confirm its executable stays alive |
| `receipt-path` | no | `shipcheck-receipt.json` | JSON receipt output path |

## Outputs

`status`, `bundle-id`, `version`, `build`, `team-id`, `architectures`, `sha256`, and `receipt-path`.

## Tested release paths

The repository's macOS acceptance gate builds and ad-hoc signs a fixture application, then verifies it directly and through both ZIP and DMG packaging. The gate also deliberately supplies the wrong bundle identifier and requires ShipCheck to reject it.

Gatekeeper and notarization are enabled by default for real release use; the self-test disables those two checks only because its fixture is intentionally ad-hoc signed rather than Developer ID notarized.

## Security and privacy

ShipCheck does not send your release artifact to a ShipCheck service. See [SECURITY.md](SECURITY.md) for vulnerability-reporting guidance and the security boundary.

## License

MIT
