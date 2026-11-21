# Native touch investigation

Checked 2026-11-21. This is an implementation investigation, not a claim that
OpenDisplay already exposes a native macOS touchscreen.

## What Apple publishes

- [TN3212: Adopting gesture recognizers for Sidecar touch support](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)
  documents direct Sidecar touch reception in macOS 27 / iPadOS 27. Touches
  reach AppKit gesture recognizers, not NSApp/sendEvent or event monitors.
- [NSIsTouchNative](https://developer.apple.com/documentation/bundleresources/information-property-list/nsistouchnative)
  marks an application's own handling; adding it to a sender does not create
  a touch-capable display or inject touch into other applications.
- [Apple IOHIDFamily source](https://github.com/apple-oss-distributions/IOHIDFamily)
  is published, but is not the Sidecar implementation. Its
  [IOHIDUserClient](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDSystem/IOHIDUserClient.cpp)
  explicitly checks server-access entitlements. Other user-device paths need
  separate investigation; do not assume this one check covers every HID API.
- The installed macOS 27 SDK exposes NSScreen.touchCapabilities and AppKit
  gesture recognition. A supported API to register OpenDisplay's display for
  Sidecar-style direct-touch injection has not been identified.

No reusable Apple Sidecar source was found in this pass. Do not copy proprietary
framework binaries into the GPL project or describe a CGEvent pointer as native
touch. An optional independently implemented HID/DriverKit backend needs its own
capability probe, entitlements/signing investigation and real gesture-recognizer
tests before being enabled.

## Next implementation checks

1. Inspect current Apple IOKitUser/IOHIDFamily user-device APIs and entitlement
   checks, plus on-device public headers; identify a legal, loadable injection
   path for direct digitizer contacts on macOS 27.
2. Build a small opt-in probe that never posts input during ordinary builds.
   Test creation/destruction without changing system protections or private
   entitlements. A missing entitlement is a blocker, not permission to weaken
   SIP or bypass signing.
3. If viable, negotiate a distinct contact capability and transmit stable
   contact IDs, phases, normalized positions, timestamps and cancellation.
   Route only to the chosen virtual display, release all contacts on connection
   replacement/stop, and keep Pencil separate.
4. Verify reception by AppKit gesture recognizers in another test application,
   including one-finger pan, pinch/rotate, text selection and cancellation.
   Successful pointer events alone do not satisfy this test.
5. Independently improve compatibility scroll events (precise deltas and phases,
   targeting the gesture location without warping the cursor). Name this a
   compatibility backend. Do not silently report it as native multi-touch.

## ProMotion reference

[Optimizing iPhone and iPad apps to support ProMotion displays](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
requires CADisableMinimumFrameDurationOnPhone for >60 Hz iPhone presentation.
120 Hz is a request; heat, power mode and display scheduling may lower it.
