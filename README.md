# Telepathy

Telepathy is an experimental macOS utility that moves window focus and the
pointer toward where you look. It uses the Mac camera, Apple's Vision framework,
and the macOS Accessibility API. All processing stays on the Mac.

The first milestone is intentionally narrow: learn a gaze-to-screen mapping
from ordinary clicks, visualize the estimate in a debug overlay, and transfer
focus between windows when the mouse is idle. The pointer moves once when focus
crosses into another window. It does not continuously chase your eyes.

## Current MVP

- Native AVFoundation camera capture and Vision face, eye, and pupil landmarks.
- Passive local calibration from ordinary mouse clicks.
- A click-through debug overlay showing raw gaze, filtered gaze, and the target window.
- Direct macOS window activation through the Accessibility API.
- One-time pointer relocation to the predicted gaze point after a focus transfer.
- Physical mouse suppression, short anti-bounce timing, and `Command-Option-Escape` emergency pause.
- Menu-bar controls for tracking, debugging, pointer warping, and calibration reset.

## Build and run

Requirements: macOS 14 or newer and Xcode Command Line Tools.

```sh
swift test
./scripts/run-app.sh
```

The first launch requests Camera and Accessibility access. Telepathy initially
learns from clicks: look at the control you are clicking and use several
different areas of the desktop. Focus transfer begins after the overlay changes
from `LEARNING` to `TRACKING`.

The build script produces `build/Telepathy.app` and signs it ad hoc. Rebuilding
an ad-hoc app can require macOS privacy permissions to be granted again.

Development is tracked in GitHub issues. The product and technical direction
live in [`docs/DESIGN.md`](docs/DESIGN.md).

This is an early experiment, not assistive technology on which anyone should
currently depend.

## License

MIT
