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
- Explicit activation during physical mouse movement, enabled by default and configurable.
- A stable-only edge shine for armed, dwell-progress, and confirmed states.
- A macOS or custom accent shared by the app, shine, indicator, and calibration.
- Independent controls for the shine, pointer transfer, and Experimental gaze ring.
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

By default, explicit Left Shift or middle-mouse activation overrides the 280 ms
physical-mouse quiet period. Disable **Mouse movement** in Telepathy if all
handoffs should wait until the pointer is still. Automatic and Dwell always
preserve the quiet period.

Switch delay controls how long a target must remain stable. Auto-return can
restore the previous display after one to five seconds; physical mouse movement
or a click on the temporary display cancels that return and adopts it. Both
settings persist across relaunches.

The screen shine is on by default. A broad, five-stop light waits for a stable
target, creeps inward from the physical display edge, and fades quickly. It has
no perimeter stroke, blur, or persistent full-screen surface. Choose the macOS accent or a
custom color in Telepathy; unreadably dark colors are lifted only as much as
needed for visible controls. The exact gaze-area ring is off by default because
fine eye-driven selection remains Experimental.

Normal handoff uses a 15 fps head-only Vision request. Full eye landmarks run
only during calibration or when the Experimental gaze indicator is enabled.
Telepathy stops camera capture while Off, asleep, locked, untrusted, or unable
to hand off between displays. See [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md)
for the runtime budget and measurement procedure.

For development, `./scripts/build-app.sh debug` produces `build/Telepathy.app`.
The product contract and edge-case policy live in [`docs/DESIGN.md`](docs/DESIGN.md).

This is an early experiment, not assistive technology on which anyone should
currently depend.

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the
local build, privacy, and verification contract.

## License

MIT
