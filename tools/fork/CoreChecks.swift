import Foundation

/// SDK-independent regressions for the fork's negotiation and packet path.
/// Run with tools/fork/check-core.sh when the full Xcode SDK is unavailable.
enum ForkCoreChecks {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(description: message) }
            count += 1
        }
        let panel = PixelSize(width: 1920, height: 1080)
        let high = [VideoCapability(codec: "h264", maxFrameRate: 120)]
        func config(request: Int = 120, display: Int? = 120,
                    caps: [VideoCapability]? = high) throws -> VideoStreamConfiguration {
            try VideoStreamConfiguration.make(source: panel, quality: .best,
                receiverCapabilities: caps, displayMaxFrameRate: display,
                requestedFramesPerSecond: request)
        }

        let full = try config()
        try check(full.framesPerSecond == 120, "1080p120 must be selectable")
        try check(full.bitrate == 36_000_000, "120 FPS must preserve the nominal per-frame bit budget")
        let standard = try config(request: 60)
        try check(standard.framesPerSecond == 60 && standard.bitrate == 18_000_000,
                  "default 60 FPS preset must remain compatible")
        try check(try config(request: 30).framesPerSecond == 30, "30 FPS must be selectable")
        try check(try config(display: 60).framesPerSecond == 60, "60 Hz panel must cap high refresh")
        try check(try config(display: nil, caps: nil).framesPerSecond == 60,
                  "legacy receiver must not get 120 FPS")
        try check(try config(display: nil).framesPerSecond == 60, "missing panel ceiling must stay conservative")
        try check(try config(caps: [VideoCapability(codec: "h264", maxFrameRate: 30)]).framesPerSecond == 30,
                  "decoder ceiling must cap high refresh")
        try check(try config(caps: [VideoCapability(codec: "h264", maxFrameRate: 120,
                    maxPixelsPerSecond: panel.width * panel.height * 45)]).framesPerSecond == 45,
                  "decode throughput must cap high refresh")

        let canvas = try VideoStreamConfiguration.makeForCanvas(panel,
            panel: PixelSize(width: 2560, height: 1440), quality: .balanced,
            receiverCapabilities: high, displayMaxFrameRate: 120,
            requestedFramesPerSecond: 120)
        try check(canvas.framesPerSecond == 120, "capped canvas must propagate requested cadence")
        let fiveK = try VideoStreamConfiguration.make(source: PixelSize(width: 5120, height: 2880),
            quality: .best, receiverCapabilities: high, displayMaxFrameRate: 120,
            requestedFramesPerSecond: 120)
        let blocks = ((fiveK.encodedSize.width + 15) / 16) * ((fiveK.encodedSize.height + 15) / 16)
        try check(blocks <= VideoStreamConfiguration.maxMacroblocksPerFrame,
                  "high refresh must respect H264 frame limit")
        try check(blocks * fiveK.framesPerSecond <= VideoStreamConfiguration.maxMacroblocksPerSecond,
                  "high refresh must respect H264 macroblock throughput")
        try check(fiveK.framesPerSecond == 55, "5K H264 fallback regression")

        for (reported, expected) in [(120.0, 120), (119.88, 120), (60.0, 60), (30.0, 30),
                                     (0.0, 60), (-1.0, 60), (Double.nan, 60), (Double.infinity, 60)] {
            try check(StreamRefreshRate.sourceLimit(requested: 120, reported: reported) == expected,
                      "unexpected source rate handling for \(reported)")
        }
        try check(StreamRefreshRate.high.requestedRate(displayMaximum: nil) == 60,
                  "legacy panel cannot opt in to high refresh")
        try check(StreamRefreshRate.economy.requestedRate(displayMaximum: 120) == 30,
                  "panel must not raise the user's requested rate")

        var limiter = FrameRateLimiter(framesPerSecond: 120)
        let admitted = (0..<240).filter { limiter.shouldSubmit(at: Double($0) / 240) }.count
        try check(admitted == 120, "240 Hz capture must admit exactly 120 FPS")
        var oldLimiter = FrameRateLimiter(framesPerSecond: 55)
        let oldAdmitted = (0..<600).filter { oldLimiter.shouldSubmit(at: Double($0) / 60) }.count
        try check(abs(oldAdmitted - 550) <= 1, "fractional legacy cadence regression")

        // A large packet with multiple NALs must match the old byte-level wire
        // contract exactly, so old receivers need no parser changes.
        let metadata = Data("{\"cap\":123,\"snd\":124}".utf8)
        let nals = [Data([0x67, 0x42, 0, 0x34]), Data(repeating: 0x65, count: 512 * 1024)]
        var builder = WirePacketBuilder(prefix: metadata, payloadCapacity: 512 * 1024 + 128)
        var expectedPayload = metadata
        for nal in nals {
            builder.appendStartCode()
            nal.withUnsafeBytes { bytes in
                builder.append(bytes.bindMemory(to: UInt8.self).baseAddress!, count: bytes.count)
            }
            expectedPayload.append(contentsOf: [0, 0, 0, 1])
            expectedPayload.append(nal)
        }
        guard let packet = builder.finalize() else { throw Failure(description: "packet finalization failed") }
        let length = packet.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        try check(Int(length) == expectedPayload.count, "big-endian payload length mismatch")
        try check(packet.dropFirst(4) == expectedPayload, "metadata/Annex B wire compatibility regression")
        var empty = WirePacketBuilder()
        try check(empty.finalize() == Data([0, 0, 0, 0]), "empty framing regression")
        var encodes = EncodeWorkCounter()
        let retired = encodes.begin()
        try check(encodes.count == 1, "encode admission must occupy a slot")
        encodes.reset()
        let current = encodes.begin()
        encodes.finish(retired)
        try check(encodes.count == 1, "retired encoder callback must not release a current slot")
        try check(!encodes.isCurrent(retired) && encodes.isCurrent(current),
                  "encoder reset must retire its old work")
        encodes.finish(current)
        try check(encodes.count == 0, "current callback must release its slot")
        encodes.finish(current)
        try check(encodes.count == 0, "encode count must not underflow")
        for _ in 0..<500 {
            let old = encodes.begin()
            encodes.reset()
            let fresh = encodes.begin()
            encodes.finish(old)
            try check(encodes.count == 1, "repeated pipeline replacement must preserve current backpressure")
            encodes.finish(fresh)
        }
        let session = UUID()
        typealias Finger = DirectTouchFrame.Contact
        let left = Finger(id: 1, x: 0, y: 1)
        let right = Finger(id: 2, x: 1, y: 0)
        func frame(_ contacts: [Finger]) -> DirectTouchFrame {
            DirectTouchFrame(session: session, contacts: contacts)
        }
        let wireFrame = try JSONSerialization.data(withJSONObject: [
            "type": DirectTouchFrame.messageType, "session": session.uuidString,
            "contacts": [left.fields, right.fields],
        ])
        let decodedTouch = try JSONDecoder().decode(DirectTouchFrame.self, from: wireFrame)
        try check(decodedTouch.isValid && decodedTouch.session == session && decodedTouch.contacts == [left, right],
                  "direct touch wire format must preserve session and distinct finger coordinates")
        try check(frame([]).isValid, "empty touch frame must release all contacts")
        try check(!frame([left, left]).isValid, "duplicate finger IDs must be rejected")
        try check(!frame([Finger(id: 0, x: 0, y: 0)]).isValid, "zero contact ID must be rejected")
        try check(!frame([Finger(id: 11, x: 0, y: 0)]).isValid, "out-of-range contact ID must be rejected")
        try check(!frame([Finger(id: 1, x: 1.001, y: 0)]).isValid, "off-screen contact must be rejected")
        try check(!frame([Finger(id: 1, x: .nan, y: .infinity)]).isValid, "non-finite contact must be rejected")

        var touchReport = TouchscreenReport()
        let first = touchReport.update([left, right])
        try check(first.count == 1 && first[0].count == 102 && first[0].last == 2,
                  "HID report must have fixed byte size and two active contacts")
        try check(Array(first[0].prefix(7)) == [1, 7, 1, 0, 0, 255, 127],
                  "touch flags and edge coordinates must match the HID layout")
        try check(Array(first[0][11..<17]) == [7, 2, 255, 127, 0, 0],
                  "second finger must use its own ID and axes")
        let lift = touchReport.update([right])
        try check(lift.count == 2 && lift[0][1] == 4 && lift[0][11] == 7 && lift[1].last == 1,
                  "lifting a finger must end only its contact")
        let clear = touchReport.update([])
        try check(clear.count == 2 && clear[0][1] == 4 && clear[1].last == 0,
                  "disconnect must send a lift followed by an empty report")
        var replacement = TouchscreenReport()
        _ = replacement.update([left])
        let swap = replacement.update([right])
        try check(swap[0][2] == 1 && swap[0][1] == 4 && swap[1][2] == 2 && swap[1][1] == 7,
                  "an old finger must lift before a replacement finger goes down")
        count += try ReceiverCoreChecks.run()
        print("PASS: \(count) core regression checks")
    }
}
