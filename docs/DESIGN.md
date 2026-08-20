# Telepathy design

## Product thesis

Telepathy turns visible attention into ordinary macOS display context. The main
product is not an eye-controlled mouse and does not continuously select windows.
Head direction chooses a display; the keyboard and mouse keep their normal
meaning inside that display.

The longer-term opportunity is more precise: look at a field, pane, control, or
text position and act there without navigation ceremony. That research remains
valuable, but it must not make the reliable display-switching product fragile.

## Main product contract

1. Capture the camera locally with AVFoundation and Vision.
2. Classify which configured display the user is facing from face position,
   yaw, and pitch. Eye features do not override the display decision.
3. Ignore all movement that remains on the currently active display.
4. After the selected activation policy succeeds, restore the most recent
   eligible window on the target display's visible Space.
5. Restore the last physical pointer position on that display, clamped to its
   current visible bounds. Use the display center when no position is known.
6. Let all subsequent input flow through macOS normally.

macOS does not expose keyboard focus for an abstract display. Telepathy must
focus a window to implement a display handoff, but the product never uses head
or gaze to choose between applications on the same display.

### Window restoration policy

"Last focused" means the most recent eligible window, not the last window ever:

- The window must still exist, remain unminimized, belong to a visible app, and
  still be on the target display.
- It must be visible on that display's current Space. Telepathy does not summon
  another Space, unminimize a window, or reveal a hidden app.
- Closed, moved, hidden, transient, off-Space, and Telepathy-owned windows are
  discarded.
- A window spanning displays belongs to the display containing its largest
  area. Ties are resolved by the window center.
- If the remembered window is stale, use the frontmost eligible on-screen
  window on that display.
- If nothing qualifies, move only the pointer when pointer transfer is enabled;
  keyboard focus remains unchanged.
- Full-screen apps, Stage Manager sets, sheets, modal windows, and games are
  handled conservatively. Never force a Space transition to manufacture a
  successful-looking switch.

This is less gimmicky than focusing the window under a noisy point estimate. A
screen behaves like a durable workspace, while the exact app remains the user's
recent explicit choice.

## Activation grammar

Every activation method drives one state machine: `idle -> settling -> armed ->
commit`. Changing the candidate display resets the state. Physical mouse motion
and the post-transfer cooldown remain authoritative. Settling is deliberately
invisible so classifier indecision never becomes desktop flicker.

- **Automatic:** commit after the configured Switch delay.
- **Dwell (650 ms):** keep facing the candidate display for 650 ms. The screen bloom grows
  with progress, then the handoff commits without a second gesture.
- **Keyboard:** arm the target, then press or hold the recorded key. Left Shift
  is the default and keeps its ordinary macOS meaning.
- **Mouse:** arm the target, then press the middle mouse button.

Switch delay can be Instant, 90, 150, 250, 400, or 650 ms. Confirmation events
are observed, not buffered, suppressed, or replayed. The recorded key keeps its
ordinary macOS meaning after Telepathy observes it.

Wink, mouth-open, and tongue confirmation are not shipping modes. A fixed
laptop camera loses facial landmarks precisely when the user turns toward an
off-axis display, so those gestures fail at the moment they are needed. They
should return only if different hardware or a separately validated detector
removes that geometric limitation.

Automatic is the default. Confirmation modes are alternatives for people who
want more intent or for environments where reference glances are common.

## Authority and override rules

- The persistent power switch and `Command-Option-Escape` emergency shortcut
  stop all focus and pointer transfer.
- Physical pointer movement suspends automatic transfer for 280 ms.
- A target must remain stable and the 240 ms switch cooldown must expire.
- Low-confidence or uncalibrated classification does nothing.
- Cursor warping occurs once per display handoff, never continuously.
- Telepathy never suppresses, reroutes, or replays ordinary keyboard input.

### Temporary handoff

Auto-return is optional and off by default. When enabled, a successful handoff
starts a one, two, three, or five second timer that restores the origin display.
Physical pointer movement or a click on the temporary display cancels the timer
and adopts that display as the current workspace. Pointer activity that remains
on the origin does not. Disabling Telepathy, changing a relevant setting,
starting calibration, or changing the display layout also cancels it.

After an automatic return, Telepathy suppresses the temporary target until the
head prediction leaves it. This prevents an immediate bounce back while the
user is still facing that screen. A manual return to the origin never schedules
the inverse trip.

Active typing should eventually pin the current display context for a short
quiet interval, with an explicit persistent focus lock for editing, gaming, and
presentations. That override is still future work. The intended precedence is:
manual lock, active typing, physical mouse, then Telepathy.

## Calibration and adaptation

Calibration is intentional, local, saved per exact display layout, and never
launched as an unsolicited overlay.

