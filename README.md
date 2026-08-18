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
- A native on/off switch plus menu-bar controls for debugging, pointer warping, and calibration reset.

## Build and run

Requirements: macOS 14 or newer and Xcode Command Line Tools.

```sh
swift test
./scripts/install-app.sh
```

The installer opens `~/Applications/Telepathy.app`. After that, open Telepathy
from Spotlight, the Applications folder, or with `./scripts/run-app.sh`. Normal
launches do not rebuild the app, so macOS sees the same installed bundle instead
of a new ad-hoc build each time.

On first use, allow Camera access. Open Telepathy from its menu-bar eye and use
the Accessibility button if window focusing is not yet authorized. That button
is deliberate: Telepathy never throws an Accessibility message over the
desktop. Because local builds are signed ad hoc, installing a new build can
require granting access again; simply reopening the installed app should not.

Telepathy initially learns from clicks. Look at each target as you click it and
use at least ten targets spread across the desktop. When the control window says
`Tracking`, look at another visible window. Telepathy focuses that window and
moves the pointer once; keyboard and mouse input then work normally there.
Physical mouse movement temporarily overrides gaze. Use the on/off switch or
`Command-Option-Escape` to pause or resume at any time.

The debug overlay is on by default while tracking. It contains only a gold gaze
dot, a faint raw-estimate cross, and the candidate-window perimeter. Turn it off
from the menu-bar eye when it is no longer useful.

For development, `./scripts/build-app.sh debug` produces `build/Telepathy.app`.
Do not use that transient bundle as the everyday launch target.

Development is tracked in GitHub issues. The product and technical direction
live in [`docs/DESIGN.md`](docs/DESIGN.md).

This is an early experiment, not assistive technology on which anyone should
currently depend.

## License

MIT
