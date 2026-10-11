import AppKit
import VeilCore

@MainActor final class MediaController: NSObject, NSWindowDelegate {
    weak var owner: AppDelegate?
    private(set) var source: Pane?
    private var panel: NSPanel?
    private var glass: GlassBackground?
    private var timer: Timer?
    private var wasDown = false
    private var dragStart: CGPoint?
    init(owner: AppDelegate) { self.owner = owner }
    func float(_ pane: Pane, show: Bool = true) {
        restore()
        guard let owner, let window = pane.window else { return }
        owner.pip.stop()
        source = pane
        let frame = window.convertToScreen(pane.convert(pane.bounds, to: nil))
        let panel = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Image / GIF"; panel.titlebarAppearsTransparent = true; panel.isReleasedWhenClosed = false; panel.delegate = self
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let background = GlassBackground(frame: root.bounds); background.autoresizingMask = [.width, .height]
        root.addSubview(background); panel.contentView = root
        pane.floating = true; pane.park(); pane.terminal.removeFromSuperview(); pane.terminal.isHidden = false
        pane.terminal.frame = root.bounds.insetBy(dx: 12, dy: 12); pane.terminal.autoresizingMask = [.width, .height]
        root.addSubview(pane.terminal)
        self.panel = panel; glass = background; apply(owner.configuration)
        if show { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(pane.terminal) }
        wasDown = false
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDrop() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func apply(_ config: Configuration) { if let panel { glass?.apply(config, window: panel) } }
    func restore() {
        timer?.invalidate(); timer = nil
        guard let source else { return }
        source.terminal.removeFromSuperview(); source.addSubview(source.terminal, positioned: .below, relativeTo: nil)
        source.terminal.autoresizingMask = []; source.floating = false; source.restore(); source.needsLayout = true; source.layoutSubtreeIfNeeded()
        panel?.delegate = nil; panel?.close(); panel = nil; glass = nil; self.source = nil
    }
    func checkDrop() {
        guard let owner, let source, let panel else { return }
        let down = NSEvent.pressedMouseButtons & 1 != 0
        defer { wasDown = down }
        if down && !wasDown {
            // Only a gesture beginning on this window can transfer its pane.
            let titleBar = NSRect(x: panel.frame.minX, y: panel.frame.maxY - 28, width: panel.frame.width, height: 28)
            dragStart = titleBar.contains(NSEvent.mouseLocation) ? panel.frame.origin : nil
        }
        guard wasDown && !down else { return }
        defer { dragStart = nil }
        guard let dragStart, hypot(panel.frame.minX - dragStart.x, panel.frame.minY - dragStart.y) > 8 else { return }
        let frame = panel.frame
        let targets = owner.active.panes.filter { $0 !== source && $0.isIdle && $0.window != nil }
        let scored = targets.map { pane -> (Pane, CGFloat) in
            let rect = owner.window.convertToScreen(pane.convert(pane.bounds, to: nil))
            let intersection = frame.intersection(rect)
            let area = max(1, min(frame.width * frame.height, rect.width * rect.height))
            return (pane, intersection.isNull ? 0 : intersection.width * intersection.height / area)
        }
        if let target = scored.max(by: { $0.1 < $1.1 }), target.1 >= 0.62 { restore(); owner.swap(source, target.0) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { restore(); return false }
}