### Full Calibration

Full Calibration is deliberately different from Quick Recenter. On every active
display it first holds a center target while the user moves naturally within
their normal seated posture, then glides through eight perimeter targets. The
progress ring advances only when fresh camera frames are accepted. Movement
between targets is never sampled. Once calibration starts, the target surface
contains no instructional text because competing text can pull fixation away
from the labeled target. Instructions appear only in the confirmation dialog
before sampling begins.

Two held-out targets per display form a final check. The new profile is saved
only when the head-only classifier identifies every display with at least 60%
per-display accuracy and 70% overall accuracy. Escape, lost tracking, or a
failed check preserves the previous profile. Two displays take roughly 45
seconds. The pass trains:

- a head-only nearest-neighbor display classifier for the main product; and
- the finer head-and-pupil desktop regression retained for Experimental mode.

The target moves smoothly within a display. Cross-display movement uses a brief
direction arrow before the target appears on the next display. The overlay
honors Reduce Motion by replacing the long glide with a short state change.

### Quick Recenter

Quick Recenter visits only the center of each display and appends a small set of
recent samples to the saved Full Calibration. It does not run posture-range,
perimeter-coverage, or held-out validation phases. It is intended for a changed
chair position, viewing distance, or laptop lid angle, not a changed display
layout.

Profiles are keyed by display identity, geometry, resolution, rotation, and
main-display assignment. A changed layout selects its matching saved profile or
requires Full Calibration. It never silently reuses incompatible geometry.

Ordinary non-confirmation clicks add local labels. For the main classifier, a
click's display is a strong coarse label even when its exact point is imperfect.
Future adaptation should be recency-weighted, reject outliers, detect posture
clusters, and ask for Quick Recenter when confidence drifts rather than pooling
every historical posture into one model.

Camera frames are never stored or transmitted. Only compact calibration
features and labels are persisted locally.

## Feedback design

Visual direction is instrument / monochrome: warm ink surfaces and one sparse
accent signal. The accent can follow macOS or use one custom color across the
control window, bloom, gaze indicator, and calibration. The desktop remains the
dominant surface.

Each display owns a click-through transparent AppKit panel so feedback works
across real display geometry and Spaces. A temporary proximity bloom is drawn
just inside the candidate screen perimeter:

- **Candidate:** a thin, brief edge light says the stable glance was recognized and the
  target is armed.
- **Dwell:** the same edge light creeps farther inward with dwell progress.
- **Confirmed:** a soft edge light creeps inward and disappears in about 720 ms.

The bloom is four clipped edge gradients plus a one-pixel hairline. It has no
center-origin stroke, shadow, persistent rectangle, or settling-state render.
The cue appears only after 180 ms of target stability; the armed cue expires
after 420 ms. Screen feedback can be disabled without turning Telepathy off.
The separately smoothed gaze-area ring is off by default and explicitly labeled
Experimental.

Permission and status text never appear in the desktop overlay. They belong in
the native control window and menu-bar menu.

## Technical architecture

```text
AVFoundation camera
        |
Apple Vision face landmarks
        |
        +--> head features --> per-layout display classifier
        |                              |
        |                       activation policy
        |                              |
        |                 remembered eligible window/display
        |                              |
        |                    AX focus + one pointer warp
        |
        +--> head + pupils --> exact desktop mapper --> Experimental only

physical clicks --> local labels for both models
```

Apple Head Pointer is not embedded because it owns pointer movement and does
not expose the tracking signal required for this interaction. Telepathy uses
public AVFoundation, Vision, ApplicationServices Accessibility, CoreGraphics,
and AppKit APIs directly.

## Experimental precision track

Exact window, control, and text placement remains behind Experimental. The
eventual model can learn from high-confidence clicks and caret placements, keep
separate posture/camera-geometry clusters, weight recent evidence, and validate
before promoting a calibration. A click is not always an exact gaze label, so
continuous learning must use confidence and reject contradictions.

Laptop movement, lid angle, camera position, lighting, glasses glare, and pose
can invalidate exact mapping. Coarse display classification should recover
quickly through Quick Recenter and click display labels; exact text placement
will require stronger validation and may need better hardware.

Clear glasses can work normally. Glare, tint, thick frames, or partial eye
occlusion reduce pupil reliability in Experimental precision mode. Main display
selection keeps working from head features when pupils disappear. Shipping
activation modes do not depend on eye or mouth landmarks.

## Known boundary: games

Exclusive fullscreen presentation, raw mouse input, cursor locking, missing
Accessibility windows, and anti-cheat systems can invalidate Telepathy's normal
assumptions. The product does nothing when it cannot find a public eligible
window. Game support is a later opt-in mode, not an MVP promise.
