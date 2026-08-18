# Telepathy design

## Product thesis

The eyes already identify the next place a person intends to act. Telepathy
turns that signal into ordinary macOS focus, leaving the keyboard and mouse to
do what they already do well.

The product is not an eye-controlled mouse and should not feel like assistive
dwell control. Looking changes focus. Input remains normal.

The long-term opportunity is broader than switching monitors. A person should
eventually be able to look at a character, field, control, pane, or window and
begin typing or issuing a command there. In an editor, that could remove much of
the navigation ceremony associated with reaching a text location. It should
work beyond IDEs because the underlying primitive is universal: attention
chooses the target, then existing input acts on it.

## MVP contract

The MVP operates at window granularity:

1. Capture the built-in camera locally.
2. Estimate a point on the combined desktop from head and pupil features.
3. Identify the macOS Accessibility window under that point.
4. When the estimate moves into a different window, focus that window.
5. Warp the pointer once to the estimated point inside the new window.
6. Let all subsequent keyboard and mouse events flow through macOS normally.

Telepathy does not intercept, suppress, reinterpret, or replay ordinary
keyboard input. A space bar pauses a video only because the video window is now
the ordinary focused window.

### “Instant” behavior

Instant should mean no intentional dwell and no activation gesture. It cannot
mean acting on every raw camera frame because natural saccades and estimator
noise would thrash focus.

The initial defaults are therefore filters rather than interaction steps:

- Target stability: 90 ms.
- Physical mouse quiet period: 280 ms.
- Post-transfer cooldown: 240 ms.
- Gaze smoothing: 72 percent newest sample, 28 percent previous sample.
- Visual-indicator smoothing: 22 percent newest sample, 78 percent previous sample.

These values are hypotheses. Debug sessions should measure false switches,
missed switches, and time-to-focus before any number becomes product policy.

### Authority rules

- Physical mouse movement always wins and temporarily suspends gaze transfer.
- Cursor warping occurs only when changing windows, never continuously.
- `Command-Option-Escape` immediately pauses or resumes focus transfer.
- The control window and menu-bar item provide an ordinary persistent on/off control.
- Low-confidence or uncalibrated tracking does nothing.
- A target that cannot be identified through public Accessibility APIs does nothing.

## Calibration

The MVP learns passively from ordinary clicks. At mouse-down time, the pointer
location is a useful label for the most recent head and pupil features. A small
ridge-regression model maps those features into normalized coordinates across
the combined desktop.

Passive learning makes the app useful without a ritual, but the assumption is
not always true: people sometimes click while looking elsewhere. Future
versions should combine:

- Robust outlier rejection.
- Per-display models.
- Opportunistic labels from clicks and text-caret placement.
- A short explicit calibration only when passive confidence is insufficient.
- Drift detection for posture, lighting, camera position, and display changes.

Calibration samples are stored locally in the app's user defaults. Camera
frames are not stored or transmitted.

### Display layouts

The current runtime reads the active CoreGraphics displays whenever it maps a
prediction, unions their real bounds, and uses macOS's configured relative
positions. If the built-in display is arranged to the right of an external
display, that offset is part of the coordinate space automatically. Screen
changes also resize the overlay to the new desktop bounds.

The present calibration is normalized to the combined desktop but is not yet
keyed to a particular display layout. Reusing it after a display is moved,
rotated, disconnected, or replaced can therefore be inaccurate even though the
new bounds are detected correctly.

The intended calibration flow is explicit and short, never an unsolicited
full-screen ritual:

1. The user chooses `Calibrate` from the control window, or accepts a quiet
   suggestion when no profile matches the current display layout.
2. Telepathy shows inset corners and a center target across every active
   display, sampling stable head and pupil features at known coordinates.
3. The sequence completes in roughly ten seconds and stores a profile keyed by
   display identity, bounds, scale, and rotation.
4. Ordinary clicks continue refining that profile opportunistically.

Changing the layout selects another saved profile or offers calibration; it
must not silently reuse a geometrically incompatible mapping.

## Debug experience

The MVP intentionally ships with an optional, click-through gaze indicator:

- A thin gold ring represents an approximate gaze area, with separate visual
  smoothing so feedback can remain calm without slowing focus decisions.
