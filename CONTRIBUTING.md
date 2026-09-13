# Contributing to Telepathy

Telepathy is a dependency-free native macOS experiment. Contributions should
keep camera frames on-device, use public Apple APIs, and preserve ordinary
keyboard and mouse behavior.

## Local setup

Requirements: macOS 14 or newer and Xcode Command Line Tools.

```sh
git clone https://github.com/thaninbew/telepathy.git
cd telepathy
swift test
./scripts/build-app.sh debug
```

Run `./scripts/setup-local-signing.sh` once before the first local installation.
It creates a dedicated local code-signing identity in the login Keychain.
`./scripts/install-app.sh` then updates the single canonical app at
`~/Applications/Telepathy.app` with that stable identity so local rebuilds do
not change its Accessibility identity. Development bundles use the separate
`app.telepathy.macos.development` identifier.

To remove the local identity later, open Keychain Access, search for **Telepathy
Local Development**, and delete its certificate and private key. The next
production installation will stop before replacing the app until another stable
identity is configured.

## Change contract

- Keep the main product display-level and head-led. Exact gaze selection stays
  Experimental.
- Do not store or transmit camera frames.
- Never suppress, buffer, or replay user input.
- Treat physical pointer activity and the emergency pause as authoritative.
- Add deterministic tests for policy, geometry, calibration, or persistence
  changes.
- Verify `swift test` and `./scripts/build-app.sh release` before opening a pull
  request.

Bug reports are most useful with the macOS version, display arrangement,
activation mode, whether Reduce Motion is enabled, and exact reproduction steps.
Do not attach camera frames or personal screen recordings unless you have
deliberately removed private content.
