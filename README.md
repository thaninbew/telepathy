# Telepathy

Telepathy is an experimental native macOS utility that transfers working
context to the display you turn toward. It restores that display's recent
eligible window and pointer position, while ordinary keyboard and mouse input
continue through macOS unchanged. Camera processing stays on the Mac.

## Current MVP

- Head-led display classification from AVFoundation and Apple Vision.
- No head or gaze selection between apps on the same display.
- Last eligible window and last physical pointer position remembered per display.
- Automatic, hold, wink, mouth-open, keyboard, and middle-mouse activation.
- A temporary warm-gold screen bloom for armed, hold-progress, and confirmed states.
- Independent controls for the bloom, pointer transfer, and Experimental gaze ring.
- Saved Full Calibration profiles plus Quick Recenter for posture changes.
- Physical mouse suppression and `Command-Option-Escape` emergency pause.

Tongue confirmation is intentionally deferred because public Vision landmarks
do not expose a reliable tongue signal.

## Build and run

Requirements: macOS 14 or newer and Xcode Command Line Tools.

```sh
swift test
./scripts/install-app.sh
```

The installer opens `~/Applications/Telepathy.app`. Open the control window from
the menu-bar eye. Telepathy never places permission messages over the desktop.
Local ad-hoc updates may require granting Accessibility access again.

Run **Full Calibration** after a new display arrangement. It visits the center
and corners of every active display and takes roughly 40 seconds for two
displays. Run **Quick Recenter** after a meaningful posture, viewing-distance,
or laptop-lid change. Both profiles persist across relaunches.

Automatic activation is the default. Hold adds visible progress; wink and
mouth-open confirm an armed display; keyboard uses `Command-Option-Space`; mouse
uses the middle button. Physical mouse movement always takes temporary control.

The screen bloom is on by default and disappears quickly. The exact gaze-area
ring is off by default because fine eye-driven selection remains Experimental.

For development, `./scripts/build-app.sh debug` produces `build/Telepathy.app`.
The product contract and edge-case policy live in [`docs/DESIGN.md`](docs/DESIGN.md).

This is an early experiment, not assistive technology on which anyone should
currently depend.

## License

MIT
