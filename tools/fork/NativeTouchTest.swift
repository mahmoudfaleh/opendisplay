import AppKit

/// Receives AppKit direct touches on its own window. It neither creates
/// an input device nor observes events sent to other applications.
private final class DirectContactRecognizer: NSGestureRecognizer {
    var onCountChanged: (Int) -> Void = { _ in }

    override func touchesBegan(with event: NSEvent) { update(with: event) }
    override func touchesMoved(with event: NSEvent) { update(with: event) }
    override func touchesEnded(with event: NSEvent) { update(with: event) }

    override func touchesCancelled(with event: NSEvent) {
        onCountChanged(0)
        state = .cancelled
    }

    private func update(with event: NSEvent) {
        let count = event.touches(matching: .touching, in: view).filter { $0.type == .direct }.count
        onCountChanged(count)
        if count > 0 {
            state = state == .possible ? .began : .changed
        } else if state != .possible {
            state = .ended
        }
    }
}

@main
@MainActor
final class NativeTouchTest: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = NativeTouchTest()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let testWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        testWindow.title = "OpenDisplay Direct Touch Test"
        testWindow.minSize = NSSize(width: 460, height: 280)
        testWindow.center()

        let canvas = NSView()
        canvas.allowedTouchTypes = .direct
        testWindow.contentView = canvas
        let instructions = NSTextField(labelWithString: "Move this window to the tablet and touch inside it.")
        let active = NSTextField(labelWithString: "Active fingers   0")
        active.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        let greatest = NSTextField(labelWithString: "Most at once   0")
        let labels = NSStackView(views: [instructions, active, greatest])
        labels.orientation = .vertical
        labels.alignment = .centerX
        labels.spacing = 14
        labels.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(labels)
        NSLayoutConstraint.activate([
            labels.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
        ])

        let recognizer = DirectContactRecognizer(target: nil, action: nil)
        recognizer.allowedTouchTypes = .direct
        var peak = 0
        recognizer.onCountChanged = { count in
            peak = max(peak, count)
            active.stringValue = "Active fingers   \(count)"
            greatest.stringValue = "Most at once   \(peak)"
        }
        canvas.addGestureRecognizer(recognizer)
        window = testWindow
        testWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
