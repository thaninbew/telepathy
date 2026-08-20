# Telepathy

Telepathy is an experimental native macOS utility that transfers working
context to the display you turn toward. It restores that display's recent
eligible window and pointer position, while ordinary keyboard and mouse input
continue through macOS unchanged. Camera processing stays on the Mac.

## Current MVP

- Head-led display classification from AVFoundation and Apple Vision.
- No head or gaze selection between apps on the same display.
- Last eligible window and last physical pointer position remembered per display.
- Automatic, dwell, configurable-keyboard, and middle-mouse activation.
- Left Shift default shortcut, configurable Switch delay, and optional Auto-return.
- A stable-only edge bloom for armed, dwell-progress, and confirmed states.
- A macOS or custom accent shared by the app, bloom, indicator, and calibration.
- Independent controls for the bloom, pointer transfer, and Experimental gaze ring.
- Saved Full Calibration profiles plus Quick Recenter for posture changes.
- Physical mouse suppression and `Command-Option-Escape` emergency pause.

Facial confirmation is intentionally excluded because a fixed laptop camera
cannot reliably see a wink, open mouth, or tongue while the user faces an
off-axis display.

## Build and run

Requirements: macOS 14 or newer and Xcode Command Line Tools.

```sh
swift test
./scripts/install-app.sh
```

The installer opens `~/Applications/Telepathy.app`. Open the control window from
the menu-bar eye. Telepathy never places permission messages over the desktop.
Local ad-hoc updates may require granting Accessibility access again.

Run **Full Calibration** after a new display arrangement. Its guided target
captures natural posture variation, covers each display perimeter, then checks
unseen positions before replacing the saved profile. It takes roughly 45
seconds for two displays. Run **Quick Recenter** after a meaningful posture,
viewing-distance, or laptop-lid change. Both profiles persist across relaunches.

Automatic activation is the default. **Dwell (650 ms)** means keeping the same
display in view for 650 ms; it needs no key or click. Keyboard activation
defaults to **Left Shift**. A quick press or a held Left Shift confirms the stable
target without blocking Shift's normal macOS behavior. Telepathy can record a
different modifier or ordinary key, and shows it in parentheses beside Keyboard.

Switch delay controls how long a target must remain stable. Auto-return can
restore the previous display after one to five seconds; physical mouse movement
or a click on the temporary display cancels that return and adopts it. Both
settings persist across relaunches.

The screen bloom is on by default. It waits for a stable target, creeps inward
from the physical display edge, and fades quickly. Choose the macOS accent or a
custom color in Telepathy; unreadably dark colors are lifted only as much as
needed for visible controls. The exact gaze-area ring is off by default because
fine eye-driven selection remains Experimental.

For development, `./scripts/build-app.sh debug` produces `build/Telepathy.app`.
The product contract and edge-case policy live in [`docs/DESIGN.md`](docs/DESIGN.md).

This is an early experiment, not assistive technology on which anyone should
currently depend.

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the
local build, privacy, and verification contract.

## License

MIT
