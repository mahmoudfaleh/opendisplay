# Native touchscreen development build

OpenDisplay can now forward a snapshot of up to ten fingers from the iOS receiver
to an experimental virtual HID touchscreen. IOKit creates a device for the
extended display's UUID. Each report includes contact positions, IDs, finger
confidence and explicit lifts, so a receiving macOS app can use its own gesture
recognizers. Pencil uses its separate input path. When the native session is
unavailable the receiver uses its existing input mode.

## Build and try

1. Build both apps from the fork using the [repository build instructions](../README.md).
   Use macOS 27 or later for the sender.
2. For the Mac sender's Debug configuration, select an Apple Development
   certificate and a matching macOS App Development provisioning profile
   containing `com.apple.developer.hid.virtual.device`. The profile must match
   your app identifier and Mac. In the OpenSidecarMac target build settings,
   set **Code Signing Entitlements** for Debug to
   `Mac/NativeTouchDevelopment.entitlements`. A plist by itself does not grant
   the capability. The regular release build uses its own signing settings.
3. Launch the signed development sender with `-nativeTouch YES` in the Xcode
   scheme's launch arguments. Grant the dev sender its usual Screen Recording
   and Accessibility permissions. Connect a trusted iPhone or iPad over USB
   and choose **Extend**. Start the fork receiver on the device.
4. The receiver's **Settings → Status → Finger input** shows the negotiated
   mode. **Native touchscreen** confirms the sender opened the digitizer.
   To verify delivery, try a tap, one-finger scroll and two-finger pinch in a
   touch-aware macOS app on the extended display. Verify that the Mac's own
   display receives no touch and that unplugging during a gesture releases it.

Wi-Fi and Mirror continue to use the usual input mode. USB is the first
supported transport for the experiment because it uses the selected trusted
device and the existing Wi-Fi protocol lacks peer authentication.

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
- [Apollo PR #1624](https://github.com/ClassicOldSong/Apollo/pull/1624) reports
  that macOS 27.2.1 and 27.3 use a HID digitizer's `displayUUID` property to
  route direct touches. OpenDisplay independently implements this binding
  using ColorSync for the display UUID and the IOKit virtual device API.
- The installed SDK's `IOHIDUserDevice.h` and
  [Apple's entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device)
  specify virtual HID authorization. Apollo reports using a development
  provisioning profile for this capability.

Apple's actual Sidecar implementation was not available as source.

## Validation

Mac sender and shared receiver sources passed typechecking. The core checks
cover wire snapshots, per-finger tracking, release reports and rejection of
invalid input. Tests also passed under AddressSanitizer. The iOS sources passed
syntax parsing. This Mac runs 27.0.1, has Command Line Tools only and has no
valid signing identity. An unsigned IOKit device-creation probe returned nil
without sending any reports. Signed end-to-end gesture delivery remains open.

## ProMotion reference

[Optimizing iPhone and iPad apps to support ProMotion displays](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
requires CADisableMinimumFrameDurationOnPhone for >60 Hz iPhone presentation.
120 Hz is a request; heat, power mode and display scheduling may lower it.
