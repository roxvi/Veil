// Standalone movable/resizable AX window for PiP verification. Never bundled.
import AppKit

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 130, y: 200, width: 480, height: 270),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Veil PiP Test Window"
        window.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.3, alpha: 1)
        let label = NSTextField(labelWithString: "PiP verification · move or resize this window")
        label.textColor = .white; label.alignment = .center; label.frame = NSRect(x: 0, y: 115, width: 480, height: 26)
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        window.contentView?.addSubview(label)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FixtureMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
