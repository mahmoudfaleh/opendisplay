import ColorSync
import CoreGraphics
import Foundation
import IOKit.hidsystem

/// One entitled virtual digitizer bound to an OpenDisplay display. Access
/// belongs to the sender queue. There is no listener or standalone input tool.
final class NativeTouchscreen {
    let session = UUID()
    let displayID: CGDirectDisplayID
    private let device: IOHIDUserDevice
    private var report = TouchscreenReport()

    init?(displayID: CGDirectDisplayID, queue: DispatchQueue) {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let displayUUID = CFUUIDCreateString(nil, uuid) else { return nil }
        let panel = CGDisplayScreenSize(displayID)
        let width = Self.millimetres(panel.width, fallback: 250)
        let height = Self.millimetres(panel.height, fallback: 160)
        let properties: [String: Any] = [
            "ReportDescriptor": TouchscreenReport.descriptor(widthMM: width, heightMM: height),
            "Product": "OpenDisplay Touchscreen",
            "Transport": "Virtual",
            "SerialNumber": session.uuidString,
            "PrimaryUsagePage": 0x0D,
            "PrimaryUsage": 0x04,
            "displayUUID": displayUUID,
            "Built-In": false,
        ]
        guard let device = IOHIDUserDeviceCreateWithProperties(nil, properties as CFDictionary, 0) else {
            return nil
        }
        self.displayID = displayID
        self.device = device
        IOHIDUserDeviceRegisterGetReportBlock(device) { type, id, bytes, length in
            guard type == kIOHIDReportTypeFeature, id == 2, length.pointee >= 2 else {
                return kIOReturnUnsupported
            }
            bytes[0] = 2
            bytes[1] = UInt8(TouchscreenReport.contactLimit)
            length.pointee = 2
            return kIOReturnSuccess
        }
        // IOKit requires the last reference to survive until cancellation
        // finishes. The callback queue can do this without blocking capture.
        let retainedDevice = Unmanaged.passRetained(device)
        IOHIDUserDeviceSetCancelHandler(device) { retainedDevice.release() }
        IOHIDUserDeviceSetDispatchQueue(device, queue)
        IOHIDUserDeviceActivate(device)
    }

    deinit {
        if !report.active.isEmpty { _ = send([]) }
        IOHIDUserDeviceCancel(device)
    }

    @discardableResult
    func send(_ contacts: [DirectTouchFrame.Contact]) -> Bool {
        for bytes in report.update(contacts) {
            let status = bytes.withUnsafeBytes { raw in
                IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(),
                    raw.bindMemory(to: UInt8.self).baseAddress!, raw.count)
            }
            if status != kIOReturnSuccess { return false }
        }
        return true
    }

    private static func millimetres(_ value: CGFloat, fallback: Int) -> Int {
        guard value.isFinite, value >= 1, value <= 6_553 else { return fallback }
        return Int(value.rounded())
    }
}
