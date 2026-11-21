# OpenDisplay fork — development checkpoint

User goal: more efficient streaming over USB and Wi-Fi, a 120 Hz option, and
native touchscreen/gesture support (not just cursor emulation). Authorized
unattended implementation for a 24-hour window beginning about
2026-11-21 22:09 Asia/Qatar (19:09 UTC), with development passes at five-hour
intervals. Preserve all original attribution and GPL-3.0 licensing.

## Repository and environment

- Fork: https://github.com/mahmoudfaleh/opendisplay
- Upstream: https://github.com/peetzweg/opendisplay
- Branch: `feat/high-refresh-streaming`
- Local path: `/Users/mahmoud/Documents/Codex/2026-11-21/continue-this-by-making-you-goal/opendisplay`
- GitHub Desktop cloned the real fork with history; origin is the user's fork,
  upstream points to peetzweg. Shell GitHub access fails DNS in this sandbox.
  GitHub Desktop's authenticated UI can clone and may be needed to publish.
- Only Command Line Tools are installed; full Xcode, xcodegen, XCTest and the
  iOS SDK are unavailable. Do not claim an iOS application build passed.
- Initial free disk space: about 12 GiB. Source fits locally; no user files have
  been moved. Avoid downloading multi-gigabyte SDKs without checking space.
- Keep the upstream development bundle identities and TCC instructions in
  AGENTS.md. Do not replace the installed release OpenDisplay app.

## Scheduled passes

Automations created successfully in this conversation. They inherit the current
environment selection, but the service returned no explicit environment details.
The Mac must remain awake/connected for any local computer work.

| Pass | Qatar time | Focus |
| --- | --- | --- |
| Initial | Nov 21, 22:09 onward | Fork, inspect, implement cadence and packet path |
| +5h | Nov 22, 03:09 | Native touch/HID feasibility and compile checks |
| +10h | Nov 22, 08:09 | Streaming/backpressure/throughput measurements |
| +15h | Nov 22, 13:09 | Gesture/input implementation and compatibility |
| +20h | Nov 22, 18:09 | Integration, regression fixes, documentation |
| Final | Nov 22, 22:11 | Final validation and honest delivery report |

These are checkpoints, not guaranteed continuous execution. Each pass should
read this file, inspect git status, continue the highest priority unfinished work,
record real evidence, and make coherent commits. End the development window with
clear remaining limitations; never fake performance or native touch validation.

## Initial implementation

- Added persisted 30/60/120 Hz selection to the Mac sender UI (`-frameRate 120`
  also uses UserDefaults' existing launch-argument behavior).
- Propagated requested cadence through normal and capped-canvas negotiation,
  ScreenCaptureKit and encoder settings; maintained decoder throughput and
  H.264 level limits. Absent panel limits retain the legacy 60 FPS ceiling.
- Receiver H.264 offers and iOS HEVC offers now follow the panel's refresh limit
  up to 120. Added the iPhone ProMotion Info.plist flag in project.yml.
- Virtual display modes request the chosen cadence. If apply rejects a high-rate
  mode, creation retries at 60. Capture checks the actual CGDisplayMode rate and
  conservatively caps unknown/clamped sources at 60. Some OS versions may still
  prohibit >60 Hz virtual displays: requesting 120 is not proof of 120 distinct
  captured frames. Mirror on a genuine high-refresh display is a separate case.
- At >60 FPS, nominal bitrate scales with cadence (Best: 18 -> 36 Mbps at 120),
  preserving existing <=60 presets. This is a budget, not a measured link speed.
- Video framing now appends NAL bytes, timestamps and the length prefix into one
  builder buffer, preserving the existing wire bytes while removing per-NAL
  temporary Data objects and subsequent full-frame prefix copies.
- Send completions now ignore a retired connection so they cannot decrement a
  replacement connection's queue counter. The completion retains byte count
  instead of the whole frame merely to report statistics.
- Reject incomplete/noncontiguous NAL reads instead of sending truncated video.
  Consider CMBlockBufferCreateContiguous if hardware produces fragmented buffers.
- Added focused regressions runnable with `tools/fork/check-core.sh`, also wired
  into the full-Xcode MacTests target. Validation results are recorded below.

## Validation

- Initial `swiftc -parse` for Mac/Shared and iOS sources passed after edits.
- `git diff --check` passed.
- XCTest is unavailable in the installed Command Line Tools (`no such module
  XCTest`); a standalone production-core regression executable is provided.
- `tools/fork/check-core.sh`: **28 checks passed**, exercising high-refresh
  selection, legacy and decoder fallback, H.264 level limits, fractional pacing,
  source-rate validation and a 512 KiB multi-NAL packet's exact wire bytes.
- `tools/fork/check-sender.sh`: **passed** for the real Mac sender/capture/input/
  transport sources against the installed macOS SDK. Existing Swift concurrency
  warnings remain in `build/fork-core/sender-typecheck.log`; this is not a full
  app link/build and does not validate the Sparkle-dependent SwiftUI UI.
- No USB/Wi-Fi device, physical 120 Hz panel, or native contact injection test
  has passed yet. Do not describe throughput gains as measured.

## Highest priority remaining work

1. Preserve the passing core checks and sender typecheck; inspect any new changes
   before extending work. Full Xcode app/iOS builds remain outstanding.
2. Publish this feature branch to the fork through authenticated GitHub Desktop
   if terminal networking remains unavailable.
3. Follow research/fork-touch-investigation.md. Apple publishes touch reception
   docs and HID components; no reusable Sidecar injection source was found.
   Investigate a working direct-touch backend before claiming native support.
4. Improve scroll phases/precise deltas and gesture targeting without moving
   the cursor. Keep compatibility behavior explicitly identified.
5. Profile the frame packet builder and end-to-end transport with synthetic
   data. Test backpressure and old completion/reconnect races; preserve bounded
   latency rather than blindly enlarging buffers. Consider adaptive bitrate only
   with clear queue/latency evidence.
6. Verify actual high-refresh mode creation and capture cadence on this OS with
   an isolated probe; don't disturb the installed release app or existing screen
   permissions. Inspect on-glass presentation and decode workload on a ProMotion
   receiver once hardware/SDK access is available.
7. Revisit receiver advertising for untested decoder limits, thermal/low-power
   fallback, virtual-display resize fallback and hardware encoder limitations.
8. Update PROTOCOL.md/COMPATIBILITY.md and README with final implemented behavior
   and supported pairings. Preserve upstream controls and unknown-message safety.
