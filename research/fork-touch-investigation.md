# Native touchscreen development build

OpenDisplay can forward a snapshot of up to ten fingers from the Android or
iOS receiver to an experimental virtual HID touchscreen. IOKit creates a device for the
extended display's UUID. Each report includes contact positions, IDs, finger
confidence and explicit lifts, so a receiving macOS app can use its own gesture
recognizers. Pencil uses its separate input path. When the native session is
unavailable the receiver uses its existing input mode.

## Build and try

1. Build the Mac sender from this branch and use it on macOS 27 or later.
   For Android, build the receiver with the [Android build instructions](../Android/README.md)
   or check [GitHub Actions](https://github.com/mahmoudfaleh/opendisplay/actions/workflows/fork-touch-test-apk.yml)
   for a successful **Android touchscreen test APK** run. The debug APK installs
   alongside the Play Store app as **OpenDisplay Dev**.
2. For the Mac sender's Debug configuration, select an Apple Development
   certificate and a matching macOS App Development provisioning profile
   containing `com.apple.developer.hid.virtual.device`. The profile must match
   your app identifier and Mac. In the OpenSidecarMac target build settings,
   set **Code Signing Entitlements** for Debug to
   `Mac/NativeTouchDevelopment.entitlements`. A plist by itself does not grant
   the capability. The regular release build uses its own signing settings.
3. Launch the signed development sender with `./run.sh -nativeTouch YES`
   or pass `-nativeTouch YES` in the Xcode scheme's launch arguments. Quit any
   running copy of OpenDisplay Dev first. Grant the dev sender its usual
   Screen Recording and Accessibility permissions. Choose **Extend**. On Android, use a data
   cable and choose the tablet under USB on the Mac. When the tablet prompts
   you, open **OpenDisplay Dev** for the USB accessory. On iOS, connect the
   trusted iPhone or iPad over USB and open the fork receiver.
4. The receiver's **Settings → Status → Finger input** shows the negotiated
   mode. The sender announces **Native touchscreen** after macOS accepts
   its first HID report. To verify AppKit delivery, run
   `open "$(tools/fork/build-touch-test.sh)"`, then move **OpenDisplay Direct
   Touch Test** to the tablet display. Press two fingers inside its window.
   **Most at once** should reach 2, and **Active fingers** should drop to 0
   when both lift. Check that unplugging mid-gesture clears the count and
   try one-finger scrolling and a two-finger pinch in a touch-aware app.

If native mode stays inactive, the Mac sender log distinguishes a missing
entitlement, a rejected device, and a failed HID report. An accepted HID
report confirms kernel submission. The test window checks the separate step
of macOS delivering those contacts to applications on the extended display.

Native touch on Android uses Android Open Accessory mode, so the tablet
does not need USB debugging. Wi-Fi, ADB forwarding and Mirror use pointer
compatibility. USB keeps native input scoped to the selected cabled device.

For an Android second screen today, the published OpenDisplay receiver works
with the standard Mac sender over USB or Wi-Fi. It provides tap, drag and
two-finger scrolling. The native path requires the fork receiver and Apple's
virtual HID entitlement on the Mac. [OpenDisplay downloads](https://opendisplay.app/).

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

The Android protocol tests exercise stable finger IDs, per-finger release,
cancellation, contact limits and JSON snapshots. The tablet build uses the
Android SDK. The Apple Development signing requirement applies to the Mac sender.

## ProMotion reference

[Optimizing iPhone and iPad apps to support ProMotion displays](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
requires CADisableMinimumFrameDurationOnPhone for >60 Hz iPhone presentation.
120 Hz is a request; heat, power mode and display scheduling may lower it.
