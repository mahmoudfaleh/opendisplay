import ColorSync
import CoreGraphics
import Foundation
import IOKit.hidsystem
import Security

/// One entitled virtual digitizer bound to an OpenDisplay display. Access
/// belongs to the sender queue. There is no listener or standalone input tool.
final class NativeTouchscreen {
    enum SetupError: LocalizedError {
        case missingEntitlement
        case displayUnavailable
        case deviceRejected

        var errorDescription: String? {
            switch self {
            case .missingEntitlement:
                return "the Mac sender lacks the Apple virtual HID signing entitlement"
            case .displayUnavailable:
                return "the extended display has no device UUID"
            case .deviceRejected:
                return "macOS rejected the virtual HID device; check the signing profile"
            }
        }
    }

    let session = UUID()
    let displayID: CGDirectDisplayID
    private let device: IOHIDUserDevice
    private var report = TouchscreenReport()

    init(displayID: CGDirectDisplayID, queue: DispatchQueue) throws {
        guard let task = SecTaskCreateFromSelf(nil),
              SecTaskCopyValueForEntitlement(task, "com.apple.developer.hid.virtual.device" as CFString,
                                            nil) as? Bool == true else {
            throw SetupError.missingEntitlement
        }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let displayUUID = CFUUIDCreateString(nil, uuid) else {
            throw SetupError.displayUnavailable
        }
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
        // Register the feature-report callback before the digitizer is visible
        // so the system can read its maximum contact count on discovery.
        guard let device = IOHIDUserDeviceCreateWithProperties(
            nil, properties as CFDictionary, IOHIDUserDeviceOptions.createOnActivate.rawValue
        ) else {
            throw SetupError.deviceRejected
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

    func send(_ contacts: [DirectTouchFrame.Contact]) -> IOReturn {
        var nextReport = report
        for bytes in nextReport.update(contacts) {
            let status = bytes.withUnsafeBytes { raw in
                IOHIDUserDeviceHandleReportWithTimeStamp(device, mach_absolute_time(),
                    raw.bindMemory(to: UInt8.self).baseAddress!, raw.count)
            }
            if status != kIOReturnSuccess { return status }
        }
        // Keep the previous contacts available for cleanup if submission fails.
        report = nextReport
        return kIOReturnSuccess
    }

    private static func millimetres(_ value: CGFloat, fallback: Int) -> Int {
        guard value.isFinite, value >= 1, value <= 6_553 else { return fallback }
        return Int(value.rounded())
    }
}
