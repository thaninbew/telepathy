# Performance contract

Telepathy is intended to remain enabled throughout the day. Runtime performance
is part of the product contract, not a release-note afterthought.

## Budgets

Measure an optimized release build after a 60-second warm-up with two displays,
a visible face, the control window closed, and the Experimental indicator off.

- Active steady state: at most 5% mean CPU and 8% p95 over two minutes.
- Off, screen asleep, or session locked: at most 0.5% mean CPU and no camera capture.
- Active footprint after five minutes: at most 150 MB.
- Head-motion-to-prediction p95: at most 100 ms.
- Handoff latency: no more than the configured delay plus 100 ms.
- No event-tap timeouts or unbounded memory growth.

Calibration is a deliberate, temporary detailed-analysis mode. Up to 20% mean
CPU is acceptable during that pass if memory remains bounded and the saved model
is not replaced on failure.

## Runtime strategy

- Normal display handoff uses `VNDetectFaceRectanglesRequest` at 15 fps.
- Calibration and the Experimental gaze indicator use detailed landmarks at 20 fps.
- Camera hardware cadence is constrained when supported, with a software gate as fallback.
- Accessibility focus context is sampled at 4 Hz rather than once per camera frame.
- Display geometry and classifier standardization are cached.
- Screen shine uses narrow layer-hosted edge strips; no full-screen transparent
  backing window remains resident.
- Off, sleep, lock, unavailable Accessibility, and normal single-display idle
  stop camera capture. The lightweight event tap remains for emergency re-enable.

## Measurement

Record the exact commit, display arrangement, settings, and camera mode for every run.

```sh
PID="$(pgrep -f '/Telepathy.app/Contents/MacOS/Telepathy$' | head -1)"
top -l 120 -s 1 -pid "$PID" -stats pid,cpu,mem,power,threads
xcrun xctrace record --template 'Time Profiler' --attach "$PID" \
  --time-limit 60s --output /tmp/Telepathy-Time-Profiler.trace
vmmap -summary "$PID"
```

Measure active steady state, continuous physical mouse movement, repeated
cross-display handoffs, Off, sleep/lock, and calibration separately. A green
unit-test suite does not substitute for measurements on the physical Mac.
