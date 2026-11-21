# Receiver preparation optimization

Measured locally on 2026-11-21, arm64 macOS 27.0.1, using the installed Swift
compiler with `swiftc -O`. CPU model is not recorded. This is a synthetic test
of Annex B scanning and AVCC block preparation, not a USB/Wi-Fi throughput,
decoder, presentation or end-to-end FPS test.

## Change

The receiver previously copied every NAL into temporary Data, copied it again
into AVCC Data, then copied AVCC into CoreMedia-owned memory. It now records
NAL byte ranges and writes length headers and picture bytes directly into one
CoreMedia-owned allocation. Parameter sets still receive persistent copies.
The frame deframing copy and hardware decoder are unchanged.

The scanner finds candidate trailing `1` bytes with libc `memchr`, then checks
their three preceding zeroes. Searching zeroes individually regressed badly on
zero-heavy payloads; that version was discarded. The final scanner falls back
to a scalar scan if `1` candidates are densely packed, avoiding excessive libc
calls on unusual payloads. The four-byte start-code wire contract is unchanged.

The decoder never borrows an escaping pointer into transient Swift Data.
CoreMedia allocates and owns the output memory. The writer validates ranges and
lengths before pointer access, including for sliced Data with nonzero indices.

## Results

Median CPU microseconds per frame from seven rounds, alternating old/new order,
after warmup. The benchmark compares the prior per-NAL-copy algorithm with the
actual production parser/writer. Each fixture contains two picture NALs and a
telemetry prefix. Fixtures are deterministic synthetic patterns, not captured
video. Output is consumed each iteration to keep the work observable.

| Synthetic payload | Old microseconds/frame | New microseconds/frame | Speedup |
| --- | ---: | ---: | ---: |
| 32 KiB, random nonzero bytes including `1` | 19.240 | 2.199 | 8.75x |
| 256 KiB, same distribution | 150.693 | 14.971 | 10.07x |
| 1 MiB keyframe-sized payload | 603.086 | 61.912 | 9.74x |
| 32 KiB, frequent zeroes | 20.093 | 1.991 | 10.09x |
| 32 KiB, frequent `1` bytes | 18.962 | 18.093 | 1.05x |

At 1 MiB this saves about 0.54 ms of CPU preparation per frame in this test.
For 32 KiB frames the saving is about 0.017 ms. Application latency also includes
encode, network, decode and refresh timing. These results cannot be interpreted
as a 9-10x increase in application FPS or physical link bandwidth. Real H.264/HEVC
recordings, older receivers and a ProMotion device remain needed for validation
beyond this isolated stage.

## Other changes

- Dropped captures share one replay timer instead of cancelling and creating a
  dispatch timer on every busy capture. It replays the latest frame and retries
  backpressure at the selected cadence.
- Encoder work has an epoch ticket. Callbacks from a retired capture/connection
  cannot decrement the new pending count or incorrectly open extra admission
  slots. Old callbacks are skipped before packet construction.
- Protocol version, frame bytes, codec selection and touch input are unchanged.

## Validation and reproduction

The 1,350 core assertions passed normally and under AddressSanitizer. They cover
400 generated scanner cases against the prior algorithm, byte-exact AVCC output,
short input, sliced Data, output ownership after input mutation, invalid ranges
and repeated encoder replacement. No screen capture or input is injected.

```sh
tools/fork/check-core.sh
tools/fork/check-core.sh --sanitize
tools/fork/check-sender.sh
tools/fork/check-receiver.sh
tools/fork/benchmark-receiver.sh
```

The actual sender implementation typechecks at macOS 14 and the actual shared
receiver typechecks at macOS 12. Existing concurrency warnings remain in the
compiler logs. The iOS sources parse, but full app builds and physical playback
remain outstanding because full Xcode and the iOS SDK are not installed.