- A hairline gold perimeter confirms an actual focus transfer and disappears
  after one second. It never remains around the current candidate window.

The overlay never displays permission, setup, or status messages over the
desktop. Those belong in the Telepathy control window and menu-bar menu. The
overlay also disappears while Telepathy is off or before a calibrated estimate
exists. The user can disable the indicator independently while focus tracking
continues.

Visual direction: instrument / monochrome. The desktop remains the dominant
surface; Telepathy adds one sparse warm-gold signal over neutral telemetry. The
overlay uses no blur, no large color fill, and no competing accent.

The control window follows the same instrument / monochrome direction: warm
ink surfaces, one gold state signal, compact native controls, and no decorative
dashboard chrome. Its switch is the authoritative persistent on/off control.

The likely steady-state feedback is the brief, faint perimeter confirmation
only when focus moves; the gaze-area ring is primarily a calibration and debug
instrument.

## Technical architecture

```text
AVFoundation camera
        |
Apple Vision landmarks
        |
head + pupil feature vector -------- mouse click labels
        |                                  |
        +------- adaptive gaze mapper -----+
                         |
                  desktop coordinate
                         |
          Accessibility point hit-testing
                         |
             stability and authority policy
                         |
          activate window + one cursor warp
```

Apple's built-in Head Pointer is not used because it owns pointer movement and
does not expose the raw tracking signal required for Telepathy's behavior.
Telepathy instead uses public Apple frameworks directly: AVFoundation, Vision,
ApplicationServices Accessibility, CoreGraphics, and AppKit.

## Known boundaries

### Games

Many games use exclusive fullscreen presentation, raw mouse input, cursor
locking, or accessibility trees with no meaningful windows or controls. Some
anti-cheat systems may also treat synthetic cursor positioning as suspicious.
The MVP should default to doing nothing when it cannot identify a public
Accessibility window. Game-specific support is a later, opt-in research area,
not an MVP compatibility promise.

### Precision

A laptop webcam is plausible for coarse monitor and window selection, but small
controls and exact text positions require better calibration and likely a
stronger gaze model. Head direction should carry monitor selection; pupil
features should refine the point inside that monitor. The debug overlay exists
to expose rather than conceal this uncertainty.

### Glasses and partial eye visibility

Clear lenses can work normally, but glare, tinted lenses, thick frames, or a
poor camera angle can obscure pupil landmarks. The current MVP requires both
pupils and drops frames where Vision cannot identify them. A later fusion model
should weight eye features by quality and fall back to head pose for coarse
display or window selection rather than losing the entire frame. Calibration
should be performed with the glasses and lighting the user normally uses.

### Focus semantics

macOS keyboard focus, frontmost application, focused window, first responder,
hover, and pointer position are different states. The MVP guarantees only the
public operations it performs: activate the application, focus and raise the
window where supported, and relocate the pointer. Individual apps remain
responsible for what a key does inside their restored responder chain.

## Roadmap

### 1. Window focus

Prove that monitor and window switching is faster than reaching for the mouse,
without producing disruptive false transfers.

### 2. Control focus

Use the Accessibility hierarchy to select a button, field, tab, or scroll area
without requiring pixel-perfect gaze. The interface should snap semantically to
the intended element while the pointer remains honest about the estimate.

### 3. Text placement

Place the insertion caret near the looked-at glyph. Accessibility text ranges
can cover standard controls; editor integrations may provide exact layout and
document coordinates where generic APIs cannot. Eye position selects the rough
location, and a tiny keyboard correction resolves ambiguity.

### 4. Universal attention input

Expose a local, permissioned attention-target API so editors, browsers, media
apps, terminals, and accessibility tools can respond semantically instead of
receiving only a synthetic pointer coordinate.

## MVP evaluation

Do not judge the MVP by whether the dot appears to follow a face. Record:

- Median and p95 gaze-to-focus latency.
- Intended window-transfer success rate.
- False transfers per hour.
- Transfers attempted during physical mouse use.
- Cursor landing distance from the user's next physical click.
- Calibration time until the model becomes usable.
- CPU use and camera frame-processing rate.

The MVP succeeds when switching to another visible window feels immediate,
ordinary keyboard input lands there, and Telepathy can remain enabled without
requiring conscious management.
