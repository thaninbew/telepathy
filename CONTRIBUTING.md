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

`./scripts/install-app.sh` installs an ad-hoc signed build in
`~/Applications/Telepathy.app`. macOS may require Accessibility access again
after a local replacement.

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
